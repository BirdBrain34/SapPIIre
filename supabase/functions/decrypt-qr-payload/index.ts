import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const json = (payload: Record<string, unknown>) =>
  new Response(JSON.stringify(payload), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });

const base64ToBytes = (base64: string): Uint8Array => {
  const normalized = base64.replace(/\s+/g, '');
  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
};

const pemToPkcs8 = (pem: string): Uint8Array => {
  const body = pem
    .replace(/\\n/g, '')
    .replace(/\\r/g, '')
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace('-----BEGIN RSA PRIVATE KEY-----', '')
    .replace('-----END RSA PRIVATE KEY-----', '')
    .replace(/\s+/g, '');
  return base64ToBytes(body);
};

const arrayBufferFromBytes = (bytes: Uint8Array): ArrayBuffer => {
  return bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer;
};

const tryRsaOaepDecrypt = async (
  privateKeyDer: Uint8Array,
  encryptedAesKeyB64: string,
): Promise<{ aesKeyBuffer: ArrayBuffer | null; hashUsed: string | null }> => {
  const encryptedBytes = base64ToBytes(encryptedAesKeyB64);
  const encryptedBuffer = arrayBufferFromBytes(encryptedBytes);
  const derBuffer = arrayBufferFromBytes(privateKeyDer);

  for (const hash of ['SHA-1', 'SHA-256']) {
    try {
      const privateKey = await crypto.subtle.importKey(
        'pkcs8',
        derBuffer,
        { name: 'RSA-OAEP', hash },
        false,
        ['decrypt'],
      );

      const aesKeyBuffer = await crypto.subtle.decrypt(
        { name: 'RSA-OAEP' },
        privateKey,
        encryptedBuffer,
      );

      return { aesKeyBuffer, hashUsed: hash };
    } catch {
      // Try next hash variant.
    }
  }

  return { aesKeyBuffer: null, hashUsed: null };
};

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return json({ success: false, reason: 'method_not_allowed' });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const sessionId =
      typeof body?.sessionId === 'string' ? body.sessionId.trim() : '';

    if (!sessionId) {
      return json({ success: false, reason: 'missing_session_id' });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const privateKeyPem = Deno.env.get('RSA_PRIVATE_KEY_PEM');

    if (!supabaseUrl || !serviceRoleKey || !privateKeyPem) {
      return json({ success: false, reason: 'missing_env_vars' });
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const { data: row, error: fetchError } = await supabase
      .from('form_submission')
      .select(
        'id, encrypted_payload, payload_iv, encrypted_aes_key, transmission_version',
      )
      .eq('id', sessionId)
      .eq('transmission_version', 1)
      .maybeSingle();

    if (fetchError || !row) {
      return json({ success: false, reason: 'session_not_found_or_fetch_failed' });
    }

    const encryptedPayload = String(row.encrypted_payload ?? '').trim();
    const payloadIv = String(row.payload_iv ?? '').trim();
    const encryptedAesKey = String(row.encrypted_aes_key ?? '').trim();

    if (!encryptedPayload || !payloadIv || !encryptedAesKey) {
      return json({ success: false, reason: 'missing_encrypted_columns' });
    }

    let privateKeyDer: Uint8Array;
    try {
      privateKeyDer = pemToPkcs8(privateKeyPem);
    } catch {
      return json({ success: false, reason: 'invalid_private_key_pem' });
    }

    const rsaResult = await tryRsaOaepDecrypt(privateKeyDer, encryptedAesKey);
    if (!rsaResult.aesKeyBuffer) {
      return json({ success: false, reason: 'rsa_decrypt_failed' });
    }
    const aesKeyBytes = new Uint8Array(rsaResult.aesKeyBuffer);

    const aesKey = await crypto.subtle.importKey(
      'raw',
      aesKeyBytes,
      { name: 'AES-GCM' },
      false,
      ['decrypt'],
    ).catch(() => null);
    if (!aesKey) {
      return json({ success: false, reason: 'aes_key_import_failed' });
    }

    const payloadIvBuffer = arrayBufferFromBytes(base64ToBytes(payloadIv));
    const encryptedPayloadBuffer = arrayBufferFromBytes(
      base64ToBytes(encryptedPayload),
    );

    const decryptedPayloadBuffer = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: payloadIvBuffer },
      aesKey,
      encryptedPayloadBuffer,
    ).catch(() => null);
    if (!decryptedPayloadBuffer) {
      return json({ success: false, reason: 'aes_gcm_decrypt_failed' });
    }

    const decryptedText = new TextDecoder().decode(
      new Uint8Array(decryptedPayloadBuffer),
    );
    const parsedPayload = JSON.parse(decryptedText);

    const { error: updateError } = await supabase
      .from('form_submission')
      .update({ form_data: parsedPayload })
      .eq('id', sessionId)
      .eq('transmission_version', 1);

    if (updateError) {
      return json({ success: false, reason: 'update_failed' });
    }

    return json({ success: true, hashUsed: rsaResult.hashUsed });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'unknown_error';
    return json({ success: false, reason: 'decryption_failed', message });
  }
});

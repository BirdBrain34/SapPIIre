import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
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

Deno.serve(async (req: Request) => {
  console.log('[serve-submission-for-review] Function invoked');

  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return json({ success: false, reason: 'method_not_allowed' }, 405);
  }

  try {
    // --- Step 1: Parse request body ---
    const body = await req.json().catch(() => ({}));
    const sessionId = typeof body?.sessionId === 'string' ? body.sessionId.trim() : '';
    const staffId = typeof body?.staffId === 'string' ? body.staffId.trim() : '';
    const hashAlgo: string =
      typeof body?.hashAlgo === 'string' && body.hashAlgo.trim() !== ''
        ? body.hashAlgo.trim()
        : 'SHA-1';

    console.log(`[serve-submission-for-review] sessionId=${sessionId}, staffId=${staffId}, hashAlgo=${hashAlgo}`);

    // --- Step 1 (cont.): Validate inputs ---
    if (!sessionId) {
      return json({ success: false, reason: 'missing_session_id' }, 400);
    }
    if (!staffId) {
      return json({ success: false, reason: 'missing_staff_id' }, 400);
    }

    // --- Step 1 (cont.): Load environment ---
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const privateKeyPem = Deno.env.get('RSA_PRIVATE_KEY_PEM');

    if (!supabaseUrl || !serviceRoleKey || !privateKeyPem) {
      console.error('[serve-submission-for-review] Missing environment variables');
      return json({ success: false, reason: 'missing_env_vars' }, 500);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // --- Step 2: Staff authorization check ---
    const { data: staff, error: staffError } = await supabase
      .from('staff_accounts')
      .select('role, is_active, account_status')
      .eq('cswd_id', staffId)
      .single();

    if (staffError || !staff) {
      console.log(`[serve-submission-for-review] Staff not found: staffId=${staffId}`);
      return json({ success: false, reason: 'unauthorized' }, 403);
    }

    if (staff.is_active === false || staff.account_status !== 'active') {
      console.log(`[serve-submission-for-review] Inactive staff: staffId=${staffId}`);
      return json({ success: false, reason: 'unauthorized' }, 403);
    }

    if (staff.role === 'viewer') {
      console.log(`[serve-submission-for-review] Viewer insufficient permissions: staffId=${staffId}`);
      return json({ success: false, reason: 'insufficient_permissions' }, 403);
    }

    // --- Step 3: Fetch the encrypted envelope ---
    const { data: row, error: fetchError } = await supabase
      .from('form_submission')
      .select('id, encrypted_payload, payload_iv, encrypted_aes_key, transmission_version, status, expires_at')
      .eq('id', sessionId)
      .maybeSingle();

    if (fetchError || !row) {
      console.log(`[serve-submission-for-review] Session not found: sessionId=${sessionId}`);
      return json({ success: false, reason: 'session_not_found' }, 404);
    }

    // --- Step 3a: Expiry check ---
    if (row.expires_at && new Date(row.expires_at) < new Date()) {
      console.log(`[serve-submission-for-review] Session expired: sessionId=${sessionId} expires_at=${row.expires_at}`);
      return json({ success: false, reason: 'session_expired' }, 410);
    }

    if (row.transmission_version !== 1) {
      console.log(`[serve-submission-for-review] Session not encrypted (transmission_version=${row.transmission_version}): sessionId=${sessionId}`);
      return json({ success: false, reason: 'session_not_encrypted' }, 400);
    }

    const encryptedPayload = String(row.encrypted_payload ?? '').trim();
    const payloadIv = String(row.payload_iv ?? '').trim();
    const encryptedAesKey = String(row.encrypted_aes_key ?? '').trim();

    if (!encryptedPayload || !payloadIv || !encryptedAesKey) {
      console.log(`[serve-submission-for-review] Missing encrypted columns for sessionId=${sessionId}`);
      return json({ success: false, reason: 'missing_encrypted_columns' }, 400);
    }

    // --- Step 4: RSA-OAEP unwrap of AES key ---
    const privateKeyDer = pemToPkcs8(privateKeyPem);

    // Try SHA-1 first (matches Flutter encrypt package RSA-OAEP default), then SHA-256 as fallback
    let aesKeyBuffer: ArrayBuffer | null = null;
    for (const hash of [hashAlgo, 'SHA-256']) {
      try {
        const privateKey = await crypto.subtle.importKey(
          'pkcs8',
          arrayBufferFromBytes(privateKeyDer),
          { name: 'RSA-OAEP', hash },
          false,
          ['decrypt'],
        );
        aesKeyBuffer = await crypto.subtle.decrypt(
          { name: 'RSA-OAEP' },
          privateKey,
          arrayBufferFromBytes(base64ToBytes(encryptedAesKey)),
        );
        break;
      } catch {
        continue;
      }
    }

    if (!aesKeyBuffer) {
      console.error(`[serve-submission-for-review] RSA decryption failed for sessionId=${sessionId}`);
      return json({ success: false, reason: 'rsa_decrypt_failed' }, 500);
    }

    // --- Step 5: AES-GCM decryption of payload ---
    let decryptedBuffer: ArrayBuffer | null = null;
    try {
      const aesKey = await crypto.subtle.importKey(
        'raw',
        aesKeyBuffer,
        { name: 'AES-GCM' },
        false,
        ['decrypt'],
      );

      decryptedBuffer = await crypto.subtle.decrypt(
        { name: 'AES-GCM', iv: arrayBufferFromBytes(base64ToBytes(payloadIv)) },
        aesKey,
        arrayBufferFromBytes(base64ToBytes(encryptedPayload)),
      );
    } catch {
      decryptedBuffer = null;
    }

    if (!decryptedBuffer) {
      console.error(`[serve-submission-for-review] AES-GCM decryption failed for sessionId=${sessionId}`);
      return json({ success: false, reason: 'aes_gcm_decrypt_failed' }, 500);
    }

    const plaintext = new TextDecoder().decode(new Uint8Array(decryptedBuffer));
    const parsed = JSON.parse(plaintext) as Record<string, unknown>;

    // --- Step 6: Audit log write (fire-and-forget) ---
    try {
      await supabase.from('audit_logs').insert({
        action_type: 'submission_preview_decrypted',
        category: 'session',
        severity: 'warning',
        actor_id: staffId,
        target_type: 'form_submission',
        target_id: sessionId,
        details: { transmission_version: row.transmission_version },
      });
    } catch (err) {
      console.error(`[serve-submission-for-review] Audit log insert failed: ${err}`);
    }

    // --- Step 7: Return plaintext to caller (ephemeral — never written to DB) ---
    console.log(`[serve-submission-for-review] Successfully decrypted sessionId=${sessionId}`);
    return json({ success: true, data: parsed }, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : 'unknown_error';
    console.error(`[serve-submission-for-review] Error: ${message}`);
    return json({ success: false, reason: 'decryption_failed', message }, 500);
  }
});
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
  console.log('[decrypt-qr-payload] Function invoked');

  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    console.log('[decrypt-qr-payload] Non-POST request rejected');
    return json({ success: false, reason: 'method_not_allowed' }, 405);
  }

  // ── JWT Authentication ──────────────────────────────────────
  const authHeader = req.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return json({ success: false, reason: 'unauthorized' }, 401);
  }

  const token = authHeader.replace('Bearer ', '').trim();
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

  if (!supabaseUrl || !serviceRoleKey) {
    return json({ success: false, reason: 'server_config_error' }, 500);
  }

  const authClient = createClient(supabaseUrl, serviceRoleKey);
  const { data: { user }, error: authError } = await authClient.auth.getUser(token);

  if (authError || !user) {
    return json({ success: false, reason: 'invalid_token' }, 401);
  }

  console.log(`[decrypt-qr-payload] Authenticated user: ${user.id}`);

  try {
    const body = await req.json().catch(() => ({}));
    const sessionId =
      typeof body?.sessionId === 'string' ? body.sessionId.trim() : '';
    const hashAlgo: string =
      typeof body?.hashAlgo === 'string' && body.hashAlgo.trim() !== ''
        ? body.hashAlgo.trim()
        : 'SHA-1';

    console.log(`[decrypt-qr-payload] Validating sessionId=${sessionId}, hashAlgo=${hashAlgo}`);

    if (!sessionId) {
      return json({ success: false, reason: 'missing_session_id' });
    }

    const privateKeyPem = Deno.env.get('RSA_PRIVATE_KEY_PEM');

    if (!privateKeyPem) {
      return json({ success: false, reason: 'missing_env_vars' });
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const { data: row, error: fetchError } = await supabase
      .from('form_submission')
      .select(
        'id, encrypted_payload, payload_iv, encrypted_aes_key, transmission_version, status',
      )
      .eq('id', sessionId)
      .eq('transmission_version', 1)
      .maybeSingle();

    if (fetchError || !row) {
      console.log(`[decrypt-qr-payload] Session not found or fetch failed: sessionId=${sessionId}, error=${fetchError?.message}`);
      return json({ success: false, reason: 'session_not_found_or_fetch_failed' });
    }

    const encryptedPayload = String(row.encrypted_payload ?? '').trim();
    const payloadIv = String(row.payload_iv ?? '').trim();
    const encryptedAesKey = String(row.encrypted_aes_key ?? '').trim();

    if (!encryptedPayload || !payloadIv || !encryptedAesKey) {
      console.log(`[decrypt-qr-payload] Missing encrypted columns for sessionId=${sessionId}`);
      return json({ success: false, reason: 'missing_encrypted_columns' });
    }

    // Validation-only: do NOT decrypt the payload.
    // Update status to 'scanned' only if currently 'active' (guard against
    // overwriting a row already in a later state).
    const { error: updateError } = await supabase
      .from('form_submission')
      .update({ status: 'scanned', scanned_at: new Date().toISOString() })
      .eq('id', sessionId)
      .eq('status', 'active');

    if (updateError) {
      console.log(`[decrypt-qr-payload] Status update failed for sessionId=${sessionId}: ${updateError.message}`);
      return json({ success: false, reason: 'update_failed' });
    }

    console.log(`[decrypt-qr-payload] Successfully validated sessionId=${sessionId}`);
    return json({ success: true, hashUsed: null });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'unknown_error';
    console.error(`[decrypt-qr-payload] Error: ${message}`);
    return json({ success: false, reason: 'decryption_failed', message });
  }
});
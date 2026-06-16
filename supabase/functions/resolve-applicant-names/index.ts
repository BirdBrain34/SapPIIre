import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const base64ToBytes = (base64: string): Uint8Array => {
  const normalized = base64.replace(/\s+/g, '');
  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
};

const arrayBufferFromBytes = (bytes: Uint8Array): ArrayBuffer => {
  return bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer;
};

// Derive key using HMAC-SHA256 (same algorithm as derive-field-key)
async function deriveKey(secret: string, userId: string): Promise<Uint8Array> {
  const encoder = new TextEncoder();
  const keyBytes = await crypto.subtle.sign(
    'HMAC',
    await crypto.subtle.importKey(
      'raw',
      encoder.encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign'],
    ),
    encoder.encode(userId),
  );
  return new Uint8Array(keyBytes);
}

// Decrypt an AES-GCM field
async function decryptField(
  ciphertextB64: string,
  ivB64: string,
  aesKeyBytes: Uint8Array,
): Promise<string> {
  try {
    const ciphertext = base64ToBytes(ciphertextB64);
    const iv = base64ToBytes(ivB64);

    const aesKey = await crypto.subtle.importKey(
      'raw',
      aesKeyBytes,
      { name: 'AES-GCM' },
      false,
      ['decrypt'],
    );

    const decrypted = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: arrayBufferFromBytes(iv) },
      aesKey,
      arrayBufferFromBytes(ciphertext),
    );

    return new TextDecoder().decode(new Uint8Array(decrypted));
  } catch {
    return '';
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  try {
    const body = await req.json().catch(() => ({}));
    const userIds: string[] = Array.isArray(body?.userIds) ? body.userIds : [];
    const staffId: string = typeof body?.staffId === 'string' ? body.staffId.trim() : '';

    if (userIds.length === 0) {
      return new Response(
        JSON.stringify({ error: 'Missing required field: userIds' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!staffId) {
      return new Response(
        JSON.stringify({ error: 'Missing required field: staffId' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!supabaseUrl || !serviceRoleKey) {
      console.error('resolve-applicant-names error: Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
      return new Response(
        JSON.stringify({ error: 'Server configuration error' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // Step 1: Validate staff — any active staff role may resolve names
    const { data: staff, error: staffError } = await supabase
      .from('staff_accounts')
      .select('role, is_active, account_status')
      .eq('cswd_id', staffId)
      .single();

    if (staffError || !staff) {
      console.log(`[resolve-applicant-names] Staff not found: staffId=${staffId}`);
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (staff.is_active === false || staff.account_status !== 'active') {
      console.log(`[resolve-applicant-names] Inactive staff: staffId=${staffId}`);
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Load secrets
    const fieldKeySecretV2 = Deno.env.get('FIELD_KEY_HMAC_SECRET_V2');

    if (!fieldKeySecretV2) {
      console.error('resolve-applicant-names error: Missing required secrets');
      return new Response(
        JSON.stringify({ error: 'Server configuration error' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log(`[resolve-applicant-names] Processing ${userIds.length} userIds for staffId=${staffId}`);

    // Step 2: Resolve field IDs for first_name, middle_name, last_name
    const desiredCanonicalKeys = ['first_name', 'middle_name', 'last_name'];
    const bucketMap: Record<string, string> = {
      first_name: 'first',
      middle_name: 'middle',
      last_name: 'last',
    };

    const { data: fieldRows, error: fieldError } = await supabase
      .from('form_fields')
      .select('field_id, canonical_field_key')
      .in('canonical_field_key', desiredCanonicalKeys);

    if (fieldError) {
      console.error('resolve-applicant-names error: Failed to fetch form_fields:', fieldError);
      return new Response(
        JSON.stringify({ error: 'Database query failed' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const fieldIdToBucket: Record<string, string> = {};
    const candidateFieldIds: string[] = [];
    for (const row of (fieldRows as Array<Record<string, unknown>>) || []) {
      const fieldId = row['field_id']?.toString();
      const canonical = row['canonical_field_key']?.toString()?.trim()?.toLowerCase();
      if (fieldId && canonical && bucketMap[canonical]) {
        fieldIdToBucket[fieldId] = bucketMap[canonical];
        candidateFieldIds.push(fieldId);
      }
    }

    if (candidateFieldIds.length === 0) {
      return new Response(
        JSON.stringify({}),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Step 3: Fetch user_field_values for the given users and name fields
    const { data: valueRows, error: valuesError } = await supabase
      .from('user_field_values')
      .select('user_id, field_id, field_value, iv, encryption_version, updated_at')
      .in('user_id', userIds)
      .in('field_id', candidateFieldIds)
      .order('updated_at', { ascending: false });

    if (valuesError) {
      console.error('resolve-applicant-names error: Failed to fetch user_field_values:', valuesError);
      return new Response(
        JSON.stringify({ error: 'Database query failed' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Step 4: Organize and decrypt per user
    const namesByUser: Record<string, Record<string, string>> = {};
    const keyCache: Record<string, Uint8Array> = {};
    let decryptSuccessCount = 0;
    let decryptFailCount = 0;

    for (const row of (valueRows as Array<Record<string, unknown>>) || []) {
      const userId = row['user_id']?.toString();
      const fieldId = row['field_id']?.toString();
      const rawValue = row['field_value']?.toString() ?? '';

      if (!userId || !fieldId || !rawValue.trim() || rawValue === '__CLEARED__') {
        continue;
      }

      const bucket = fieldIdToBucket[fieldId];
      if (!bucket) continue;

      // Initialize user entry
      if (!namesByUser[userId]) {
        namesByUser[userId] = { last: '', first: '', middle: '' };
      }
      const target = namesByUser[userId];

      // Skip if we already have this bucket filled
      if ((target[bucket] ?? '').trim().length > 0) {
        continue;
      }

      const rawVersion = row['encryption_version'];
      const version = typeof rawVersion === 'number'
        ? rawVersion
        : parseInt(rawVersion?.toString() ?? '0', 10) || 0;

      // Cache keys per user
      if (!keyCache[userId]) {
        const keyBytes = await deriveKey(fieldKeySecretV2, userId);
        keyCache[userId] = keyBytes;
      }

      const key = keyCache[userId];

      let resolved = '';
      if (version === 2) {
        resolved = await decryptField(rawValue, row['iv']?.toString() ?? '', key);
      } else {
        // Unencrypted plaintext
        resolved = rawValue;
      }

      const clean = resolved.trim();
      if (clean && clean !== '__CLEARED__') {
        target[bucket] = clean;
        decryptSuccessCount++;
      } else {
        decryptFailCount++;
      }
    }

    const resolvedCount = Object.keys(namesByUser).length;
    console.log(
      `[resolve-applicant-names] Complete: ${resolvedCount} users resolved, ` +
      `${decryptSuccessCount} decrypts succeeded, ${decryptFailCount} failed`
    );

    return new Response(
      JSON.stringify(namesByUser),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    console.error('resolve-applicant-names error:', message);
    return new Response(
      JSON.stringify({ error: 'Name resolution failed', details: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
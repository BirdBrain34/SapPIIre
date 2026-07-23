import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

// Decrypt one AES-GCM payload. Extracted to keep the loop clean.
async function decryptOne(
  encryptedBase64: string,
  ivBase64: string,
  cryptoKey: CryptoKey,
): Promise<unknown | null> {
  try {
    const iv = Uint8Array.from(atob(ivBase64), (c) => c.charCodeAt(0));
    const ciphertext = Uint8Array.from(
      atob(encryptedBase64),
      (c) => c.charCodeAt(0),
    );
    const buffer = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv },
      cryptoKey,
      ciphertext,
    );
    return JSON.parse(new TextDecoder().decode(buffer));
  } catch {
    return null; // corrupted or wrong key — caller decides how to handle
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    const supabaseUrl    = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const serverAesKey   = Deno.env.get('SERVER_AES_KEY')!;

    const body = await req.json().catch(() => ({}));
    const { submissionIds } = body as { submissionIds: number[] };
    const staffId = typeof body?.staffId === 'string' ? body.staffId.trim() : '';

    console.log(`[decrypt-submission-batch] Received request with ${submissionIds?.length || 0} IDs, staffId=${staffId || 'none'}`);

    if (!Array.isArray(submissionIds) || submissionIds.length === 0) {
      console.log('[decrypt-submission-batch] Invalid or empty submissionIds array');
      return new Response(
        JSON.stringify({ error: 'submissionIds array required' }),
        { status: 400, headers: corsHeaders },
      );
    }

    // staffId is unconditionally required. This previously sat behind an
    // `if (staffId)` guard, so omitting it skipped authorization entirely.
    if (!staffId) {
      console.log('[decrypt-submission-batch] Missing staffId');
      return new Response(
        JSON.stringify({ error: 'Missing required field: staffId' }),
        { status: 400, headers: corsHeaders },
      );
    }

    // Hard cap: never decrypt more than 20 records per call
    const ids = submissionIds.slice(0, 20);
    console.log(`[decrypt-submission-batch] Processing ${ids.length} submissions (capped at 20)`);

    // Validate staff once — not per record. Account state is checked as well
    // as role, matching resolve-applicant-names: a deactivated or pending
    // account must not be able to decrypt records.
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const { data: staff } = await supabase
      .from('staff_accounts')
      .select('role, is_active, account_status')
      .eq('cswd_id', staffId)
      .single();

    if (!staff) {
      console.log(`[decrypt-submission-batch] Staff not found: staffId=${staffId}`);
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 403, headers: corsHeaders },
      );
    }

    if (staff.is_active === false || staff.account_status !== 'active') {
      console.log(`[decrypt-submission-batch] Inactive staff: staffId=${staffId}`);
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 403, headers: corsHeaders },
      );
    }

    if (staff.role === 'viewer') {
      console.log(`[decrypt-submission-batch] Insufficient permissions for staffId=${staffId}`);
      return new Response(
        JSON.stringify({ error: 'Insufficient permissions' }),
        { status: 403, headers: corsHeaders },
      );
    }

    const actorRole: string | null = staff.role;
    console.log(`[decrypt-submission-batch] Staff validated: ${staffId}, role=${staff.role}`);

    // Fetch all rows in ONE query — no loop network calls
    const { data: rows, error } = await supabase
      .from('client_submissions')
      .select('id, data, data_iv, data_encryption_version')
      .in('id', ids);

    if (error || !rows) {
      console.error('[decrypt-submission-batch] Fetch failed:', error?.message);
      return new Response(
        JSON.stringify({ error: 'Fetch failed' }),
        { status: 500, headers: corsHeaders },
      );
    }

    console.log(`[decrypt-submission-batch] Fetched ${rows.length} rows from database`);

    // Import key once, reuse across all decryptions
    const keyBytes = Uint8Array.from(atob(serverAesKey), (c) => c.charCodeAt(0));
    const cryptoKey = await crypto.subtle.importKey(
      'raw', keyBytes, { name: 'AES-GCM' }, false, ['decrypt'],
    );

    // Decrypt all in parallel — Promise.all, not sequential await
    const startTime = Date.now();
    const results = await Promise.all(
      rows.map(async (row) => {
        if (row.data_encryption_version !== 1) {
          // Plaintext — return as-is without touching crypto
          return { id: row.id, data: row.data, decrypted: false };
        }
        const payload = await decryptOne(row.data, row.data_iv, cryptoKey);
        return { id: row.id, data: payload, decrypted: payload !== null };
      }),
    );
    const elapsed = Date.now() - startTime;

    const decryptedCount = results.filter(r => r.decrypted).length;
    console.log(`[decrypt-submission-batch] Decrypted ${decryptedCount}/${rows.length} records in ${elapsed}ms`);

    // Audit: ONE aggregated critical event per batch call (not per record) so
    // routine list rendering doesn't flood the log. UI groups bursts further.
    if (decryptedCount > 0) {
      try {
        await supabase.from('audit_logs').insert({
          action_type: 'submission_decrypted',
          category: 'submission',
          severity: 'critical',
          actor_id: staffId,
          actor_role: actorRole,
          target_type: 'client_submission',
          details: {
            count: decryptedCount,
            ids: results.filter(r => r.decrypted).map(r => r.id),
            purpose: 'list_view',
          },
        });
      } catch (e) {
        console.error('[decrypt-submission-batch] Audit log insert failed:', e);
      }
    }

    return new Response(JSON.stringify({ results }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : 'Unknown error';
    console.error('[decrypt-submission-batch] Error:', msg);
    return new Response(
      JSON.stringify({ error: msg }),
      { status: 500, headers: corsHeaders },
    );
  }
});

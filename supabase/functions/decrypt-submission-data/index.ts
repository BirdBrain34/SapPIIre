import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-staff-id',
};

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
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const serverAesKey = Deno.env.get('SERVER_AES_KEY');

    if (!supabaseUrl || !serviceRoleKey || !serverAesKey) {
      console.error('decrypt-submission-data error: Missing environment variables');
      return new Response(
        JSON.stringify({ error: 'Server configuration error' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const body = await req.json().catch(() => ({}));
    const { submissionId, staffId } = body;

    if (!submissionId) {
      return new Response(
        JSON.stringify({ error: 'Missing submissionId' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate staff member if staffId provided
    const supabase = createClient(supabaseUrl, serviceRoleKey);
    let actorId = 'anonymous';
    
    if (staffId) {
      const { data: staffData, error: staffError } = await supabase
        .from('staff_accounts')
        .select('cswd_id, role')
        .eq('cswd_id', staffId)
        .single();

      if (staffError || !staffData) {
        return new Response(
          JSON.stringify({ error: 'Staff record not found' }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      const role = staffData.role;
      if (role === 'viewer') {
        return new Response(
          JSON.stringify({ error: 'Insufficient permissions: viewers cannot decrypt records' }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
      
      actorId = staffId;
    }

    // Fetch submission from database
    const { data: submission, error: fetchError } = await supabase
      .from('client_submissions')
      .select('data, data_iv, data_encryption_version')
      .eq('id', submissionId)
      .single();

    if (fetchError || !submission) {
      return new Response(
        JSON.stringify({ error: 'Submission not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Check if data is encrypted
    const version = submission.data_encryption_version || 0;
    if (version === 0) {
      // Plaintext data, return as-is
      return new Response(
        JSON.stringify({ data: submission.data }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Version 1: encrypted data
    const encryptedData = submission.data;
    const iv = submission.data_iv;

    if (!encryptedData || !iv) {
      return new Response(
        JSON.stringify({ error: 'Missing encrypted data or IV' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Import SERVER_AES_KEY
    const keyBytes = Uint8Array.from(atob(serverAesKey), c => c.charCodeAt(0));
    const cryptoKey = await crypto.subtle.importKey(
      'raw',
      keyBytes,
      { name: 'AES-GCM' },
      false,
      ['decrypt']
    );

    // Decrypt
    const ivBytes = Uint8Array.from(atob(iv), c => c.charCodeAt(0));
    const encryptedBytes = Uint8Array.from(atob(encryptedData), c => c.charCodeAt(0));

    const decryptedBuffer = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: ivBytes },
      cryptoKey,
      encryptedBytes
    );

    const decryptedText = new TextDecoder().decode(decryptedBuffer);
    const decryptedData = JSON.parse(decryptedText);

    // Log to audit_logs
    await supabase.from('audit_logs').insert({
      action_type: 'submission_decrypted',
      category: 'submission',
      severity: 'info',
      actor_id: actorId,
      details: { purpose: 'applicant_record_view' },
    });

    return new Response(
      JSON.stringify({ data: decryptedData }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    console.error('decrypt-submission-data error:', message);
    return new Response(
      JSON.stringify({ error: 'Decryption failed', details: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});

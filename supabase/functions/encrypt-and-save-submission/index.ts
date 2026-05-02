import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
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
    const body = await req.json().catch(() => ({}));
    const { sessionId, templateId, formCode, formType, data, intakeReference, createdBy } = body;

    if (!sessionId || !formType || !data) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: sessionId, formType, data' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const serverAesKey = Deno.env.get('SERVER_AES_KEY');
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!serverAesKey || !supabaseUrl || !serviceRoleKey) {
      console.error('encrypt-and-save-submission error: Missing environment variables');
      return new Response(
        JSON.stringify({ error: 'Server configuration error' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Generate random 12-byte IV
    const iv = crypto.getRandomValues(new Uint8Array(12));

    // Import SERVER_AES_KEY
    const keyBytes = Uint8Array.from(atob(serverAesKey), c => c.charCodeAt(0));
    const cryptoKey = await crypto.subtle.importKey(
      'raw',
      keyBytes,
      { name: 'AES-GCM' },
      false,
      ['encrypt']
    );

    // Encrypt data
    const dataString = JSON.stringify(data);
    const dataBytes = new TextEncoder().encode(dataString);
    const encryptedBuffer = await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv },
      cryptoKey,
      dataBytes
    );

    const encryptedBase64 = btoa(String.fromCharCode(...new Uint8Array(encryptedBuffer)));
    const ivBase64 = btoa(String.fromCharCode(...iv));

    // Generate intake reference using reference_counter
    const supabase = createClient(supabaseUrl, serviceRoleKey);
    
    let finalIntakeReference = intakeReference;
    if (!finalIntakeReference) {
      const { data: counterData, error: counterError } = await supabase.rpc('increment_reference_counter');
      if (!counterError && counterData) {
        const counter = counterData;
        const now = new Date();
        const year = now.getFullYear();
        const month = String(now.getMonth() + 1).padStart(2, '0');
        const day = String(now.getDate()).padStart(2, '0');
        const prefix = formCode?.trim() || 'FORM';
        finalIntakeReference = `${prefix.toUpperCase()}-${year}${month}${day}-${String(counter).padStart(6, '0')}`;
      }
    }

    // Insert encrypted data
    const { data: insertData, error: insertError } = await supabase
      .from('client_submissions')
      .upsert({
        session_id: sessionId,
        template_id: templateId,
        form_code: formCode,
        form_type: formType,
        data: encryptedBase64,
        data_iv: ivBase64,
        data_encryption_version: 1,
        created_by: createdBy,
        intake_reference: finalIntakeReference,
      }, { onConflict: 'session_id' })
      .select('id, intake_reference')
      .single();

    if (insertError) {
      console.error('encrypt-and-save-submission error:', insertError);
      return new Response(
        JSON.stringify({ error: 'Database insert failed', details: insertError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    return new Response(
      JSON.stringify({ id: insertData.id, intake_reference: insertData.intake_reference }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    console.error('encrypt-and-save-submission error:', message);
    return new Response(
      JSON.stringify({ error: 'Encryption failed', details: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});

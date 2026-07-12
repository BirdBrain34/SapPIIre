import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const SEMAPHORE_API_KEY = Deno.env.get('SEMAPHORE_API_KEY') ?? '';

// ── Rate limiting ──────────────────────────────────────────────
const OTP_RATE_LIMIT_WINDOW_MS = 600_000; // 10 minutes
const MAX_OTP_REQUESTS = 3;
const otpRateLimitStore = new Map<string, { count: number; windowStart: number }>();

function canRequestOtp(phone: string): boolean {
  const now = Date.now();
  const record = otpRateLimitStore.get(phone);
  if (!record || now - record.windowStart > OTP_RATE_LIMIT_WINDOW_MS) {
    otpRateLimitStore.set(phone, { count: 1, windowStart: now });
    return true;
  }
  if (record.count >= MAX_OTP_REQUESTS) {
    return false;
  }
  record.count++;
  return true;
}

// ── Cryptographically secure OTP generation ───────────────────
function generateSecureOtp(): string {
  // Use crypto.getRandomValues for true randomness (not time-based)
  const array = new Uint32Array(1);
  crypto.getRandomValues(array);
  const otp = (100000 + (array[0] % 900000)).toString();
  return otp;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ success: false, message: 'Method not allowed' }),
      { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  try {
    // Fail fast if the API key is missing
    if (!SEMAPHORE_API_KEY) {
      console.error('SEMAPHORE_API_KEY is not set in Supabase secrets!');
      return new Response(
        JSON.stringify({ success: false, message: 'SMS service not configured. Contact support.' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const { phone } = await req.json();

    if (!phone) {
      return new Response(
        JSON.stringify({ success: false, message: 'Phone number required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Rate limiting: max 3 OTP requests per 10 minutes per phone
    if (!canRequestOtp(phone)) {
      return new Response(
        JSON.stringify({ success: false, message: 'Too many OTP requests. Please wait 10 minutes.' }),
        { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Generate cryptographically secure OTP
    const otp = generateSecureOtp();

    // Call Semaphore API from the cloud (faster than from mobile)
    const semaphoreRes = await fetch('https://api.semaphore.co/api/v4/messages', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        apikey: SEMAPHORE_API_KEY,
        number: phone,
        message: `Your SapPIIre verification code is ${otp}. Do not share this with anyone.`,
      }),
    });

    // Always read the Semaphore response body for debugging
    const semaphoreBody = await semaphoreRes.text();
    console.log(`Semaphore response [${semaphoreRes.status}]: ${semaphoreBody}`);

    if (!semaphoreRes.ok) {
      return new Response(
        JSON.stringify({ success: false, message: `SMS send failed: ${semaphoreBody}` }),
        { status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Parse the Semaphore response to verify the SMS was actually queued.
    try {
      const parsed = JSON.parse(semaphoreBody);
      if (Array.isArray(parsed) && parsed.length > 0) {
        console.log(`SMS queued: message_id=${parsed[0]?.message_id}, status=${parsed[0]?.status}`);
      } else if (parsed?.error || parsed?.message) {
        console.error('Semaphore returned error payload:', semaphoreBody);
        return new Response(
          JSON.stringify({ success: false, message: `SMS service error: ${parsed.error || parsed.message}` }),
          { status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
    } catch {
      console.warn('Could not parse Semaphore response as JSON:', semaphoreBody);
    }

    // Save OTP to database
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    // Delete old OTP for this phone, then insert new one
    const { error: delError } = await supabase
      .from('phone_otp')
      .delete()
      .eq('phone', phone);

    if (delError) {
      console.error('Failed to delete old OTP:', delError);
    }

    const { error: insertError } = await supabase
      .from('phone_otp')
      .insert({
        phone,
        otp,
        expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
        created_at: new Date().toISOString(),
      });

    if (insertError) {
      return new Response(
        JSON.stringify({ success: false, message: 'Failed to save OTP' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    return new Response(
      JSON.stringify({ success: true, message: 'OTP sent successfully' }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (e) {
    return new Response(
      JSON.stringify({ success: false, message: (e as Error).message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
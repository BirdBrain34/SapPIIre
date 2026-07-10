import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// ── Rate limiting ──────────────────────────────────────────────
const VERIFY_RATE_LIMIT_WINDOW_MS = 900_000; // 15 minutes
const MAX_VERIFY_ATTEMPTS = 10;
const verifyRateLimitStore = new Map<string, { count: number; windowStart: number }>();

function canVerifyOtp(phone: string): boolean {
  const now = Date.now();
  const record = verifyRateLimitStore.get(phone);
  if (!record || now - record.windowStart > VERIFY_RATE_LIMIT_WINDOW_MS) {
    verifyRateLimitStore.set(phone, { count: 1, windowStart: now });
    return true;
  }
  if (record.count >= MAX_VERIFY_ATTEMPTS) {
    return false;
  }
  record.count++;
  return true;
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
    const { phone, otp } = await req.json();

    if (!phone || !otp) {
      return new Response(
        JSON.stringify({ success: false, message: 'Phone and OTP required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Rate limiting: max 10 verify attempts per 15 minutes per phone
    if (!canVerifyOtp(phone.trim())) {
      return new Response(
        JSON.stringify({ success: false, message: 'Too many verification attempts. Please wait 15 minutes.' }),
        { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    const { data: consumed, error } = await supabase
      .rpc('verify_and_consume_phone_otp', {
        p_phone: phone.trim(),
        p_otp:   otp.trim(),
      });

    if (error) {
      return new Response(
        JSON.stringify({ success: false, message: error.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!consumed) {
      return new Response(
        JSON.stringify({ success: false, message: 'Invalid or expired code.' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    return new Response(
      JSON.stringify({ success: true, message: 'Phone verified!' }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (e) {
    return new Response(
      JSON.stringify({ success: false, message: (e as Error).message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
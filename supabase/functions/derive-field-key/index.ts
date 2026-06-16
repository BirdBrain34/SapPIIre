import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Decode JWT payload without verification (we're extracting the sub claim
// from the JWT that Supabase Auth already verified on the gateway).
function getUserIdFromJwt(authHeader: string): string | null {
  try {
    const token = authHeader.replace('Bearer ', '').trim();
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const payload = JSON.parse(atob(parts[1]));
    return payload?.sub ?? null;
  } catch {
    return null;
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
    // JWT verification: extract the authenticated user from the Supabase Auth JWT
    const authHeader = req.headers.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized: missing or malformed Authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Extract userId from JWT payload (the JWT was already verified by Supabase gateway)
    const userId = getUserIdFromJwt(authHeader);
    if (!userId) {
      console.error('derive-field-key error: Could not extract userId from JWT');
      return new Response(
        JSON.stringify({ error: 'Unauthorized: invalid JWT' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Log userId for debugging (safe — logs the user ID, never the key)
    console.log(`[derive-field-key] Deriving key for userId=${userId}`);

    // Load secrets
    const fieldKeySecretV2 = Deno.env.get('FIELD_KEY_HMAC_SECRET_V2');

    if (!fieldKeySecretV2) {
      console.error('derive-field-key error: Missing required secrets (FIELD_KEY_HMAC_SECRET_V2)');
      return new Response(
        JSON.stringify({ error: 'Server configuration error' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Derive key = base64(HMAC-SHA256(secret, userId))
    const encoder = new TextEncoder();
    const userIdBytes = encoder.encode(userId);

    const v2KeyBytes = await crypto.subtle.sign(
      'HMAC',
      await crypto.subtle.importKey(
        'raw',
        encoder.encode(fieldKeySecretV2),
        { name: 'HMAC', hash: 'SHA-256' },
        false,
        ['sign'],
      ),
      userIdBytes,
    );

    // Convert ArrayBuffer to base64
    const v2KeyB64 = btoa(String.fromCharCode(...new Uint8Array(v2KeyBytes)));

    return new Response(
      JSON.stringify({ key: v2KeyB64, version: 2 }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    console.error('derive-field-key error:', message);
    return new Response(
      JSON.stringify({ error: 'Key derivation failed', details: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
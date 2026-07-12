#!/usr/bin/env node

/**
 * Session Enumeration & Edge Function Brute Force Test
 * 
 * Tests for:
 * - Predictable session IDs (form_submission)
 * - Unauthorized access to decryption endpoints
 * - Role-based access control bypass
 * - Edge Function authorization checks
 * 
 * WARNING: Only run against systems you own or have permission to test.
 */

import crypto from 'node:crypto';

const SUPABASE_URL = 'https://tgbfxepldpdswxehhlkx.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRnYmZ4ZXBsZHBkc3d4ZWhobGt4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA4NDYzMDcsImV4cCI6MjA4NjQyMjMwN30.DhoD6RHExKynXw34mibc3XRP-NwfmDnq1PttVM7-GL4';

// ============================================================
// TEST 1: Edge Function Authorization Check
// Tests if serve-submission-for-review properly validates auth
// ============================================================
async function testEdgeFunctionAuth() {
  console.log('\n══════════════════════════════════════════════');
  console.log('  EDGE FUNCTION AUTH TEST');
  console.log('══════════════════════════════════════════════');

  const endpoints = [
    'serve-submission-for-review',
    'decrypt-submission-batch',
    'decrypt-submission-data',
    'derive-field-key',
    'decrypt-qr-payload',
    'resolve-applicant-names',
    'encrypt-and-save-submission',
    'send-phone-otp',
    'verify-phone-otp',
  ];

  for (const endpoint of endpoints) {
    try {
      const res = await fetch(`${SUPABASE_URL}/functions/v1/${endpoint}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': SUPABASE_ANON_KEY,
        },
        body: JSON.stringify({ test: true }),
      });

      const body = await res.text();
      console.log(`  [${endpoint}] HTTP ${res.status}`);
      
      // If we get anything other than 401/403, it's interesting
      if (res.status === 200) {
        console.log(`    ⚠️  Endpoint returned 200 without auth! Body: ${body.slice(0, 100)}`);
      } else if (res.status === 401 || res.status === 403) {
        console.log(`    ✅ Properly rejecting unauthenticated requests`);
      } else {
        console.log(`    ℹ️  Status ${res.status}: ${body.slice(0, 100)}`);
      }
    } catch (e) {
      console.log(`  [${endpoint}] Error: ${e.message}`);
    }
  }
}

// ============================================================
// TEST 2: Test for UUID predictability in session IDs
// While UUIDv4 is generally secure, test the pattern anyway
// ============================================================
function analyzeUuidPattern() {
  console.log('\n══════════════════════════════════════════════');
  console.log('  SESSION ID (UUID) ANALYSIS');
  console.log('══════════════════════════════════════════════');

  console.log('');
  console.log('  Session IDs are UUIDs stored in form_submission.id');
  console.log('  UUIDv4 = 122 random bits = 5.3 x 10^36 possibilities');
  console.log('  ✅ Brute force is computationally infeasible');
  console.log('');
  console.log('  However, verify that Supabase is using UUIDv4:');
  console.log('  1. Check the default value in your Supabase schema');
  console.log('  2. gen_random_uuid() → UUIDv4 (secure)');
  console.log('  3. uuid_generate_v4() → UUIDv4 (secure)');
  console.log('  4. Serial/auto-increment → INSECURE (predictable!)');
  console.log('');
  console.log('  ⚠️  Automatic check requires database read access');
  console.log('  ⚠️  Manual check: Inspect a few session IDs');
  console.log('       - If they contain the same prefix → sequential');
  console.log('       - If they look random → UUIDv4');
}

// ============================================================
// TEST 3: Check if expired sessions still serve data
// ============================================================
async function testExpiredSessionBehavior() {
  console.log('\n══════════════════════════════════════════════');
  console.log('  EXPIRED SESSION TEST');
  console.log('══════════════════════════════════════════════');

  try {
    // Try accessing the serve-submission-for-review endpoint with no session
    const res = await fetch(`${SUPABASE_URL}/functions/v1/serve-submission-for-review`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': SUPABASE_ANON_KEY,
      },
      body: JSON.stringify({
        sessionId: '00000000-0000-0000-0000-000000000000',
        staffId: 'test-staff-id',
      }),
    });

    const data = await res.json();
    console.log(`  Response: ${JSON.stringify(data).slice(0, 300)}`);
    
    // The expected behavior per docs is HTTP 401 for unauthorized
    if (res.status === 401 || res.status === 403) {
      console.log('  ✅ Properly rejecting requests without valid auth');
    } else {
      console.log(`  ⚠️  Unexpected status ${res.status}`);
    }
  } catch (e) {
    console.log(`  Error: ${e.message}`);
  }
}

// ============================================================
// MAIN
// ============================================================
async function main() {
  console.log('');
  console.log('███████╗███████╗███████╗███████╗██╗ ██████╗ ███╗   ██╗');
  console.log('██╔════╝██╔════╝██╔════╝██╔════╝██║██╔═══██╗████╗  ██║');
  console.log('███████╗█████╗  ███████╗███████╗██║██║   ██║██╔██╗ ██║');
  console.log('╚════██║██╔══╝  ╚════██║╚════██║██║██║   ██║██║╚██╗██║');
  console.log('███████║███████╗███████║███████║██║╚██████╔╝██║ ╚████║');
  console.log('╚══════╝╚══════╝╚══════╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝');
  console.log('  BRUTE FORCE TEST — Session Enumeration & Edge Functions');
  console.log('========================================================');
  
  await testEdgeFunctionAuth();
  analyzeUuidPattern();
  await testExpiredSessionBehavior();
  
  console.log('\n══════════════════════════════════════════════');
  console.log('  RESULTS SUMMARY');
  console.log('══════════════════════════════════════════════');
  console.log('');
  console.log('  Edge Function Auth:');
  console.log('  - Verify above logs for any 200 responses without auth');
  console.log('  - All edge functions should require valid JWT');
  console.log('');
  console.log('  Session IDs:');
  console.log('  - Confirm gen_random_uuid() is used in the schema');
  console.log('  - Check for sequential patterns in form_submission.id');
  console.log('');
  console.log('  RECOMMENDATIONS:');
  console.log('  1. Verify every Edge Function validates JWT');
  console.log('  2. Add rate limiting to all Edge Functions');
  console.log('  3. Log and alert on repeated failed access attempts');
  console.log('  4. Implement IP-based blocking for abuse detection');
  console.log('');
}

main().catch(console.error);
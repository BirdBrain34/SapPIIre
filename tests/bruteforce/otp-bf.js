#!/usr/bin/env node

/**
 * OTP Brute Force Test
 * 
 * Tests the phone and email OTP verification endpoints
 * for rate limiting and guessability.
 * 
 * WARNING: Only run against systems you own or have permission to test.
 */

// ============================================================
// CONFIGURATION
// ============================================================
const SUPABASE_URL = 'https://tgbfxepldpdswxehhlkx.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRnYmZ4ZXBsZHBkc3d4ZWhobGt4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA4NDYzMDcsImV4cCI6MjA4NjQyMjMwN30.DhoD6RHExKynXw34mibc3XRP-NwfmDnq1PttVM7-GL4';

const TEST_PHONE = '+639123456789'; // Replace with actual test phone
const TEST_EMAIL = 'test@sappiire.phone'; // Replace with actual test email

// ============================================================
// TEST 1: Phone OTP via Edge Function
// Uses the send-phone-otp / verify-phone-otp endpoints
// ============================================================
async function testPhoneOtpRateLimiting() {
  console.log('\n══════════════════════════════════════════════');
  console.log('  PHONE OTP RATE LIMITING TEST');
  console.log('══════════════════════════════════════════════');

  try {
    // Step 1: Request an OTP
    console.log('  [1] Requesting phone OTP...');
    const sendRes = await fetch(`${SUPABASE_URL}/functions/v1/send-phone-otp`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
      },
      body: JSON.stringify({ phone: TEST_PHONE }),
    });
    const sendData = await sendRes.json();
    console.log(`      Response: ${JSON.stringify(sendData)}`);

    // Step 2: Try rapid OTP verification attempts (rate limit test)
    console.log('  [2] Sending rapid verification attempts...');
    let rateLimited = false;
    for (let i = 0; i < 15; i++) {
      const otp = String(100000 + i); // Try sequential OTPs
      
      try {
        const verifyRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/verify_and_consume_phone_otp`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'apikey': SUPABASE_ANON_KEY,
            'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
          },
          body: JSON.stringify({
            p_phone: TEST_PHONE,
            p_otp: otp,
          }),
        });
        
        const data = await verifyRes.json();
        
        if (verifyRes.status === 429) {
          console.log(`  ✅ Rate limited at attempt ${i + 1}`);
          rateLimited = true;
          break;
        }
        
        // If we get a success, that's interesting (means OTP was guessable)
        if (data === true) {
          console.log(`  ⚠️  OTP GUESSED at attempt ${i + 1}: ${otp}`);
        }
      } catch (e) {
        // Continue
      }
      
      // No delay - testing for rate limiting
    }
    
    if (!rateLimited) {
      console.log(`  ❌ No rate limiting detected after 15 rapid OTP attempts`);
    }

    // Step 3: Test via the Supabase Auth OTP endpoint
    console.log('  [3] Testing Supabase Auth OTP rate limiting...');
    const authOtpRes = await fetch(`${SUPABASE_URL}/auth/v1/verify`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': SUPABASE_ANON_KEY,
      },
      body: JSON.stringify({
        email: TEST_EMAIL,
        token: '000000',
        type: 'email',
      }),
    });
    const authOtpData = await authOtpRes.json();
    console.log(`      Status: ${authOtpRes.status}`);
    console.log(`      Response: ${JSON.stringify(authOtpData).slice(0, 200)}`);
    
    return !rateLimited;
  } catch (e) {
    console.log(`  Error: ${e.message}`);
    return true; // Assume not rate limited
  }
}

// ============================================================
// TEST 2: Supabase Email OTP Rate Limiting
// ============================================================
async function testEmailOtpRateLimiting() {
  console.log('\n══════════════════════════════════════════════');
  console.log('  EMAIL OTP RATE LIMITING TEST');
  console.log('══════════════════════════════════════════════');

  try {
    // Try sending multiple OTP requests
    console.log('  Sending 5 rapid OTP requests...');
    let rateLimited = false;
    
    for (let i = 0; i < 5; i++) {
      const res = await fetch(`${SUPABASE_URL}/auth/v1/otp`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': SUPABASE_ANON_KEY,
        },
        body: JSON.stringify({
          email: TEST_EMAIL,
          create_user: false,
        }),
      });
      
      if (res.status === 429) {
        console.log(`  ✅ Rate limited at request ${i + 1}`);
        rateLimited = true;
        break;
      }
    }
    
    if (!rateLimited) {
      console.log(`  ❌ No rate limiting on email OTP requests`);
    }
    
    return !rateLimited;
  } catch (e) {
    console.log(`  Error: ${e.message}`);
    return true;
  }
}

// ============================================================
// TEST 3: OTP Code Space Analysis
// ============================================================
function analyzeOtpSpace() {
  console.log('\n══════════════════════════════════════════════');
  console.log('  OTP CODE SPACE ANALYSIS');
  console.log('══════════════════════════════════════════════');
  
  console.log('  Phone OTPs: 6-digit numeric code');
  console.log('  Total combinations: 1,000,000');
  console.log('  At 10 attempts/second: ~28 hours to exhaust');
  console.log('  At 100 attempts/second: ~2.8 hours');
  console.log('  At 1000 attempts/second: ~17 minutes');
  console.log('');
  console.log('  Email OTPs: 6-digit numeric code (Supabase default)');
  console.log('  Same analysis applies');
  console.log('');
  console.log('  ⚠️  Without rate limiting, OTPs are guessable');
  console.log('  ⚠️  With sequential OTPs, attacker can narrow search');
}

// ============================================================
// MAIN
// ============================================================
async function main() {
  console.log('');
  console.log('██████╗ ████████╗██████╗ ');
  console.log('██╔══██╗╚══██╔══╝██╔══██╗');
  console.log('██████╔╝   ██║   ██████╔╝');
  console.log('██╔═══╝    ██║   ██╔═══╝ ');
  console.log('██║        ██║   ██║     ');
  console.log('╚═╝        ╚═╝   ╚═╝     ');
  console.log('  BRUTE FORCE TEST — OTP Endpoints');
  console.log('==============================================');
  
  // Analysis first
  analyzeOtpSpace();
  
  // Test phone OTP
  console.log('\n  ⚠️  Skipping live phone OTP test (requires real test phone number)');
  console.log('  ⚠️  Set TEST_PHONE and TEST_EMAIL in otp-bf.js to run live tests');
  console.log('  ⚠️  Or configure a test phone number in Supabase dashboard first');
  
  // Analysis only mode
  console.log('\n  MANUAL TEST STEPS:');
  console.log('  1. Create a test phone number in Supabase');
  console.log('  2. Update TEST_PHONE in this script');
  console.log('  3. Run: node otp-bf.js');
  console.log('  4. Check for rate limiting at 6+ attempts');
  console.log('');
  
  console.log('  ⚠️  Key finding for OTP security:');
  console.log('  The verify-phone-otp Edge Function should implement:');
  console.log('    - Rate limiting by phone number (max 5 attempts/hour)');
  console.log('    - OTP expiration (5-10 minutes)');
  console.log('    - Exponential backoff on failed attempts');
  console.log('    - One-time use (already implemented via rpc)');
  console.log('');
}

main().catch(console.error);
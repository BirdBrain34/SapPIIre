#!/usr/bin/env node

/**
 * SHA-256 Hash Cracking Demo
 * 
 * Demonstrates how fast SHA-256 passwords can be cracked.
 * This is the same hash used by web_auth_service.dart.
 * 
 * WARNING: Only use against your own hashes.
 */

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ============================================================
// SHA-256 hash function (same as web_auth_service.dart)
// ============================================================
function sha256(password) {
  return crypto.createHash('sha256').update(password, 'utf-8').digest('hex');
}

// ============================================================
// Generate a sample password hash for demonstration
// ============================================================
function generateSampleHash() {
  // These are example passwords - NOT real credentials
  const samplePasswords = [
    'password123',
    'admin2025',
    'cswd2026!',
    'Staff@123',
    'P@ssw0rd!',
  ];
  
  console.log('\n  Sample password hashes (SHA-256):');
  console.log('  ─────────────────────────────────────');
  for (const pw of samplePasswords) {
    console.log(`  ${pw.padEnd(20)} → ${sha256(pw)}`);
  }
  console.log('');
}

// ============================================================
// Dictionary attack simulation
// ============================================================
function dictionaryAttack(targetHash, wordlist) {
  console.log('\n══════════════════════════════════════════════');
  console.log('  DICTIONARY ATTACK SIMULATION');
  console.log('══════════════════════════════════════════════');
  
  const start = process.hrtime.bigint();
  let found = false;
  let attempts = 0;
  
  for (const word of wordlist) {
    attempts++;
    const hash = sha256(word);
    
    if (hash === targetHash) {
      const end = process.hrtime.bigint();
      const elapsedMs = Number(end - start) / 1_000_000;
      console.log(`  ✅ FOUND: "${word}"`);
      console.log(`  Attempts: ${attempts.toLocaleString()}`);
      console.log(`  Time: ${elapsedMs.toFixed(2)}ms`);
      found = true;
      break;
    }
    
    // Show progress every 100K attempts
    if (attempts % 100000 === 0) {
      const end = process.hrtime.bigint();
      const elapsedMs = Number(end - start) / 1_000_000;
      const rate = Math.round(attempts / (elapsedMs / 1000));
      console.log(`  Progress: ${attempts.toLocaleString()} attempts (${rate.toLocaleString()}/s)`);
    }
  }
  
  if (!found) {
    const end = process.hrtime.bigint();
    const elapsedMs = Number(end - start) / 1_000_000;
    console.log(`  ❌ Password not found in ${attempts.toLocaleString()} attempts`);
    console.log(`  Time: ${(elapsedMs / 1000).toFixed(1)}s`);
  }
  
  return found;
}

// ============================================================
// Brute force attack simulation (limited character set)
// ============================================================
function bruteForceSimulation() {
  console.log('\n══════════════════════════════════════════════');
  console.log('  BRUTE FORCE SPACE ANALYSIS');
  console.log('══════════════════════════════════════════════');
  
  const charsets = {
    'lowercase': 'abcdefghijklmnopqrstuvwxyz',
    'lower+digits': 'abcdefghijklmnopqrstuvwxyz0123456789',
    'alphanumeric': 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
    'full': 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-=[]{}|;:,.<>?',
  };
  
  // Benchmark hash speed
  const iterations = 50000;
  const start = process.hrtime.bigint();
  for (let i = 0; i < iterations; i++) {
    sha256(`test${i}`);
  }
  const end = process.hrtime.bigint();
  const elapsedMs = Number(end - start) / 1_000_000;
  const hashesPerSec = Math.round(iterations / (elapsedMs / 1000));
  
  console.log(`  Hash speed: ${hashesPerSec.toLocaleString()} hashes/sec (Node.js)`);
  console.log(`  GPU speed (estimate): ${(hashesPerSec * 500).toLocaleString()} hashes/sec`);
  console.log('');
  console.log('  Time to crack by password length:');
  console.log('  ─────────────────────────────────────────────────────────────');
  console.log('  Length │ Charset       │ Combinations  │ Node.js Time  │ GPU Time');
  console.log('  ───────┼───────────────┼───────────────┼───────────────┼──────────────');
  
  for (const [name, charset] of Object.entries(charsets)) {
    for (let len = 4; len <= 10; len += 2) {
      const combos = Math.pow(charset.length, len);
      const nodeTime = combos / hashesPerSec;
      const gpuTime = combos / (hashesPerSec * 500);
      
      const nodeStr = nodeTime < 60 
        ? `${nodeTime.toFixed(1)}s`
        : nodeTime < 3600 
          ? `${(nodeTime / 60).toFixed(1)}m`
          : nodeTime < 86400
            ? `${(nodeTime / 3600).toFixed(1)}h`
            : `${(nodeTime / 86400).toFixed(1)}d`;
      
      const gpuStr = gpuTime < 60 
        ? `${gpuTime.toFixed(1)}s`
        : gpuTime < 3600 
          ? `${(gpuTime / 60).toFixed(1)}m`
          : gpuTime < 86400
            ? `${(gpuTime / 3600).toFixed(1)}h`
            : `${(gpuTime / 86400).toFixed(1)}d`;
      
      console.log(`  ${len}       │ ${name.padEnd(13)} │ ${combos.toExponential(1).padEnd(13)} │ ${nodeStr.padEnd(13)} │ ${gpuStr}`);
    }
  }
  console.log('');
  console.log('  ⚠️  With SHA-256, an 8-char lowercase password falls in ~2 hours on GPU');
  console.log('  ⚠️  With bcrypt (cost=10), same password would take YEARS');
  console.log('');
}

// ============================================================
// Generate a test wordlist for the dictionary attack
// ============================================================
function generateTestWordlist() {
  const common = [
    'password', '123456', '12345678', 'qwerty', 'admin', 'letmein',
    'welcome', 'monkey', 'dragon', 'master', 'sunshine', 'princess',
    'football', 'iloveyou', 'trustno1', 'abc123', 'passw0rd',
    'admin123', 'changeme', 'secret', 'test123', 'staff123',
    'cswd2025', 'cswd2026', 'sappiire', 'SapPIIre', 'default',
    'Password1', 'P@ssw0rd', 'Welcome1', 'Admin123',
  ];
  
  // Add variations
  const wordlist = [...common];
  for (const word of common) {
    wordlist.push(word.toUpperCase());
    wordlist.push(word.charAt(0).toUpperCase() + word.slice(1));
    wordlist.push(word + '!');
    wordlist.push(word + '123');
    wordlist.push(word + '2025');
    wordlist.push(word + '2026');
  }
  
  return [...new Set(wordlist)];
}

// ============================================================
// MAIN
// ============================================================
async function main() {
  console.log('');
  console.log('██╗  ██╗ █████╗ ███████╗██╗  ██╗');
  console.log('██║  ██║██╔══██╗██╔════╝██║  ██║');
  console.log('███████║███████║███████╗███████║');
  console.log('██╔══██║██╔══██║╚════██║██╔══██║');
  console.log('██║  ██║██║  ██║███████║██║  ██║');
  console.log('╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝');
  console.log('  CRACKING DEMO — SHA-256 Password Audit');
  console.log('==============================================');
  
  // Show sample hashes
  generateSampleHash();
  
  // Brute force analysis
  bruteForceSimulation();
  
  // Dictionary attack demo
  console.log('══════════════════════════════════════════════');
  console.log('  LIVE DICTIONARY ATTACK DEMO');
  console.log('══════════════════════════════════════════════');
  
  const wordlist = generateTestWordlist();
  console.log(`  Wordlist size: ${wordlist.length} passwords`);
  
  // Pick a password from the wordlist to demonstrate
  const targetPassword = wordlist[Math.floor(Math.random() * wordlist.length)];
  const targetHash = sha256(targetPassword);
  console.log(`  Target hash: ${targetHash}`);
  console.log(`  (Password is one of the ${wordlist.length} common passwords)`);
  
  const found = dictionaryAttack(targetHash, wordlist);
  
  if (!found) {
    console.log('\n  ⚠️  Password not in wordlist (but it should be — check logic)');
  }
  
  console.log('\n══════════════════════════════════════════════');
  console.log('  FINDINGS');
  console.log('══════════════════════════════════════════════');
  console.log('');
  console.log('  🔴 CRITICAL: Web staff login uses SHA-256 for passwords');
  console.log('  🔴 SHA-256 is a FAST hash — designed for integrity, not passwords');
  console.log('  🔴 GPU can crack billions of SHA-256 hashes per second');
  console.log('  🔴 No salt is used (same password = same hash everywhere)');
  console.log('');
  console.log('  ✅ RECOMMENDED FIX:');
  console.log('  1. Replace with bcrypt (cost factor 10-12)');
  console.log('  2. Or use argon2id (memory-hard, GPU-resistant)');
  console.log('  3. Add per-user salt');
  console.log('  4. Implement rate limiting on login endpoint');
  console.log('');
  console.log('  📝 File to fix: lib/services/auth/web_auth_service.dart');
  console.log('  📝 Lines 14-17: _hashPassword() uses SHA-256');
  console.log('');
}

main().catch(console.error);
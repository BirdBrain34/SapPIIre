/**
 * SapPIIre — AES-256-GCM & RSA-2048-OAEP Crypto Benchmark
 *
 * Measures encrypt/decrypt latency for the same Web Crypto API primitives
 * used by the Supabase Edge Functions in production.
 *
 * Run:
 *   deno run --allow-all tests/benchmarks/crypto_benchmark.ts
 *
 * Optional flags:
 *   --iterations=5000       Number of iterations per operation (default 1000)
 *   --payload-size=2048     Approximate JSON payload size in bytes (default ~1 KB)
 */

// ─── Configuration ────────────────────────────────────────────────────────────

const DEFAULT_ITERATIONS = 1000;
const DEFAULT_PAYLOAD_SIZE = 1024; // ~1 KB, typical form submission

function parseArgs(): { iterations: number; payloadSize: number } {
  const args = typeof Deno !== "undefined" ? Deno.args : [];
  let iterations = DEFAULT_ITERATIONS;
  let payloadSize = DEFAULT_PAYLOAD_SIZE;

  for (const arg of args) {
    if (arg.startsWith("--iterations=")) {
      iterations = parseInt(arg.split("=")[1], 10) || DEFAULT_ITERATIONS;
    } else if (arg.startsWith("--payload-size=")) {
      payloadSize = parseInt(arg.split("=")[1], 10) || DEFAULT_PAYLOAD_SIZE;
    }
  }

  return { iterations, payloadSize };
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/** Generate a realistic JSON payload of approximately `targetBytes` size. */
function generatePayload(targetBytes: number): string {
  const baseObj: Record<string, string> = {
    first_name: "Juan",
    middle_name: "Santos",
    last_name: "Dela Cruz",
    date_of_birth: "1990-05-15",
    phone_number: "+639171234567",
    email: "juan.delacruz@example.com",
    address: "123 Rizal Street, Barangay San Miguel, Manila, Metro Manila 1000",
    civil_status: "Single",
    sex: "Male",
    nationality: "Filipino",
    occupation: "Software Developer",
    monthly_income: "25000",
    number_of_dependents: "2",
    emergency_contact: "Maria Dela Cruz",
    emergency_phone: "+639181234567",
    purpose_of_visit: "Social welfare assistance application",
    referral_source: "Barangay referral",
  };

  // Pad until we reach target size
  let payload = JSON.stringify(baseObj);
  let counter = 0;
  while (payload.length < targetBytes) {
    baseObj[`extra_field_${counter}`] = `value_${counter}_${"x".repeat(50)}`;
    payload = JSON.stringify(baseObj);
    counter++;
  }

  return payload;
}

function stats(timings: number[]): {
  min: number;
  max: number;
  avg: number;
  median: number;
  stddev: number;
} {
  const sorted = [...timings].sort((a, b) => a - b);
  const sum = sorted.reduce((s, v) => s + v, 0);
  const avg = sum / sorted.length;
  const variance =
    sorted.reduce((s, v) => s + (v - avg) ** 2, 0) / sorted.length;

  return {
    min: sorted[0],
    max: sorted[sorted.length - 1],
    avg,
    median:
      sorted.length % 2 === 0
        ? (sorted[sorted.length / 2 - 1] + sorted[sorted.length / 2]) / 2
        : sorted[Math.floor(sorted.length / 2)],
    stddev: Math.sqrt(variance),
  };
}

function fmt(ms: number): string {
  return ms.toFixed(4);
}

// ─── Benchmark Functions ──────────────────────────────────────────────────────

async function benchmarkAesEncrypt(
  payload: Uint8Array,
  iterations: number
): Promise<{
  timings: number[];
  lastCiphertext: ArrayBuffer;
  lastIv: Uint8Array;
  cryptoKey: CryptoKey;
}> {
  // Generate AES-256 key
  const cryptoKey = await crypto.subtle.generateKey(
    { name: "AES-GCM", length: 256 },
    true,
    ["encrypt", "decrypt"]
  );

  const timings: number[] = [];
  let lastCiphertext: ArrayBuffer = new ArrayBuffer(0);
  let lastIv: Uint8Array = new Uint8Array(0);

  // Warmup (3 iterations)
  for (let i = 0; i < 3; i++) {
    const iv = crypto.getRandomValues(new Uint8Array(12));
    await crypto.subtle.encrypt({ name: "AES-GCM", iv }, cryptoKey, payload);
  }

  for (let i = 0; i < iterations; i++) {
    const iv = crypto.getRandomValues(new Uint8Array(12));

    const start = performance.now();
    const ciphertext = await crypto.subtle.encrypt(
      { name: "AES-GCM", iv },
      cryptoKey,
      payload
    );
    const end = performance.now();

    timings.push(end - start);
    lastCiphertext = ciphertext;
    lastIv = iv;
  }

  return { timings, lastCiphertext, lastIv, cryptoKey };
}

async function benchmarkAesDecrypt(
  ciphertext: ArrayBuffer,
  iv: Uint8Array,
  cryptoKey: CryptoKey,
  iterations: number
): Promise<number[]> {
  const timings: number[] = [];

  // Warmup
  for (let i = 0; i < 3; i++) {
    await crypto.subtle.decrypt({ name: "AES-GCM", iv }, cryptoKey, ciphertext);
  }

  for (let i = 0; i < iterations; i++) {
    const start = performance.now();
    await crypto.subtle.decrypt({ name: "AES-GCM", iv }, cryptoKey, ciphertext);
    const end = performance.now();

    timings.push(end - start);
  }

  return timings;
}

async function benchmarkRsaKeyEncrypt(
  aesKeyRaw: ArrayBuffer,
  rsaPublicKey: CryptoKey,
  iterations: number
): Promise<{ timings: number[]; lastEncryptedKey: ArrayBuffer }> {
  const timings: number[] = [];
  let lastEncryptedKey: ArrayBuffer = new ArrayBuffer(0);

  // Warmup
  for (let i = 0; i < 3; i++) {
    await crypto.subtle.encrypt(
      { name: "RSA-OAEP" },
      rsaPublicKey,
      aesKeyRaw
    );
  }

  for (let i = 0; i < iterations; i++) {
    const start = performance.now();
    const encrypted = await crypto.subtle.encrypt(
      { name: "RSA-OAEP" },
      rsaPublicKey,
      aesKeyRaw
    );
    const end = performance.now();

    timings.push(end - start);
    lastEncryptedKey = encrypted;
  }

  return { timings, lastEncryptedKey };
}

async function benchmarkRsaKeyDecrypt(
  encryptedKey: ArrayBuffer,
  rsaPrivateKey: CryptoKey,
  iterations: number
): Promise<number[]> {
  const timings: number[] = [];

  // Warmup
  for (let i = 0; i < 3; i++) {
    await crypto.subtle.decrypt(
      { name: "RSA-OAEP" },
      rsaPrivateKey,
      encryptedKey
    );
  }

  for (let i = 0; i < iterations; i++) {
    const start = performance.now();
    await crypto.subtle.decrypt(
      { name: "RSA-OAEP" },
      rsaPrivateKey,
      encryptedKey
    );
    const end = performance.now();

    timings.push(end - start);
  }

  return timings;
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  const { iterations, payloadSize } = parseArgs();

  console.log("╔══════════════════════════════════════════════════════════════╗");
  console.log("║   SapPIIre — Cryptographic Performance Benchmark           ║");
  console.log("╠══════════════════════════════════════════════════════════════╣");
  console.log(`║  Runtime:        Deno ${Deno.version.deno}                              ║`);
  console.log(`║  Iterations:     ${String(iterations).padEnd(43)}║`);
  console.log(`║  Payload size:   ~${String(payloadSize).padEnd(41)}║`);
  console.log(`║  Timestamp:      ${new Date().toISOString().padEnd(42)}║`);
  console.log("╚══════════════════════════════════════════════════════════════╝");
  console.log();

  // Generate payload
  const payloadStr = generatePayload(payloadSize);
  const payloadBytes = new TextEncoder().encode(payloadStr);
  console.log(
    `[INFO] Actual payload size: ${payloadBytes.byteLength} bytes (${payloadStr.length} chars)`
  );
  console.log();

  // Generate RSA-2048 key pair (matches production: RSA-OAEP with SHA-1)
  console.log("[SETUP] Generating RSA-2048 key pair (SHA-1 for OAEP)...");
  const rsaKeyPair = await crypto.subtle.generateKey(
    {
      name: "RSA-OAEP",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-1",
    },
    true,
    ["encrypt", "decrypt"]
  );
  console.log("[SETUP] RSA-2048 key pair generated.\n");

  // ── 1. AES-256-GCM Encryption ──────────────────────────────────────────────
  console.log(`[BENCH] AES-256-GCM Encryption (${iterations} iterations)...`);
  const aesEncResult = await benchmarkAesEncrypt(payloadBytes, iterations);
  const aesEncStats = stats(aesEncResult.timings);
  console.log(
    `  Min: ${fmt(aesEncStats.min)} ms | Max: ${fmt(aesEncStats.max)} ms | Avg: ${fmt(aesEncStats.avg)} ms | Median: ${fmt(aesEncStats.median)} ms`
  );

  // ── 2. AES-256-GCM Decryption ──────────────────────────────────────────────
  console.log(`[BENCH] AES-256-GCM Decryption (${iterations} iterations)...`);
  const aesDecTimings = await benchmarkAesDecrypt(
    aesEncResult.lastCiphertext,
    aesEncResult.lastIv,
    aesEncResult.cryptoKey,
    iterations
  );
  const aesDecStats = stats(aesDecTimings);
  console.log(
    `  Min: ${fmt(aesDecStats.min)} ms | Max: ${fmt(aesDecStats.max)} ms | Avg: ${fmt(aesDecStats.avg)} ms | Median: ${fmt(aesDecStats.median)} ms`
  );

  // ── 3. RSA-2048-OAEP Key Encryption ────────────────────────────────────────
  console.log(
    `[BENCH] RSA-2048-OAEP Key Encryption (${iterations} iterations)...`
  );
  // Export raw AES key for RSA wrapping
  const aesKeyRaw = await crypto.subtle.exportKey(
    "raw",
    aesEncResult.cryptoKey
  );
  const rsaEncResult = await benchmarkRsaKeyEncrypt(
    aesKeyRaw,
    rsaKeyPair.publicKey,
    iterations
  );
  const rsaEncStats = stats(rsaEncResult.timings);
  console.log(
    `  Min: ${fmt(rsaEncStats.min)} ms | Max: ${fmt(rsaEncStats.max)} ms | Avg: ${fmt(rsaEncStats.avg)} ms | Median: ${fmt(rsaEncStats.median)} ms`
  );

  // ── 4. RSA-2048-OAEP Key Decryption ────────────────────────────────────────
  console.log(
    `[BENCH] RSA-2048-OAEP Key Decryption (${iterations} iterations)...`
  );
  const rsaDecTimings = await benchmarkRsaKeyDecrypt(
    rsaEncResult.lastEncryptedKey,
    rsaKeyPair.privateKey,
    iterations
  );
  const rsaDecStats = stats(rsaDecTimings);
  console.log(
    `  Min: ${fmt(rsaDecStats.min)} ms | Max: ${fmt(rsaDecStats.max)} ms | Avg: ${fmt(rsaDecStats.avg)} ms | Median: ${fmt(rsaDecStats.median)} ms`
  );

  // ── Correctness Verification ───────────────────────────────────────────────
  console.log("\n[VERIFY] Running round-trip correctness checks...");

  // AES round-trip
  const aesDecrypted = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: aesEncResult.lastIv },
    aesEncResult.cryptoKey,
    aesEncResult.lastCiphertext
  );
  const aesPlaintext = new TextDecoder().decode(aesDecrypted);
  const aesOk = aesPlaintext === payloadStr;
  console.log(`  AES-256-GCM round-trip: ${aesOk ? "✅ PASS" : "❌ FAIL"}`);

  // RSA round-trip
  const rsaDecrypted = await crypto.subtle.decrypt(
    { name: "RSA-OAEP" },
    rsaKeyPair.privateKey,
    rsaEncResult.lastEncryptedKey
  );
  const rsaKeyMatch =
    new Uint8Array(rsaDecrypted).toString() ===
    new Uint8Array(aesKeyRaw).toString();
  console.log(`  RSA-2048-OAEP round-trip: ${rsaKeyMatch ? "✅ PASS" : "❌ FAIL"}`);

  // ── Summary Table ──────────────────────────────────────────────────────────
  console.log("\n");
  console.log("┌─────────────────────────────┬───────────┬───────────┬───────────┬───────────┐");
  console.log("│ Operation                   │  Min(ms)  │  Max(ms)  │  Avg(ms)  │  Med(ms)  │");
  console.log("├─────────────────────────────┼───────────┼───────────┼───────────┼───────────┤");

  const rows = [
    { name: "AES-256-GCM Encryption", s: aesEncStats },
    { name: "AES-256-GCM Decryption", s: aesDecStats },
    { name: "RSA-2048-OAEP Key Encrypt", s: rsaEncStats },
    { name: "RSA-2048-OAEP Key Decrypt", s: rsaDecStats },
  ];

  for (const row of rows) {
    const name = row.name.padEnd(27);
    const min = fmt(row.s.min).padStart(9);
    const max = fmt(row.s.max).padStart(9);
    const avg = fmt(row.s.avg).padStart(9);
    const med = fmt(row.s.median).padStart(9);
    console.log(`│ ${name} │ ${min} │ ${max} │ ${avg} │ ${med} │`);
  }

  console.log("└─────────────────────────────┴───────────┴───────────┴───────────┴───────────┘");

  // ── CSV Output ─────────────────────────────────────────────────────────────
  console.log("\n[CSV] Copy-paste for spreadsheet:");
  console.log("Operation,Min(ms),Max(ms),Avg(ms),Median(ms),StdDev(ms)");
  for (const row of rows) {
    console.log(
      `${row.name},${fmt(row.s.min)},${fmt(row.s.max)},${fmt(row.s.avg)},${fmt(row.s.median)},${fmt(row.s.stddev)}`
    );
  }

  console.log("\n[DONE] Benchmark complete.");
}

main().catch((err) => {
  console.error("Fatal error:", err);
  Deno.exit(1);
});

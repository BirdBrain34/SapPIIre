// SapPIIre — AES-256-GCM & RSA-2048-OAEP Crypto Benchmark (Dart / Flutter)
//
// Measures encrypt/decrypt latency for the same `encrypt` package primitives
// used by HybridCryptoService in the Flutter mobile app.
//
// Run:
//   dart run tests/benchmarks/crypto_benchmark.dart
//
// Optional env vars:
//   BENCH_ITERATIONS=5000  (default 1000)

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/export.dart' as pc;

// ─── Configuration ────────────────────────────────────────────────────────────

const int defaultIterations = 1000;

int getIterations() {
  final envVal = const String.fromEnvironment('BENCH_ITERATIONS', defaultValue: '');
  if (envVal.isNotEmpty) {
    return int.tryParse(envVal) ?? defaultIterations;
  }
  return defaultIterations;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Generate a realistic JSON payload of approximately [targetBytes] size.
String generatePayload(int targetBytes) {
  final baseObj = <String, String>{
    'first_name': 'Juan',
    'middle_name': 'Santos',
    'last_name': 'Dela Cruz',
    'date_of_birth': '1990-05-15',
    'phone_number': '+639171234567',
    'email': 'juan.delacruz@example.com',
    'address': '123 Rizal Street, Barangay San Miguel, Manila, Metro Manila 1000',
    'civil_status': 'Single',
    'sex': 'Male',
    'nationality': 'Filipino',
    'occupation': 'Software Developer',
    'monthly_income': '25000',
    'number_of_dependents': '2',
    'emergency_contact': 'Maria Dela Cruz',
    'emergency_phone': '+639181234567',
    'purpose_of_visit': 'Social welfare assistance application',
    'referral_source': 'Barangay referral',
  };

  var payload = jsonEncode(baseObj);
  var counter = 0;
  while (payload.length < targetBytes) {
    baseObj['extra_field_$counter'] = 'value_${counter}_${'x' * 50}';
    payload = jsonEncode(baseObj);
    counter++;
  }

  return payload;
}

class BenchStats {
  final double min;
  final double max;
  final double avg;
  final double median;
  final double stddev;

  const BenchStats({
    required this.min,
    required this.max,
    required this.avg,
    required this.median,
    required this.stddev,
  });
}

BenchStats computeStats(List<double> timings) {
  final sorted = List<double>.from(timings)..sort();
  final sum = sorted.fold<double>(0, (s, v) => s + v);
  final avg = sum / sorted.length;
  final variance =
      sorted.fold<double>(0, (s, v) => s + (v - avg) * (v - avg)) /
          sorted.length;

  final median = sorted.length % 2 == 0
      ? (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2
      : sorted[sorted.length ~/ 2];

  return BenchStats(
    min: sorted.first,
    max: sorted.last,
    avg: avg,
    median: median,
    stddev: sqrt(variance),
  );
}

String fmt(double ms) => ms.toStringAsFixed(4);

// ─── Benchmark Functions ──────────────────────────────────────────────────────

/// Benchmark AES-256-GCM encryption (matches _encryptFieldWorker)
List<double> benchAesEncrypt(
  String payload,
  encrypt.Key aesKey,
  int iterations,
) {
  final encrypter = encrypt.Encrypter(
    encrypt.AES(aesKey, mode: encrypt.AESMode.gcm),
  );

  // Warmup
  for (var i = 0; i < 3; i++) {
    final iv = encrypt.IV.fromSecureRandom(12);
    encrypter.encrypt(payload, iv: iv);
  }

  final timings = <double>[];
  for (var i = 0; i < iterations; i++) {
    final iv = encrypt.IV.fromSecureRandom(12);

    final sw = Stopwatch()..start();
    encrypter.encrypt(payload, iv: iv);
    sw.stop();

    timings.add(sw.elapsedMicroseconds / 1000.0); // Convert to ms
  }

  return timings;
}

/// Benchmark AES-256-GCM decryption (matches _decryptFieldWorker)
List<double> benchAesDecrypt(
  String ciphertextB64,
  encrypt.IV iv,
  encrypt.Key aesKey,
  int iterations,
) {
  final encrypter = encrypt.Encrypter(
    encrypt.AES(aesKey, mode: encrypt.AESMode.gcm),
  );

  // Warmup
  for (var i = 0; i < 3; i++) {
    encrypter.decrypt64(ciphertextB64, iv: iv);
  }

  final timings = <double>[];
  for (var i = 0; i < iterations; i++) {
    final sw = Stopwatch()..start();
    encrypter.decrypt64(ciphertextB64, iv: iv);
    sw.stop();

    timings.add(sw.elapsedMicroseconds / 1000.0);
  }

  return timings;
}

/// Benchmark RSA-2048-OAEP key encryption (matches _encryptForTransmissionWorker)
List<double> benchRsaKeyEncrypt(
  Uint8List aesKeyBytes,
  dynamic rsaPublicKey,
  int iterations,
) {
  final rsaEncrypter = encrypt.Encrypter(
    encrypt.RSA(
      publicKey: rsaPublicKey,
      encoding: encrypt.RSAEncoding.OAEP,
    ),
  );

  // Warmup
  for (var i = 0; i < 3; i++) {
    rsaEncrypter.encryptBytes(aesKeyBytes);
  }

  final timings = <double>[];
  for (var i = 0; i < iterations; i++) {
    final sw = Stopwatch()..start();
    rsaEncrypter.encryptBytes(aesKeyBytes);
    sw.stop();

    timings.add(sw.elapsedMicroseconds / 1000.0);
  }

  return timings;
}

/// Benchmark RSA-2048-OAEP key decryption
List<double> benchRsaKeyDecrypt(
  encrypt.Encrypted encryptedAesKey,
  dynamic rsaPrivateKey,
  int iterations,
) {
  final rsaDecrypter = encrypt.Encrypter(
    encrypt.RSA(
      privateKey: rsaPrivateKey,
      encoding: encrypt.RSAEncoding.OAEP,
    ),
  );

  // Warmup
  for (var i = 0; i < 3; i++) {
    rsaDecrypter.decryptBytes(encryptedAesKey);
  }

  final timings = <double>[];
  for (var i = 0; i < iterations; i++) {
    final sw = Stopwatch()..start();
    rsaDecrypter.decryptBytes(encryptedAesKey);
    sw.stop();

    timings.add(sw.elapsedMicroseconds / 1000.0);
  }

  return timings;
}

// ─── Main ─────────────────────────────────────────────────────────────────────

void main() {
  final iterations = getIterations();
  const payloadSize = 1024;

  print('╔══════════════════════════════════════════════════════════════╗');
  print('║   SapPIIre — Cryptographic Performance Benchmark (Dart)    ║');
  print('╠══════════════════════════════════════════════════════════════╣');
  print('║  Runtime:        Dart VM                                   ║');
  print('║  Iterations:     ${iterations.toString().padRight(43)}║');
  print('║  Payload size:   ~${payloadSize.toString().padRight(41)}║');
  print('║  Timestamp:      ${DateTime.now().toIso8601String().padRight(42)}║');
  print('╚══════════════════════════════════════════════════════════════╝');
  print('');

  // Generate payload
  final payloadStr = generatePayload(payloadSize);
  final payloadBytes = utf8.encode(payloadStr);
  print('[INFO] Actual payload size: ${payloadBytes.length} bytes (${payloadStr.length} chars)');
  print('');

  // Generate AES-256 key (same as production: 32 bytes random)
  final aesKey = encrypt.Key.fromSecureRandom(32);

  // Generate RSA-2048 key pair using pointycastle (underlying lib for encrypt package)
  print('[SETUP] Generating RSA-2048 key pair...');
  final keyGen = pc.KeyGenerator('RSA');
  keyGen.init(pc.ParametersWithRandom(
    pc.RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
    pc.FortunaRandom()..seed(pc.KeyParameter(Uint8List.fromList(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    ))),
  ));
  final rsaKeyPair = keyGen.generateKeyPair();
  final rsaPublicKey = rsaKeyPair.publicKey as pc.RSAPublicKey;
  final rsaPrivateKey = rsaKeyPair.privateKey as pc.RSAPrivateKey;
  print('[SETUP] RSA-2048 key pair generated.\n');

  // ── 1. AES-256-GCM Encryption ──────────────────────────────────────────────
  print('[BENCH] AES-256-GCM Encryption ($iterations iterations)...');
  final aesEncTimings = benchAesEncrypt(payloadStr, aesKey, iterations);
  final aesEncStats = computeStats(aesEncTimings);
  print(
    '  Min: ${fmt(aesEncStats.min)} ms | Max: ${fmt(aesEncStats.max)} ms | '
    'Avg: ${fmt(aesEncStats.avg)} ms | Median: ${fmt(aesEncStats.median)} ms',
  );

  // Produce a ciphertext for decryption benchmark
  final encrypter = encrypt.Encrypter(
    encrypt.AES(aesKey, mode: encrypt.AESMode.gcm),
  );
  final sampleIv = encrypt.IV.fromSecureRandom(12);
  final sampleEncrypted = encrypter.encrypt(payloadStr, iv: sampleIv);

  // ── 2. AES-256-GCM Decryption ──────────────────────────────────────────────
  print('[BENCH] AES-256-GCM Decryption ($iterations iterations)...');
  final aesDecTimings = benchAesDecrypt(
    sampleEncrypted.base64,
    sampleIv,
    aesKey,
    iterations,
  );
  final aesDecStats = computeStats(aesDecTimings);
  print(
    '  Min: ${fmt(aesDecStats.min)} ms | Max: ${fmt(aesDecStats.max)} ms | '
    'Avg: ${fmt(aesDecStats.avg)} ms | Median: ${fmt(aesDecStats.median)} ms',
  );

  // ── 3. RSA-2048-OAEP Key Encryption ────────────────────────────────────────
  print('[BENCH] RSA-2048-OAEP Key Encryption ($iterations iterations)...');
  final rsaEncTimings = benchRsaKeyEncrypt(
    Uint8List.fromList(aesKey.bytes),
    rsaPublicKey,
    iterations,
  );
  final rsaEncStats = computeStats(rsaEncTimings);
  print(
    '  Min: ${fmt(rsaEncStats.min)} ms | Max: ${fmt(rsaEncStats.max)} ms | '
    'Avg: ${fmt(rsaEncStats.avg)} ms | Median: ${fmt(rsaEncStats.median)} ms',
  );

  // Produce an encrypted key for decryption benchmark
  final rsaEncrypter = encrypt.Encrypter(
    encrypt.RSA(
      publicKey: rsaPublicKey,
      encoding: encrypt.RSAEncoding.OAEP,
    ),
  );
  final sampleEncryptedKey = rsaEncrypter.encryptBytes(aesKey.bytes);

  // ── 4. RSA-2048-OAEP Key Decryption ────────────────────────────────────────
  print('[BENCH] RSA-2048-OAEP Key Decryption ($iterations iterations)...');
  final rsaDecTimings = benchRsaKeyDecrypt(
    sampleEncryptedKey,
    rsaPrivateKey,
    iterations,
  );
  final rsaDecStats = computeStats(rsaDecTimings);
  print(
    '  Min: ${fmt(rsaDecStats.min)} ms | Max: ${fmt(rsaDecStats.max)} ms | '
    'Avg: ${fmt(rsaDecStats.avg)} ms | Median: ${fmt(rsaDecStats.median)} ms',
  );

  // ── Correctness Verification ───────────────────────────────────────────────
  print('\n[VERIFY] Running round-trip correctness checks...');

  // AES round-trip
  final aesDecrypted = encrypter.decrypt(sampleEncrypted, iv: sampleIv);
  final aesOk = aesDecrypted == payloadStr;
  print('  AES-256-GCM round-trip: ${aesOk ? "✅ PASS" : "❌ FAIL"}');

  // RSA round-trip
  final rsaDecrypter = encrypt.Encrypter(
    encrypt.RSA(
      privateKey: rsaPrivateKey,
      encoding: encrypt.RSAEncoding.OAEP,
    ),
  );
  final rsaDecryptedBytes = rsaDecrypter.decryptBytes(sampleEncryptedKey);
  final rsaOk = base64Encode(rsaDecryptedBytes) == base64Encode(aesKey.bytes);
  print('  RSA-2048-OAEP round-trip: ${rsaOk ? "✅ PASS" : "❌ FAIL"}');

  // ── Summary Table ──────────────────────────────────────────────────────────
  print('\n');
  print('┌─────────────────────────────┬───────────┬───────────┬───────────┬───────────┐');
  print('│ Operation                   │  Min(ms)  │  Max(ms)  │  Avg(ms)  │  Med(ms)  │');
  print('├─────────────────────────────┼───────────┼───────────┼───────────┼───────────┤');

  final rows = <Map<String, dynamic>>[
    {'name': 'AES-256-GCM Encryption', 's': aesEncStats},
    {'name': 'AES-256-GCM Decryption', 's': aesDecStats},
    {'name': 'RSA-2048-OAEP Key Encrypt', 's': rsaEncStats},
    {'name': 'RSA-2048-OAEP Key Decrypt', 's': rsaDecStats},
  ];

  for (final row in rows) {
    final name = (row['name'] as String).padRight(27);
    final s = row['s'] as BenchStats;
    final minStr = fmt(s.min).padLeft(9);
    final maxStr = fmt(s.max).padLeft(9);
    final avgStr = fmt(s.avg).padLeft(9);
    final medStr = fmt(s.median).padLeft(9);
    print('│ $name │ $minStr │ $maxStr │ $avgStr │ $medStr │');
  }

  print('└─────────────────────────────┴───────────┴───────────┴───────────┴───────────┘');

  // ── CSV Output ─────────────────────────────────────────────────────────────
  print('\n[CSV] Copy-paste for spreadsheet:');
  print('Operation,Min(ms),Max(ms),Avg(ms),Median(ms),StdDev(ms)');
  for (final row in rows) {
    final s = row['s'] as BenchStats;
    print('${row['name']},${fmt(s.min)},${fmt(s.max)},${fmt(s.avg)},${fmt(s.median)},${fmt(s.stddev)}');
  }

  print('\n[DONE] Benchmark complete.');
}

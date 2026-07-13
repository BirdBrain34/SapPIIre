# Hybrid Crypto Test Drive Guide (SapPIIre)

This guide explains exactly how the team can run and test the hybrid cryptosystem used in this branch.

## 1) What this implementation does

### AES at-rest (database field values)
- Table: `user_field_values`
- Cipher: AES-256-GCM
- Trigger point: save/load in app via `FieldValueService`
- Metadata: `iv`, `encryption_version` = 2
- Key derivation: Server-Side via Edge Functions (`derive-field-key`)

### RSA + AES in-transit (QR/session handoff)
- Table: `form_submission`
- Process:
  1. App creates random AES session key
  2. App encrypts payload with AES-GCM
  3. App encrypts AES key with RSA-OAEP public key
  4. App stores envelope (`encrypted_payload`, `payload_iv`, `encrypted_aes_key`, `transmission_version = 1`)
  5. **Zero-Knowledge Staging:** Edge function (`serve-submission-for-review`) decrypts in-memory and returns plaintext ephemerally in HTTP response — plaintext is NEVER written to database

## 1.1) Security patch sync status (2026-04-03)

This section is the teammate handoff summary for the security fixes implemented in this branch.

### Implemented patches
- `lib/services/supabase_service.dart`
  - `saveScannedIdFieldValues()` now routes writes through `FieldValueService.saveUserFieldValues()` (no direct plaintext upsert to `user_field_values`).
  - `saveProfileAfterVerification()` now routes writes through `FieldValueService.saveUserFieldValues()` per template.
  - `_invokeDecryptQrPayloadWithRetry()` has the null/empty access token guard to avoid invoke-time null crashes.
- `lib/services/crypto/hybrid_crypto_service.dart`
  - Added `encryptFieldBatch()` and `decryptFieldBatch()` with one `compute()` call each.
  - Added `_encryptFieldBatchWorker` and `_decryptFieldBatchWorker` at file scope.
- `lib/services/field_value_service.dart`
  - `saveUserFieldValues()` now uses `HybridCryptoService.encryptFieldBatch()` for per-save batch encryption.
  - `loadUserFieldValues()` now uses `HybridCryptoService.decryptFieldBatch()` for per-load batch decryption.
  - `scanned_at` writes now use UTC (`DateTime.now().toUtc().toIso8601String()`).
  - `updated_at` is no longer client-supplied on `user_field_values` inserts; database server timestamp/default is used.

### Important note on key derivation
- The system uses server-side key derivation via the `derive-field-key` Edge Function; no local client-side secret derivation is used.
- The v1-to-v2 security comparison is documented in [docs/01_QR_Handshake_and_Cryptography.md](docs/01_QR_Handshake_and_Cryptography.md).

### Team rollout checklist
1. Pull latest branch changes.
2. Restart running app instances (do not rely on stale hot-reload state).
3. Execute one fresh save flow and one QR handshake flow.
4. Run verification SQL (section 8) and store screenshots/logs for capstone evidence.

## 2) Required VS Code extensions

Install these on each team machine:
- Dart Code (`Dart-Code.dart-code`)
- Flutter (`Dart-Code.flutter`)
- Supabase (`Supabase.supabase`)

Recommended:
- GitLens (`eamodio.gitlens`)
- Error Lens (`usernamehw.errorlens`)
- PostgreSQL (`ms-ossdata.vscode-postgresql`)

## 3) Local prerequisites

- Flutter SDK compatible with project (Dart SDK `^3.10.8`)
- Supabase project access (dashboard + edge functions)
- Git access to this repo

## 4) Branch and dependency setup

```bash
git fetch origin
git checkout security/hybrid-crypto
git pull --ff-only
flutter pub get
```

## 5) Keypair setup (one-time per environment)

You need one RSA keypair per environment (dev/staging/prod).

### Option A: OpenSSL
```bash
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out rsa_private_key.pem
openssl rsa -pubout -in rsa_private_key.pem -out rsa_public_key.pem
```

### Option B: Ask security/admin
- Request environment-specific `rsa_private_key.pem` and `rsa_public_key.pem`
- Never commit the private key to git

## 6) Supabase setup

### 6.1 Add/activate public key for app-side encryption
- Store `rsa_public_key.pem` in your key source table used by RPC `get_active_rsa_public_key`
- Ensure the active record returns a non-empty PEM string

Validation SQL:
```sql
select get_active_rsa_public_key();
```

### 6.2 Configure edge secret (private key)
- Go to Supabase Dashboard -> Edge Functions -> Secrets
- Add secret name: `RSA_PRIVATE_KEY_PEM`
- Value: full PEM (including BEGIN/END lines)

### 6.3 Deploy edge function
This branch uses function path:
- `supabase/functions/decrypt-qr-payload/index.ts`

Deploy command:
```bash
supabase functions deploy decrypt-qr-payload
```

Important auth setting:
- If function calls are blocked with HTTP 401 before function logic runs, disable JWT verification for this function (or configure equivalent in your deploy process).
- Keep app-level/session-level checks in function logic as needed.

## 7) App runtime flow to test

1. Start app and authenticate
2. Open a session in web side
3. From mobile, send selected fields to web session
4. Confirm row in `form_submission` moves to `status = scanned` with `transmission_version = 1`
5. Staff invokes `serve-submission-for-review` Edge Function to decrypt in-memory (plaintext never written to database)
6. If the session has expired, confirm the function returns HTTP 410 with `reason = 'session_expired'` and the mobile client shows the expired-session state instead of a generic failure

## 8) Verification queries (copy-paste)

### 8.1 AES at-rest coverage
```sql
select
  count(*) as total_rows,
  count(*) filter (where encryption_version = 2) as aes_v2_rows,
  count(*) filter (where encryption_version = 2 and iv is not null and iv <> '') as aes_v2_with_iv,
  count(*) filter (where encryption_version = 2 and (iv is null or iv = '')) as aes_v2_missing_iv
from user_field_values;
```

Pass signal:
- `aes_v2_missing_iv = 0`

### 8.2 Recent AES rows (schema-safe ordering)
```sql
select
  id,
  encryption_version,
  (iv is not null and iv <> '') as has_iv,
  length(coalesce(field_value, '')) as field_value_len,
  updated_at
from user_field_values
order by updated_at desc
limit 25;
```

### 8.3 Hybrid envelope presence
```sql
select
  id,
  status,
  transmission_version,
  encrypted_payload is not null and encrypted_payload <> '' as has_encrypted_payload,
  payload_iv is not null and payload_iv <> '' as has_payload_iv,
  encrypted_aes_key is not null and encrypted_aes_key <> '' as has_encrypted_aes_key,
  created_at
from form_submission
order by created_at desc
limit 25;
```

Pass signal for encrypted sessions:
- `transmission_version = 1`
- all `has_*` columns are true

### 8.4 Zero-Knowledge Staging validation (encrypted envelope only)
```sql
with target as (
  select '5f74584f-261d-43df-af3e-24f3f2a61a58'::uuid as submission_id
)
select
  fs.id,
  fs.status,
  fs.transmission_version,
  (fs.encrypted_payload is not null and fs.encrypted_payload <> '') as has_encrypted_payload,
  (fs.payload_iv is not null and fs.payload_iv <> '') as has_payload_iv,
  (fs.encrypted_aes_key is not null and fs.encrypted_aes_key <> '') as has_encrypted_aes_key,
  case
    when fs.transmission_version = 1
      and fs.encrypted_payload is not null and fs.encrypted_payload <> ''
      and fs.payload_iv is not null and fs.payload_iv <> ''
      and fs.encrypted_aes_key is not null and fs.encrypted_aes_key <> ''
    then 'PASS (Zero-Knowledge Staging: encrypted envelope valid)'
    else 'FAIL'
  end as hybrid_result
from form_submission fs
join target t on fs.id = t.submission_id;
```

Note: Decryption happens in-memory via `serve-submission-for-review` Edge Function. To verify decryption, invoke the function directly with `sessionId` and `staffId` parameters. Stale sessions should return HTTP 410 `session_expired`.

### 8.5 Completion rate for encrypted transmissions
```sql
select
  count(*) as encrypted_total,
  count(*) filter (where status = 'completed') as encrypted_completed,
  count(*) filter (where status = 'scanned') as encrypted_scanned,
  round(
    100.0 * count(*) filter (where status = 'completed') / nullif(count(*), 0),
    2
  ) as encrypted_completion_pct
from form_submission
where transmission_version = 1;
```

## 9) Expected test results

A healthy run should show:
- At-rest rows with `encryption_version = 2` and valid IV in `user_field_values`
- New session rows with `transmission_version = 1` in `form_submission`
- Envelope columns present (`encrypted_payload`, `payload_iv`, `encrypted_aes_key`)
- **Zero-Knowledge Staging:** Encrypted envelope remains in database; decryption happens in-memory on staff request via `serve-submission-for-review` Edge Function

## 10) Troubleshooting quick map

- `missing_env_vars`:
  - Check `RSA_PRIVATE_KEY_PEM` secret

- `rsa_decrypt_failed`:
  - Public/private key mismatch

- `session_expired`:
  - The session passed `expires_at`; generate a new QR/session and retry
  - Re-upload matching pair and re-test

- `aes_gcm_decrypt_failed`:
  - Corrupted envelope or wrong AES key unwrap

- Session stuck in `scanned`:
  - Check function logs
  - Check function auth gate (401 means blocked before code)

## 11) Security checklist for team

- Do not commit `.pem` files
- Use environment-specific keypairs
- Rotate keys per environment on schedule
- Restrict access to private key secret
- Validate one PASS row after any deployment

## 12) Source files involved

### Core Cryptography and Services
- `lib/services/crypto/hybrid_crypto_service.dart`
- `lib/services/field_value_service.dart`
- `lib/services/supabase_service.dart`
- `lib/services/forms/submission_service.dart`

### Controllers
- `lib/web/controllers/manage_forms_controller.dart`

### Edge Functions (Zero-Knowledge Staging)
- `supabase/functions/serve-submission-for-review/index.ts` (on-demand in-memory decryption for staff review)
- `supabase/functions/decrypt-qr-payload/index.ts` (validation-only, status update)

### Edge Functions (Client Submissions)
- `supabase/functions/encrypt-and-save-submission/index.ts` (server-side AES-256-GCM encryption of finalized records)
- `supabase/functions/decrypt-submission-data/index.ts` (single-record decryption with role-based access control)
- `supabase/functions/decrypt-submission-batch/index.ts` (batch decryption for applicants screen, 5-10x faster loading)

### Edge Functions (OTP Verification)
- `supabase/functions/send-phone-otp/index.ts` (generate and store OTP for phone verification)
- `supabase/functions/verify-phone-otp/index.ts` (validate OTP using RPC)

### Main Entry Point
- `lib/main.dart`

### Benchmarks
- `tests/benchmarks/crypto_benchmark.ts` (Server-side/Deno performance measurement)
- `tests/benchmarks/crypto_benchmark.dart` (Client-side/Dart performance measurement)

## 13) Performance Benchmarks

To collect the performance metrics for the hybrid security implementation (for manuscripts or security reports), you can run the benchmark scripts. These scripts isolate the exact cryptographic operations used in production (AES-256-GCM and RSA-2048-OAEP) to measure computational overhead accurately.

### Running the Server-Side (Deno) Benchmark
This script measures the performance of the native Web Crypto API, exactly as it runs in the Supabase Edge Functions.

```bash
deno run --allow-all tests/benchmarks/crypto_benchmark.ts
```
Optional flags:
- `--iterations=5000` (default is 1000)
- `--payload-size=2048` (default is ~1KB)

### Running the Client-Side (Dart) Benchmark
This script measures the performance of the `encrypt` and `pointycastle` packages, exactly as they run in the Flutter mobile app.

```bash
dart run tests/benchmarks/crypto_benchmark.dart
```
*(To configure iterations in Dart, you can pass `BENCH_ITERATIONS` as a dart environment variable: `dart run --define=BENCH_ITERATIONS=5000 tests/benchmarks/crypto_benchmark.dart`)*

Both scripts will automatically verify round-trip encryption correctness and output a table of **Min, Max, Average, and Median** execution times in milliseconds. They also output CSV text for easy copy-pasting into your manuscript's tables.

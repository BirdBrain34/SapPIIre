# Hybrid Crypto Test Drive Guide (SapPIIre)

This guide explains exactly how the team can run and test the hybrid cryptosystem used in this branch.

## 1) What this implementation does

### AES at-rest (database field values)
- Table: `user_field_values`
- Cipher: AES-256-GCM
- Trigger point: save/load in app via `FieldValueService`
- Metadata: `iv`, `encryption_version`

### RSA + AES in-transit (QR/session handoff)
- Table: `form_submission`
- Process:
  1. App creates random AES session key
  2. App encrypts payload with AES-GCM
  3. App encrypts AES key with RSA-OAEP public key
  4. App stores envelope (`encrypted_payload`, `payload_iv`, `encrypted_aes_key`, `transmission_version = 1`)
  5. Edge function decrypts and writes plaintext JSON to `form_data`

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
4. Confirm row in `form_submission` moves to `status = scanned`
5. Confirm edge decrypt writes `form_data`

## 8) Verification queries (copy-paste)

### 8.1 AES at-rest coverage
```sql
select
  count(*) as total_rows,
  count(*) filter (where encryption_version = 1) as aes_v1_rows,
  count(*) filter (where encryption_version = 1 and iv is not null and iv <> '') as aes_v1_with_iv,
  count(*) filter (where encryption_version = 1 and (iv is null or iv = '')) as aes_v1_missing_iv,
  count(*) filter (where encryption_version = 0) as legacy_plaintext_rows
from user_field_values;
```

Pass signal:
- `aes_v1_missing_iv = 0`

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

### 8.4 End-to-end decrypt success for one row
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
  (fs.form_data::jsonb <> '{}'::jsonb) as form_data_not_empty,
  case
    when fs.transmission_version = 1
      and fs.encrypted_payload is not null and fs.encrypted_payload <> ''
      and fs.payload_iv is not null and fs.payload_iv <> ''
      and fs.encrypted_aes_key is not null and fs.encrypted_aes_key <> ''
      and fs.form_data::jsonb <> '{}'::jsonb
    then 'PASS'
    else 'FAIL'
  end as hybrid_result
from form_submission fs
join target t on fs.id = t.submission_id;
```

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
- At-rest rows with `encryption_version = 1` and valid IV
- New session rows with `transmission_version = 1`
- Envelope columns present (`encrypted_payload`, `payload_iv`, `encrypted_aes_key`)
- `form_data` becomes non-empty after edge decrypt

## 10) Troubleshooting quick map

- `missing_env_vars`:
  - Check `RSA_PRIVATE_KEY_PEM` secret

- `rsa_decrypt_failed`:
  - Public/private key mismatch
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

- `lib/services/crypto/hybrid_crypto_service.dart`
- `lib/services/field_value_service.dart`
- `lib/services/supabase_service.dart`
- `supabase/functions/decrypt-qr-payload/index.ts`
- `lib/main.dart`

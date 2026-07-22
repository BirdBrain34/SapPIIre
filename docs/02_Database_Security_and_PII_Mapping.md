# 02. Database Security and PII Mapping

## 1. Security Partitioning Overview

The Supabase schema separates data into distinct security domains to reduce exposure coupling:

1. Cryptographic key registry domain (`app_rsa_keypairs`).
2. User-owned PII value domain (`user_field_values`).
3. Live session transport domain (`form_submission`, `display_sessions`).
4. Finalized applicant archive domain (`client_submissions`).
5. Identity and access governance domain (`staff_accounts`, `staff_profiles`, OTP tables, `audit_logs`).

This partitioning supports controlled data progression from user input, to encrypted transfer, to staff-verified final records.

## 2. Schema-Coupled Security Responsibilities

### 2.1 Cryptographic Key Governance

`app_rsa_keypairs` stores versioned public keys (`key_version`, `public_key_pem`, `is_active`, `rotated_at`). The table is explicitly public-key oriented; private decryption material remains outside relational storage in Edge secrets.

The active public key is distributed to mobile clients via the `get_active_rsa_public_key` RPC, called by `HybridCryptoService.fetchAndCacheRsaPublicKey()` (`lib/services/crypto/hybrid_crypto_service.dart`, line 198). The corresponding private key (`RSA_PRIVATE_KEY_PEM`) is held exclusively in Supabase Edge Secrets and is used only by the `serve-submission-for-review` Edge Function during in-memory decryption.

### 2.2 PII at Rest: `user_field_values`

`user_field_values` stores mobile-sourced field values by (`user_id`, `field_id`) with cryptographic metadata:

1. `field_value` for encrypted value content.
2. `iv` for AES-GCM decryption metadata.
3. `encryption_version` (smallint) records the protection state for the stored value and supports future migration paths.
4. `updated_at` for recency resolution.

Foreign-key linkage to `form_fields(field_id)` binds values to dynamic metadata definitions.

**Key Derivation (`derive-field-key` Edge Function):** The mobile client calls `derive-field-key` (`supabase/functions/derive-field-key/index.ts`) to obtain a per-user AES-256 key. The function:
1. Validates the requesting user's JWT via `supabase.auth.getUser(token)` (line 48) — prevents impersonation
2. Derives the key via `HMAC-SHA256(FIELD_KEY_HMAC_SECRET_V2, userId)` (lines 59-75)
3. Returns the key in the HTTP response — never persists it to any database table
4. The client caches the key in volatile memory (`HybridCryptoService._fieldKeyCache`) and clears it on sign-out

**Server-Side Name Resolution (`resolve-applicant-names` Edge Function):** For dashboard display, staff need to see applicant names without having access to encryption keys. The `resolve-applicant-names` Edge Function (`supabase/functions/resolve-applicant-names/index.ts`) performs server-side decryption:
1. Validates staff authorization against `staff_accounts` (lines 118-121)
2. Queries `form_fields` for field IDs matching `canonical_field_key IN ('first_name', 'middle_name', 'last_name')` (lines 162-163)
3. Fetches encrypted values from `user_field_values` for the requested user IDs (lines 193-198)
4. Derives the same HMAC-SHA256 key server-side and decrypts (lines 251-259)
5. Returns plaintext names in the HTTP response — encryption keys never reach the browser

### 2.3 Transport Session Layer: `form_submission`

`form_submission` is the system's QR handshake anchor and enforces lifecycle constraints:

1. `status` domain is constrained to `active`, `scanned`, `completed`, `closed`, `expired`.
2. `expires_at` defaults to 10-minute session validity.
3. Hybrid transport columns include `encrypted_payload`, `payload_iv`, `encrypted_aes_key`, and `transmission_version`.
4. Staff linkage is modeled through optional `user_id` foreign key (not enforced in schema).

**QR Session Validation (`decrypt-qr-payload` Edge Function):** When the mobile client transmits data to a session, the `decrypt-qr-payload` Edge Function (`supabase/functions/decrypt-qr-payload/index.ts`) validates the transmission:
1. Authenticates the requesting user via JWT (lines 58-76)
2. Verifies the session exists and has `transmission_version=1` (lines 103-110)
3. Checks that `encrypted_payload`, `payload_iv`, and `encrypted_aes_key` are all non-empty (lines 121-124)
4. Updates `form_submission.status` to `'scanned'` and sets `scanned_at` — but only if current status is `'active'` (lines 129-133)
5. Does NOT decrypt the payload — decryption is deferred to `serve-submission-for-review`

**Zero-Knowledge Staging (`serve-submission-for-review` Edge Function):** When staff open a session for review, the `serve-submission-for-review` Edge Function (`supabase/functions/serve-submission-for-review/index.ts`) performs in-memory decryption:
1. Validates staff authorization against `staff_accounts` (role, is_active, account_status) (lines 89-108)
2. Fetches the encrypted envelope from `form_submission` (lines 111-115)
3. Checks `expires_at` — returns HTTP 410 if expired (lines 123-126)
4. Unwraps the AES key using RSA-OAEP with `RSA_PRIVATE_KEY_PEM` from Edge Secrets (lines 143-170)
5. Decrypts the payload with AES-GCM (lines 173-195)
6. Returns plaintext JSON ephemerally in the HTTP response — **never writes plaintext to the database** (line 217)
7. Logs the decryption event to `audit_logs` (lines 202-210)

### 2.4 Finalized Record Layer: `client_submissions`

`client_submissions` is the final intake archive where staff-reviewed JSON (`data`) is persisted with server-side encryption and operational metadata:

1. `session_id` is unique, preventing duplicate finalize writes per session.
2. `template_id` references `form_templates(template_id)`.
3. `intake_reference`, `form_code`, `created_by`, and edit stamps provide intake and accountability metadata.
4. **Data Encryption:** The `data` column stores AES-256-GCM encrypted JSON (Base64 encoded) of finalized applicant records.
   - Encryption is performed server-side by the `encrypt-and-save-submission` Edge Function.
   - A random 12-byte IV is generated per record and stored in `data_iv`.
   - The encryption algorithm is AES-256-GCM, with symmetric key (`SERVER_AES_KEY`) stored in Supabase Edge Secrets.
   - `data_encryption_version` is set to 1 to indicate encryption status and enable future versioning.
5. **Decryption Access Control:** The `decrypt-submission-data` Edge Function authorizes decryption requests based on staff role (`admin`, `superadmin`).
6. **Batch Decryption (`decrypt-submission-batch` Edge Function):** For dashboard analytics, the `decrypt-submission-batch` Edge Function (`supabase/functions/decrypt-submission-batch/index.ts`) decrypts up to 20 submissions in a single call with one key import. It validates staff role once (lines 66-78), fetches all rows in one query (lines 82-85), imports the AES key once (lines 98-101), and decrypts in parallel via `Promise.all` (lines 105-114). Handles both version 0 (plaintext) and version 1 (encrypted) records transparently (lines 107-113).
7. This architecture provides a defense-in-depth layer protecting finalized applicant records at rest, complementing client-side field encryption in `user_field_values` and hybrid transport encryption in `form_submission`.

### 2.5 Dynamic Metadata Layer

The form metadata stack consists of:

1. `form_templates`
2. `form_sections`
3. `form_fields`
4. `form_field_options`
5. `form_field_conditions`

This stack defines storage semantics (field IDs, canonical keys, validation rules) used by both mobile and web channels.

For web analytics presentation, `dashboard_widget_configs` and `dashboard_card_settings` store per-template chart type, field, color, and card-elevation preferences so dashboard rendering can remain metadata-driven rather than hard-coded.

### 2.6 Access and Verification Layer

`staff_accounts` and `staff_profiles` implement dashboard identity governance with schema-level role and status constraints:

1. `role` in {admin, superadmin}
2. `requested_role` in {admin, superadmin}
3. `account_status` in {pending, active, deactivated}
4. `is_active` and `is_first_login` for operational gatekeeping

Complementary verification tables:

1. `phone_otp` for time-bounded mobile OTP with atomic consumption via the `verify_and_consume_phone_otp` RPC.

**OTP Generation (`send-phone-otp` Edge Function):** The `send-phone-otp` Edge Function (`supabase/functions/send-phone-otp/index.ts`) handles SMS-based phone verification:
1. Rate-limits requests to 3 per 10 minutes per phone number (in-memory store, lines 12-28)
2. Generates a cryptographically secure 6-digit OTP via `crypto.getRandomValues()` (line 35)
3. Sends the OTP via Semaphore SMS API (lines 82-89)
4. Stores the OTP in `phone_otp` with a 10-minute expiry (`expires_at`) (lines 136-142)
5. Deletes any previous OTP for the same phone before inserting (lines 126-129)

**OTP Verification (`verify-phone-otp` Edge Function):** The `verify-phone-otp` Edge Function (`supabase/functions/verify-phone-otp/index.ts`) handles verification:
1. Rate-limits verification attempts to 10 per 15 minutes per phone (lines 10-27)
2. Calls the `verify_and_consume_phone_otp(p_phone, p_otp)` RPC which atomically checks the OTP and deletes the row in a single transaction (lines 63-67)
3. Returns success/failure — the RPC's atomicity prevents replay attacks since the OTP row is consumed on first successful verification
4. Rate limiting at both the generation and verification stages provides defense against brute-force attacks

### 2.7 Audit Domain

`audit_logs` captures actor, target, severity, category, and JSON detail payloads, enabling non-repudiation-oriented operational review.

## 3. PII Mapping and Movement Pipeline

### 3.1 Mobile Save Path (Data at Rest)

Mobile form values are transformed into field-level records keyed by `field_id` and written to `user_field_values`. For encrypted rows, AES metadata (`iv`, `encryption_version`) is written alongside ciphertext.

### 3.2 Cross-Template Semantic Mapping

`form_fields.canonical_field_key` and semantic aliasing enable value reuse across heterogeneous templates. This allows one user profile corpus to hydrate multiple CSWD forms without hard-coded table proliferation.

### 3.3 Session Push (Data in Transit)

When transmission is initiated:

1. Encrypted envelope data is written to `form_submission` transport columns.
2. Session status transitions to `scanned` for dashboard pickup.

### 3.4 Zero-Knowledge Staging and Finalization

**In-Memory Decryption:** When staff open a session with `status='scanned'` and `transmission_version=1`, the `serve-submission-for-review` Edge Function decrypts the encrypted envelope on-demand and returns plaintext JSON ephemerally in the HTTP response. Staff review the decrypted payload directly in the dashboard UI.

If the session has passed `expires_at`, the same function returns HTTP 410 with `reason = 'session_expired'`, which the client can surface as an expired-session state instead of retrying the decryption path.

**Server-Side Finalization:** Upon review completion, staff finalize the record via the `encrypt-and-save-submission` Edge Function, which performs server-side AES-256-GCM encryption before persisting to `client_submissions`.

This creates three distinct encryption/security boundaries:

1. **At Rest (User Level):** Derived-key AES-GCM protection of PII in `user_field_values`.
2. **In Transit:** Hybrid AES/RSA encrypted payload in `form_submission` transport columns.
3. **At Rest (Finalized Record):** Server-side AES encryption of finalized applicant records in `client_submissions.data`.

These layered protections ensure that sensitive data remains protected across the entire intake lifecycle.

## 4. Forensic Traceability

The schema supports chain-of-custody reconstruction:

1. `user_accounts.user_id` -> `user_field_values.user_id` (user PII ownership).
2. `form_submission.user_id` (user-to-session linkage).
3. `client_submissions.session_id` (final-record linkage to scanned session).
4. `audit_logs` records actor and action context for privileged operations.

## 5. Core Feature Conformance

The schema supports manuscript-required features:

1. Mobile PII management through persistent field-level storage.
2. Hybrid cryptographic transit through encrypted session envelope columns.
3. Secured autofill through decrypt-to-session and staff completion workflows.
4. CSWD dashboard governance through role/status-constrained staff identity tables.

## 6. Row Level Security (RLS) — Staff Tables

### 6.1 RLS Architecture

Staff identity tables (`staff_accounts`, `staff_profiles`, `staff_display_view`) are locked down with restrictive RLS policies. Since the application uses **custom authentication** (not Supabase Auth), `auth.uid()` is always null and cannot be used for policy gating.

The protection strategy is:

1. **RLS enabled** on `staff_accounts` and `staff_profiles`.
2. **RESTRICTIVE deny-all policies** applied to `anon` and `authenticated` roles on both tables — blocking all SELECT, INSERT, UPDATE, and DELETE.
3. **SELECT revoked** on `staff_display_view` from `anon` and `authenticated` roles.

### 6.2 Access Control Flow

All staff table operations route through the `manage-staff-account` Edge Function, which uses `SUPABASE_SERVICE_ROLE_KEY` (bypasses RLS):

```
Flutter Client → Edge Function (service role key) → staff_accounts/staff_profiles/staff_display_view
```

The anon key shipped with the client can no longer read or write any staff table directly.

### 6.3 Edge Function Actions

| Action | Purpose |
|---|---|
| `login` | Superadmin lookup by username, staff lookup by email |
| `update_last_login` | Set `last_login = now()` |
| `fetch_profile` | Get profile fields by cswd_id |
| `fetch_account` | Get account (email/username/role/status) by email or cswd_id |
| `fetch_password_hash` | Get password_hash by cswd_id |
| `check_username` | Case-insensitive username existence check |
| `check_username_unique` | Exact-match uniqueness check |
| `create_pending` | Insert into both tables with rollback on profile failure |
| `create_admin` | Insert admin account + profile with rollback |
| `update_account` | Generic UPDATE with dynamic fields |
| `fetch_accounts` | Pending + active account lists |
| `fetch_staff_batch` | Bulk account/profile fetch by ID list |
| `fetch_display` | SELECT from staff_display_view |



## 7. Hardening Notes from Current Schema Context

1. Add or verify unique constraints for (`user_id`, `field_id`) in `user_field_values` to align with deterministic upsert expectations.
2. Monitor `encryption_version` distribution and missing-IV anomalies.
3. Keep `app_rsa_keypairs` activation and rotation governance auditable through `audit_logs`.
4. Remaining dashboard and mobile features (`dashboard_analytics_service.dart`, `supabase_service.dart`, `history_controller.dart`) still query staff tables directly with anon key — they silently return empty under RLS. Migrate these to Edge Function actions if dashboard functionality is needed.
5. **Secure random number generation verified (v1.0.0):** All cryptographic RNG usage across the codebase was confirmed as cryptographically secure:
   - No `java.util.Random` usage in first-party Android/Kotlin code
   - Dart crypto layer uses `encrypt.IV.fromSecureRandom()` and `encrypt.Key.fromSecureRandom()`
   - Edge function OTP generation uses `crypto.getRandomValues()`

### 7.1 Login Filter Injection Hardening (v1.0.0 → v1.0.1)

The `SupabaseService.login()` method's PostgREST `.or()` filter construction was initially hardened against filter-grammar injection by stripping syntactic characters. In v1.0.1 this was **replaced entirely** with parameterized `.ilike()` queries to eliminate the injection surface completely:

```dart
// v1.0.0: character-strip approach (still used string interpolation)
final safeIdentifier = identifier.replaceAll(RegExp(r'[,()]'), '');
.or('username.ilike.$safeIdentifier,email.ilike.$safeIdentifier')

// v1.0.1: parameterized queries — no string interpolation at all
Map<String, dynamic>? account = await _supabase
    .from('user_accounts')
    .select('user_id, username, email, phone_number, is_active')
    .ilike('username', identifier)
    .maybeSingle();

if (account == null) {
  account = await _supabase
      .from('user_accounts')
      .select('user_id, username, email, phone_number, is_active')
      .ilike('email', identifier)
      .maybeSingle();
}
```

The Supabase Dart client's `.ilike()` method safely binds the user-supplied value as a query parameter rather than embedding it in a filter string, preventing PostgREST filter-grammar injection (CWE-89). This change was validated by MobSF v4.5.1 static analysis — the SQL Injection warning was downgraded from warning to resolved.

### 7.2 Release-Mode Log Stripping (v1.0.1)

MobSF flagged `debugPrint()` calls as a sensitive-logging risk (CWE-532). A `LogUtil` wrapper was created at `lib/services/log_util.dart` that eliminates all log output in release builds:

```dart
// lib/services/log_util.dart
void Function(String? message, {int? wrapWidth}) logPrint = kReleaseMode
    ? _noOp       // release: silently discards
    : debugPrint; // debug/profile: forwards normally

class LogUtil {
  static void debugPrint(String? message, {int? wrapWidth}) {
    logPrint(message, wrapWidth: wrapWidth);
  }
}
```

**Migration strategy:** All PII-handling and crypto services (`hybrid_crypto_service.dart`, `web_auth_service.dart`, `supabase_service.dart`) have been migrated from raw `debugPrint()` to `LogUtil.debugPrint()`. In `flutter build --release`, the Dart compiler eliminates these calls entirely since `kReleaseMode` is a compile-time constant. This satisfies MobSF's MSTG-STORAGE-3 requirement without losing debug visibility during development.

### 7.3 Production Keystore and Minimum SDK (v1.0.1)

Two high-severity MobSF findings were addressed in `android/app/build.gradle.kts`:

1. **Debug Certificate → Production Keystore:** The release build type now uses `signingConfigs.getByName("release")` instead of `signingConfigs.getByName("debug")`. A production keystore (`sappiire-release.jks`, RSA 2048-bit, PKCS12 format) was generated and linked via `android/key.properties` (gitignored). The keystore has a 10,000-day validity and is protected by `.gitignore` rules (`**/*.jks`, `**/*.jks.old`).

2. **Minimum SDK Bump (24 → 29):** `minSdk` was overridden from `flutter.minSdkVersion` (which resolved to 24, Android 7.0) to `29` (Android 10). This ensures the app only installs on devices that receive standard security updates, addressing the "App can be installed on a vulnerable unpatched Android version" finding.

```kotlin
defaultConfig {
    minSdk = 29  // was flutter.minSdkVersion → 24
    // ...
}

buildTypes {
    getByName("release") {
        signingConfig = signingConfigs.getByName("release")  // was debug
        // ...
    }
}
```

### 7.4 Exported Broadcast Receiver Hardening (v1.0.1)

The `androidx.profileinstaller.ProfileInstallReceiver` was flagged as exported (`android:exported=true`) with a permission that could be obtained by other apps. The fix in `AndroidManifest.xml` overrides the receiver with `android:exported="false"` and uses `tools:replace="android:exported"` to win the manifest merger conflict:

```xml
<receiver
    android:name="androidx.profileinstaller.ProfileInstallReceiver"
    android:exported="false"
    tools:replace="android:exported"
    tools:node="merge">
    <intent-filter>
        <action android:name="androidx.profileinstaller.action.INSTALL_PROFILE" />
    </intent-filter>
</receiver>
```

This ensures only apps signed with the same certificate can interact with the receiver, addressing the "protection level should be checked" warning.

### 7.5 MobSF v4.5.1 Post-Remediation Score

After applying all fixes, a second MobSF scan was performed on the release APK:

| Metric | Before (Pre-Remediation) | After (Post-Remediation) |
|--------|--------------------------|--------------------------|
| **Security Score** | 46/100 (Medium Risk) | **64/100 (Low Risk)** |
| **Grade** | B | **A** |
| **High Severity** | 2 (debug cert, minSdk) | **0** |
| **Warning** | 4 (SQL injection, insecure RNG, temp file, external storage) | 0 (all false positives or resolved) |
| **Info** | 2 (logging, clipboard) | 2 (logging, clipboard — both mitigated) |
| **Exported Receivers** | 1 (ProfileInstallReceiver) | **0** |

**Score improvement: +18 points.** All high-severity and warning-level findings were resolved or documented as false positives.

**Remaining info-level findings:**
- **Logging (CWE-532):** Mitigated via `LogUtil` — all logs stripped in release builds.
- **Clipboard (MSTG-STORAGE-10):** No first-party clipboard usage found; flagged references are in Flutter engine code (`io/flutter/plugin/editing/d.java`), not application code.
- **Shared library warnings (stack canaries, fortified functions):** Documented as not applicable to Dart/Flutter libraries per MobSF documentation. The `libdatastore_shared_counter.so` library (from a third-party plugin) lacks stack canaries but is not a first-party concern.

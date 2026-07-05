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

### 2.2 PII at Rest: `user_field_values`

`user_field_values` stores mobile-sourced field values by (`user_id`, `field_id`) with cryptographic metadata:

1. `field_value` for encrypted value content.
2. `iv` for AES-GCM decryption metadata.
3. `encryption_version` (smallint) records the protection state for the stored value and supports future migration paths.
4. `updated_at` for recency resolution.

Foreign-key linkage to `form_fields(field_id)` binds values to dynamic metadata definitions.

The application derives protection keys through the `derive-field-key` Edge Function and stores the resulting ciphertext metadata in the row alongside the encrypted value.

### 2.3 Transport Session Layer: `form_submission`

`form_submission` is the system's QR handshake anchor and enforces lifecycle constraints:

1. `status` domain is constrained to `active`, `scanned`, `completed`, `closed`, `expired`.
2. `expires_at` defaults to 10-minute session validity.
3. Hybrid transport columns include `encrypted_payload`, `payload_iv`, `encrypted_aes_key`, and `transmission_version`.
4. Staff linkage is modeled through optional `user_id` foreign key (not enforced in schema).
5. **Zero-Knowledge Staging:** Decryption occurs strictly in-memory via the `serve-submission-for-review` Edge Function during the request lifecycle, delivering plaintext ephemerally to the dashboard without any database persistence.

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
5. **Decryption Access Control:** The `decrypt-submission-data` Edge Function authorizes decryption requests based on staff role (`admin`, `form_editor`, `superadmin`), preventing `viewer` role access to plaintext records.
6. This architecture provides a defense-in-depth layer protecting finalized applicant records at rest, complementing client-side field encryption in `user_field_values` and hybrid transport encryption in `form_submission`.

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

1. `role` in {viewer, form_editor, admin, superadmin}
2. `requested_role` in {viewer, form_editor, admin}
3. `account_status` in {pending, active, deactivated}
4. `is_active` and `is_first_login` for operational gatekeeping

Complementary verification tables:

1. `phone_otp` for time-bounded mobile OTP.

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

### 6.4 Migration Reference

File: `supabase/migrations/20240001000000_staff_rls.sql`

## 7. Hardening Notes from Current Schema Context

1. Add or verify unique constraints for (`user_id`, `field_id`) in `user_field_values` to align with deterministic upsert expectations.
2. Monitor `encryption_version` distribution and missing-IV anomalies.
3. Keep `app_rsa_keypairs` activation and rotation governance auditable through `audit_logs`.
4. Remaining dashboard and mobile features (`dashboard_analytics_service.dart`, `supabase_service.dart`, `history_controller.dart`) still query staff tables directly with anon key — they silently return empty under RLS. Migrate these to Edge Function actions if dashboard functionality is needed.

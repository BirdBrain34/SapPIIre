# 02. Database Security and PII Mapping

## 1. Security Partitioning Overview

The Supabase schema separates data into distinct security domains to reduce exposure coupling:

1. Cryptographic key registry domain (`app_rsa_keypairs`).
2. User-owned PII value domain (`user_field_values`).
3. Live session transport domain (`form_submission`, `submission_field_values`, `display_sessions`).
4. Finalized applicant archive domain (`client_submissions`).
5. Identity and access governance domain (`staff_accounts`, `staff_profiles`, OTP tables, `audit_logs`).

This partitioning supports controlled data progression from user input, to encrypted transfer, to staff-verified final records.

## 2. Schema-Coupled Security Responsibilities

### 2.1 Cryptographic Key Governance

`app_rsa_keypairs` stores versioned public keys (`key_version`, `public_key_pem`, `is_active`, `rotated_at`). The table is explicitly public-key oriented; private decryption material remains outside relational storage in Edge secrets.

### 2.2 PII at Rest: `user_field_values`

`user_field_values` stores mobile-sourced field values by (`user_id`, `field_id`) with cryptographic metadata:

1. `field_value` for encrypted or legacy value content.
2. `iv` for AES-GCM decryption metadata.
3. `encryption_version` (smallint) for cipher-state branching.
4. `updated_at` for recency resolution.

Foreign-key linkage to `form_fields(field_id)` binds values to dynamic metadata definitions.

### 2.3 Transport Session Layer: `form_submission`

`form_submission` is the system's QR handshake anchor and enforces lifecycle constraints:

1. `status` domain is constrained to `active`, `scanned`, `completed`, `closed`, `expired`.
2. `expires_at` defaults to 30-minute session validity.
3. Hybrid transport columns include `encrypted_payload`, `payload_iv`, `encrypted_aes_key`, and `transmission_version`.
4. Staff linkage is modeled through `cswd_id` foreign key to `staff_accounts(cswd_id)`.

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

### 2.6 Access and Verification Layer

`staff_accounts` and `staff_profiles` implement dashboard identity governance with schema-level role and status constraints:

1. `role` in {viewer, form_editor, admin, superadmin}
2. `requested_role` in {viewer, form_editor, admin}
3. `account_status` in {pending, active, deactivated}
4. `is_active` and `is_first_login` for operational gatekeeping

Complementary verification tables:

1. `phone_otp` for time-bounded mobile OTP.
2. `staff_password_reset_otp` for staff credential recovery.

### 2.7 Audit Domain

`audit_logs` captures actor, target, severity, category, and JSON detail payloads, enabling non-repudiation-oriented operational review.

## 3. PII Mapping and Movement Pipeline

### 3.1 Mobile Save Path (Data at Rest)

Mobile form values are transformed into field-level records keyed by `field_id` and written to `user_field_values`. For encrypted rows, AES metadata (`iv`, `encryption_version`) is written alongside ciphertext.

### 3.2 Cross-Template Semantic Mapping

`form_fields.canonical_field_key` and semantic aliasing enable value reuse across heterogeneous templates. This allows one user profile corpus to hydrate multiple CSWD forms without hard-coded table proliferation.

### 3.3 Session Push (Data in Transit)

When transmission is initiated:

1. Normalized rows are written to `submission_field_values` (session-level per-field trace).
2. Encrypted envelope data is written to `form_submission` transport columns.
3. Session status transitions to `scanned` for dashboard pickup.

### 3.4 Decrypt and Finalize

Edge decryption writes plaintext JSON into `form_submission.form_data`. Staff review and finalize into `client_submissions` via the `encrypt-and-save-submission` Edge Function, which performs server-side AES-256-GCM encryption before persisting. This creates three distinct encryption/security boundaries:

1. **At Rest (User Level):** Client-side AES encryption of PII in `user_field_values`.
2. **In Transit:** Hybrid AES/RSA encrypted payload in `form_submission` transport columns.
3. **At Rest (Finalized Record):** Server-side AES encryption of finalized applicant records in `client_submissions.data`.

These layered protections ensure that sensitive data remains protected across the entire intake lifecycle.

## 4. Forensic Traceability

The schema supports chain-of-custody reconstruction:

1. `user_accounts.user_id` -> `user_field_values.user_id` (user PII ownership).
2. `form_submission.user_id` and `form_submission.cswd_id` (user-to-staff session linkage).
3. `submission_field_values.submission_id` -> `form_submission.id` (session field evidence).
4. `client_submissions.session_id` (final-record linkage to scanned session).
5. `audit_logs` records actor and action context for privileged operations.

## 5. Core Feature Conformance

The schema supports manuscript-required features:

1. Mobile PII management through persistent field-level storage.
2. Hybrid cryptographic transit through encrypted session envelope columns.
3. Secured autofill through decrypt-to-session and staff completion workflows.
4. CSWD dashboard governance through role/status-constrained staff identity tables.

## 6. Hardening Notes from Current Schema Context

1. Add or verify unique constraints for (`user_id`, `field_id`) in `user_field_values` and (`submission_id`, `field_id`) in `submission_field_values` to align with deterministic upsert expectations.
2. Maintain strict RLS policies to confine decrypted payload visibility.
3. Monitor `encryption_version` distribution and missing-IV anomalies.
4. Keep `app_rsa_keypairs` activation and rotation governance auditable through `audit_logs`.

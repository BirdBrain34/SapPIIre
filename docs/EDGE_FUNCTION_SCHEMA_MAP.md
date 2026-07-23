# Edge Function ↔ Database Schema Map

## 1. Edge Functions

### `derive-field-key`
**File:** `supabase/functions/derive-field-key/index.ts`  
**Purpose:** HMAC-SHA256 per-user AES key derivation. No direct table access. Called by mobile client for `user_field_values` encryption.  
**Key operations:** JWT validation via `supabase.auth.getUser(token)` (line 48), HMAC-SHA256 derivation (lines 59-75). Key never persisted — returned in HTTP response, cached in volatile memory only.  
**Environment:** `FIELD_KEY_HMAC_SECRET_V2`

---

### `encrypt-and-save-submission`
**Files:** `supabase/functions/encrypt-and-save-submission/index.ts`, `canonical_hash.ts`, `applicant_identity.ts`  
**Purpose:** Server-side AES-256-GCM encryption of finalized applicant records, plus duplicate-submission detection. Called on staff finalization.

| Table | Column | Operation | Lines |
|-------|--------|-----------|-------|
| `form_submission` | user_id | SELECT by session_id (identity resolution) | `applicant_identity.ts` `deriveApplicantKey` |
| `form_fields` | field_id, field_name, canonical_field_key | SELECT (10-min cached; maps payload labels to name/DOB) | `applicant_identity.ts` `loadFieldMap` |
| `client_submissions` | id, intake_reference, created_at | SELECT (duplicate lookup, newest match) | 25-46, 123 |
| `client_submissions` | session_id | UPSERT (onConflict: session_id) | 175-190 |
| `client_submissions` | template_id, form_code, form_type | UPSERT | 178-180 |
| `client_submissions` | data (base64 ciphertext) | INSERT | 181 |
| `client_submissions` | data_iv | INSERT | 182 |
| `client_submissions` | data_encryption_version (= 1) | INSERT | 183 |
| `client_submissions` | created_by | INSERT | 184 |
| `client_submissions` | intake_reference | INSERT | 185 |
| `client_submissions` | **content_hash** (CSH-1 of plaintext) | INSERT | 186 |
| `client_submissions` | **applicant_key** (identity token) | INSERT | 187 |
| RPC: `next_client_submission_ref()` | — | Sequence counter | 161 |

**Environment:** `SERVER_AES_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`

#### Request body

| Field | Required | Notes |
|-------|----------|-------|
| `sessionId` | yes | `form_submission.id`; upsert conflict key |
| `formType` | yes | |
| `data` | yes | **Plaintext** payload object; encrypted server-side |
| `templateId`, `formCode`, `createdBy` | no | |
| `intakeReference` | no | Generated from the sequence when omitted |
| `acknowledgeDuplicate` | no | `true` skips the duplicate check entirely. Set by the client after staff answer "Save anyway" |

#### Responses

| Status | Body | Meaning |
|--------|------|---------|
| 200 | `{id, intake_reference}` | Saved |
| **409** | `{duplicate: true, reason: "identical_submission", existing: {id, intake_reference, created_at}}` | Payload matches an earlier submission by the same applicant. **Nothing was written.** Returned before the sequence RPC runs, so a cancelled save never leaves a gap in the intake reference series |
| 400 | `{error}` | Missing `sessionId` / `formType` / `data` |
| 500 | `{error, details}` | Config, encryption, or insert failure |

#### Duplicate detection

The function is the only place plaintext and the database meet — `data` is stored as AES-GCM
ciphertext with a random IV, so no SQL expression can compare two submissions' answers. It
therefore hashes the plaintext (CSH-1, `canonical_hash.ts`) into the plaintext `content_hash`
column, and derives `applicant_key` (`user:<uuid>`, else a salted `pii:` fingerprint of
last+first+DOB, else `NULL`).

Detection is **advisory** — there is deliberately no `UNIQUE` constraint, because staff can
override the warning. Full specification, including the identity rules and why a `NULL`
`applicant_key` disables the check: `docs/15_Submission_Deduplication.md`.

`applicant_identity.ts` duplicates helpers from `search-applicants/index.ts` (fingerprinting,
normalization, `projectFromBlob`, `loadFieldMap`) because Supabase deploys each function
directory independently and cross-directory imports are fragile. Keep the two in sync by hand.

---

### `decrypt-submission-data`
**File:** `supabase/functions/decrypt-submission-data/index.ts`  
**Purpose:** Single-record AES-256-GCM decryption with staff authorization.

| Table | Column | Operation | Lines |
|-------|--------|-----------|-------|
| `staff_accounts` | cswd_id | SELECT (validate staff exists) | 49-53 |
| `staff_accounts` | role | SELECT (block viewer) | 62 |
| `client_submissions` | data, data_iv, data_encryption_version | SELECT | 75-78 |
| `audit_logs` | — | INSERT (decryption event) | 132-138 |

**Environment:** `SERVER_AES_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`

---

### `decrypt-submission-batch`
**File:** `supabase/functions/decrypt-submission-batch/index.ts`  
**Purpose:** Batch decryption (up to 20 records). Single key import, parallel `Promise.all`.

| Table | Column | Operation | Lines |
|-------|--------|-----------|-------|
| `staff_accounts` | role | SELECT (block viewer) | 66-78 |
| `client_submissions` | id, data, data_iv, data_encryption_version | SELECT (inFilter) | 82-85 |

**Environment:** `SERVER_AES_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`

---

### `serve-submission-for-review`
**File:** `supabase/functions/serve-submission-for-review/index.ts`  
**Purpose:** Zero-knowledge staging decryption. RSA unwrap + AES-GCM decrypt. Plaintext never written to DB.

| Table | Column | Operation | Lines |
|-------|--------|-----------|-------|
| `staff_accounts` | role, is_active, account_status | SELECT (authorization) | 89-93 |
| `form_submission` | id, encrypted_payload, payload_iv | SELECT | 113 |
| `form_submission` | encrypted_aes_key, transmission_version, status, expires_at | SELECT | 113 |
| `audit_logs` | — | INSERT (preview event) | 202-210 |

Expired sessions return HTTP 410 `session_expired` (line 125).  
**Environment:** `RSA_PRIVATE_KEY_PEM`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`

---

### `decrypt-qr-payload`
**File:** `supabase/functions/decrypt-qr-payload/index.ts`  
**Purpose:** QR session validation. Does NOT decrypt — only validates envelope existence and transitions status.

| Table | Column | Operation | Lines |
|-------|--------|-----------|-------|
| `form_submission` | id | SELECT (exists check) | 103-110 |
| `form_submission` | encrypted_payload, payload_iv, encrypted_aes_key | SELECT (non-empty check) | 117-119 |
| `form_submission` | transmission_version | SELECT (= 1) | 109 |
| `form_submission` | status | UPDATE → 'scanned' (only if 'active') | 129-133 |
| `form_submission` | scanned_at | UPDATE → now() | 131 |

**Environment:** `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`

---

### `resolve-applicant-names`
**File:** `supabase/functions/resolve-applicant-names/index.ts`  
**Purpose:** Server-side decryption of applicant names for dashboard display. Staff never need encryption keys.

| Table | Column | Operation | Lines |
|-------|--------|-----------|-------|
| `staff_accounts` | — | SELECT (validate staff active) | 118-121 |
| `form_fields` | field_id | SELECT by canonical_field_key IN (first_name, middle_name, last_name) | 162-163 |
| `user_field_values` | user_id, field_id, field_value, iv, encryption_version, updated_at | SELECT (inFilter) | 193-198 |

**Environment:** `FIELD_KEY_HMAC_SECRET_V2`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`

---

### `manage-staff-account`
**File:** `supabase/functions/manage-staff-account/index.ts`  
**Purpose:** All staff account lifecycle operations. 17 action types. Centralizes staff table access behind Edge Function (RLS bypass via service role key).

| Action | Lines | Tables | Description |
|--------|-------|--------|-------------|
| `login` | 95-181 | `staff_accounts` | Authenticate by username/email, bcrypt verify |
| `change_password` | 183-219 | `staff_accounts` | Verify current password, hash + update |
| `update_password` | 221-246 | `staff_accounts` | Force-update (first-login flow) |
| `reset_superadmin_password` | 248-281 | `staff_accounts` | Token-gated recovery |
| `validate_session` | 283-312 | `staff_accounts` | Check account is still active |
| `update_last_login` | 315-325 | `staff_accounts` | Set last_login = now() |
| `fetch_profile` | 327-339 | `staff_profiles` | Get profile fields |
| `fetch_account` | 341-360 | `staff_accounts` | Get account by email or cswd_id |
| `fetch_password_hash` | 362-374 | `staff_accounts` | Get password_hash |
| `check_username` | 376-388 | `staff_accounts` | Case-insensitive uniqueness |
| `check_username_unique` | 390-402 | `staff_accounts` | Exact-match uniqueness |
| `create_pending` | 404-459 | `staff_accounts`, `staff_profiles` | Insert pending staff (rollback on failure) |
| `create_admin` | 461-513 | `staff_accounts`, `staff_profiles` | Insert active admin (rollback on failure) |
| `update_account` | 515-542 | `staff_accounts` | Generic UPDATE |
| `fetch_accounts` | 544-559 | `staff_accounts` | Pending + active lists |
| `fetch_staff_batch` | 561-579 | `staff_accounts`, `staff_profiles` | Bulk account + profile |
| `fetch_display` | 581-593 | `staff_display_view` (DB view) | Staff display info |

**Environment:** `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPERADMIN_PASSWORD_RESET_TOKEN`

---

### `send-phone-otp`
**File:** `supabase/functions/send-phone-otp/index.ts`  
**Purpose:** Generate and store OTP. Semaphore SMS API. Rate-limited 3 requests/10min per phone.

| Table | Column | Operation | Lines |
|-------|--------|-----------|-------|
| `phone_otp` | phone | DELETE (remove old) | 127-129 |
| `phone_otp` | phone, otp, expires_at, created_at | INSERT | 136-142 |

**Environment:** `SEMAPHORE_API_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`

---

### `verify-phone-otp`
**File:** `supabase/functions/verify-phone-otp/index.ts`  
**Purpose:** Atomic OTP verification and consumption. Rate-limited 10 attempts/15min per phone.

| Table | Operation | Lines |
|-------|-----------|-------|
| RPC: `verify_and_consume_phone_otp(p_phone, p_otp)` | SELECT (returns boolean — atomically verifies and deletes) | 63-67 |

**Environment:** `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`

---

## 2. Dart Services (Direct Table Access)

### `FieldValueService` (`lib/services/field_value_service.dart`)
| Table | Operations |
|-------|-----------|
| `user_field_values` | INSERT, SELECT, DELETE (batch) |
| `form_fields` | SELECT (canonical_field_key, field_name, field_label) |

### `FormTemplateService` (`lib/services/form_template_service.dart`)
| Table | Operations |
|-------|-----------|
| `form_templates` | SELECT with JOIN to sections, fields, options, conditions |
| `form_sections` | SELECT (nested) |
| `form_fields` | SELECT (nested) |
| `form_field_options` | SELECT (nested) |
| `form_field_conditions` | SELECT (nested) |

### `FormBuilderService` (`lib/services/form_builder_service.dart`)
| Table | Operations |
|-------|-----------|
| `form_templates` | INSERT, SELECT, UPDATE, DELETE |
| `form_sections` | INSERT, UPSERT, DELETE |
| `form_fields` | INSERT, UPSERT, DELETE, UPDATE (soft-archive) |
| `form_field_options` | INSERT, DELETE |
| `form_field_conditions` | INSERT, DELETE |
| `form_template_notifications` | INSERT |
| `form_submission` | DELETE (force-delete) |
| `client_submissions` | DELETE, SELECT (count) |
| `user_field_values` | DELETE (force-delete) |

### `SubmissionService` (`lib/services/forms/submission_service.dart`)
| Table | Operations |
|-------|-----------|
| `form_submission` | INSERT, SELECT, UPDATE, stream |
| `client_submissions` | UPSERT, SELECT, UPDATE, DELETE |

### `AuditLogService` (`lib/services/audit/audit_log_service.dart`)
| Table | Operations |
|-------|-----------|
| `audit_logs` | INSERT, SELECT (with filters), SELECT COUNT |

### `DashboardAnalyticsService` (`lib/services/dashboard_analytics_service.dart`)
| Table | Operations |
|-------|-----------|
| `client_submissions` | SELECT (aggregations) |
| `form_submission` | SELECT (session timing) |
| `audit_logs` | SELECT (staff workload) |
| RPC: `search_users_by_name_canonical` | SELECT |

---

## 3. Schema Coverage

| Table | Edge Functions | Dart Services | Covered |
|-------|---------------|---------------|---------|
| `staff_accounts` | `manage-staff-account`, `decrypt-submission-data`, `decrypt-submission-batch`, `serve-submission-for-review`, `resolve-applicant-names` | `WebAuthService`, `StaffAdminService`, `AuditLogService`, `DashboardAnalyticsService` | ✅ |
| `staff_profiles` | `manage-staff-account` | `WebAuthService`, `StaffAdminService`, `SupabaseService` | ✅ |
| `form_templates` | — | `FormTemplateService`, `FormBuilderService`, `SupabaseService`, `FieldValueService`, `DashboardConfigService` | ✅ |
| `form_sections` | — | `FormTemplateService`, `FormBuilderService` | ✅ |
| `form_fields` | `resolve-applicant-names`, `encrypt-and-save-submission` | `FormTemplateService`, `FormBuilderService`, `FieldValueService`, `SupabaseService`, `FormStateController` | ✅ |
| `form_field_options` | — | `FormTemplateService`, `FormBuilderService` | ✅ |
| `form_field_conditions` | — | `FormTemplateService`, `FormBuilderService` | ✅ |
| `user_field_values` | `resolve-applicant-names` | `FieldValueService`, `SupabaseService`, `FormBuilderService` | ✅ |
| `form_submission` | `serve-submission-for-review`, `decrypt-qr-payload`, `encrypt-and-save-submission` | `SubmissionService`, `SupabaseService`, `DisplaySessionService`, `FormBuilderService`, `DashboardAnalyticsService` | ✅ |
| `client_submissions` | `encrypt-and-save-submission`, `decrypt-submission-data`, `decrypt-submission-batch` | `SubmissionService`, `FormBuilderService`, `SupabaseService`, `DashboardAnalyticsService`, `IntakeAnalyticsService` | ✅ |
| `audit_logs` | `decrypt-submission-data`, `serve-submission-for-review` | `AuditLogService`, `WebAuthService`, `DashboardAnalyticsService` | ✅ |
| `phone_otp` | `send-phone-otp`, `verify-phone-otp` | `SupabaseService` | ✅ |
| `user_accounts` | — | `SupabaseService` | ✅ |
| `display_sessions` | — | `DisplaySessionService` | ✅ |
| `app_rsa_keypairs` | via RPC `get_active_rsa_public_key` | `HybridCryptoService` (via RPC) | ✅ |
| `form_template_notifications` | — | `FormBuilderService`, `FormTemplateNotificationService`, `SupabaseService` | ✅ |
| `dashboard_widget_configs` | — | `DashboardConfigService` | ✅ |
| `dashboard_card_settings` | — | *No application code references found* | ⚠️ |
| `user_notification_reads` | — | `SupabaseService` | ✅ |

**Note:** `dashboard_card_settings` exists in the schema (columns: `id`, `template_id` unique, `card_color`, `updated_at`, `updated_by`) but no Dart service or Edge Function reads or writes to it in the repository. Referenced in `docs/02_Database_Security_and_PII_Mapping.md` as storing card elevation preferences. May be managed directly on the database tier.

---

## 4. Summary Counts

| Metric | Count |
|--------|-------|
| Edge Functions deployed | 13 |
| Edge Functions documented above | 10 |
| Edge Functions with direct schema access | 9 of those documented (derive-field-key is pure computation) |
| Schema tables | 19 |
| Tables with Edge Function access | 13 |
| Tables with only Dart service access | 5 (form_templates, form_sections, form_field_options, form_field_conditions, display_sessions) |
| Tables with no application code references | 1 (dashboard_card_settings) |

**Known documentation gap.** `supabase/functions/` contains 13 function directories, but only 10
have sections in §1. Undocumented: `search-applicants`, `manage-user-account`, `send-staff-email`.
`search-applicants` is the largest of the three and is described in
`docs/14_Applicant_Search_and_Identity_Resolution.md`; it just has no table-level entry here.
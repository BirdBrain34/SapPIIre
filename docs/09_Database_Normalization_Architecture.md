# 09. Database Normalization Architecture

**Cross-Reference:** See `docs/02_Database_Security_and_PII_Mapping.md` for encryption key hierarchy, RLS policies, and security domain partitioning

---

## 1. Normalization Compliance

### 1.1 First Normal Form (1NF)

All columns are atomic. The `client_submissions.data` column stores a JSON document (either plaintext or AES-GCM ciphertext). This is an intentional **Serialized Object** pattern — the column is not decomposed for SQL-level attribute filtering; decrypted content is queried only in application memory after Edge Function decryption. This is an accepted exception to 1NF for non-relational payload storage.

`form_fields.validation_rules` (JSONB) and `audit_logs.details` (JSONB) follow the same pattern: variable-schema payloads that are interpreted programmatically, not decomposed relationally.

### 1.2 Second Normal Form (2NF)

All tables use single-column primary keys (UUID or int8). No partial functional dependencies on composite keys exist. 2NF is fully satisfied.

### 1.3 Third Normal Form (3NF)

**Status:** Substantial compliance with documented exceptions.

| Table | Column(s) | 3NF Violation | Production Justification |
|-------|-----------|---------------|--------------------------|
| `form_templates` | `created_by` (text) | Not FK to `staff_accounts.cswd_id` | Snapshot preservation — if staff account is deactivated or renamed, the historical creator identity remains readable without a JOIN returning NULL |
| `client_submissions` | `created_by`, `last_edited_by` (text) | Not FK to `staff_accounts.cswd_id` | Snapshot preservation — see above |
| `dashboard_widget_configs` | `created_by` (text) | Not FK to `staff_accounts.cswd_id` | Snapshot preservation |
| `dashboard_card_settings` | `updated_by` (text) | Not FK to `staff_accounts.cswd_id` | Snapshot preservation |
| `form_template_notifications` | `template_name` (text) | Denormalized from `form_templates.form_name` | Ensures notification text survives template rename |
| `audit_logs` | `actor_name`, `actor_role` (text) | Denormalized from `staff_profiles` + `staff_accounts` | Append-only event store — the audit trail must be interpretable even if referenced staff accounts are later removed |

**General justification for text-based actor references:** Government social services systems require immutable auditability. A strict UUID FK introduces two failure modes:
1. If the referenced account is deactivated, a JOIN returns NULL — the forensic question "Who performed this action?" becomes unanswerable
2. If the referenced account is renamed, the historical record no longer reflects the name at time of action

The text-based approach preserves identity as it existed at time of action. See `SupabaseService.fetchClientSubmissionHistoryByUser()` (`lib/services/supabase_service.dart`, lines 916–1027) for the dual-lookup pattern: text values matching UUID regex are resolved against `staff_profiles` for display; non-UUID values are used directly.

### 1.4 Boyce-Codd Normal Form (BCNF)

The metadata hierarchy (`form_templates` → `form_sections` → `form_fields`) creates functional dependencies:
- `template_id → form_name, form_code, reference_prefix, ...`
- `section_id → template_id`
- `field_id → template_id, section_id`

These are intentional BCNF violations forming a **realized hierarchy** — a standard pattern in content-management and form-builder systems where the hierarchy simplifies querying (single-JOIN access to all template metadata) at the cost of BCNF purity.

---

## 2. The Dynamic Form Metadata Model

### 2.1 Architecture

`form_templates` → `form_sections` → `form_fields` → `form_field_options` + `form_field_conditions`

Rather than one static SQL table per form type, the system defines form structure as relational metadata. This eliminates:
1. `CREATE TABLE`/`ALTER TABLE` DDL per new or modified form
2. Backend API endpoint changes per form
3. Client-side model recompilation per form
4. App store redeployment for form changes
5. Data migration scripts for field changes

A superadmin configures the metadata hierarchy through `FormBuilderService` (`lib/services/form_builder_service.dart`). `DynamicFormRenderer` (`lib/dynamic_form/dynamic_form_renderer.dart`) consumes it at runtime on both mobile and web channels — no application code changes required.

### 2.2 Cross-Form Data Portability via `canonical_field_key`

`form_fields.canonical_field_key` decouples form-specific field names from semantic meaning. The alias engine in `FieldValueService._semanticAliasFromText()` (`lib/services/field_value_service.dart`, lines 723–821) normalizes labels across language and naming variants:

| Input Variants | Normalized Key |
|---------------|----------------|
| `lastname`, `last_name`, `surname`, `family_name`, `apelyido` | `last_name` |
| `birthdate`, `date_of_birth`, `kapanganakan` | `birth_date` |
| `civil_status`, `marital_status`, `estadong_sibil_civil_status` | `civil_status` |
| `cp_number`, `contact_no`, `mobile_no`, `cellphone_number`, `phone` | `phone` |

The cross-form fill logic (`loadUserFieldValuesWithCrossFormFill`, lines 252–493) operates in three passes:
1. Direct load by exact `field_id` match
2. Canonical resolution: `field_id` → `canonical_field_key` → best value across all user field values
3. Signature fallback: query across all templates for `canonical_field_key = 'signature'`

### 2.3 Hybrid EAV: `user_field_values`

`user_field_values` is a **hybrid Entity-Attribute-Value structure with relational anchoring** — distinct from a classic EAV anti-pattern:

| Aspect | Classic EAV | This System |
|--------|-------------|-------------|
| Attribute definition | Free-text column | FK to `form_fields.field_id` (normalized metadata) |
| Attribute type | Generic varchar | Typed by `form_fields.field_type` (18 types) |
| Value constraints | None | `validation_rules` in `form_fields` (JSONB) |
| Encryption | None | `iv`, `encryption_version` columns per row |
| Query | Attribute-level only | JOIN through `form_fields` for typed access |

Field-level granularity provides:
1. **Encryption granularity**: PII-bearing fields are AES-GCM encrypted; non-sensitive fields remain plaintext. Reduces batch encryption overhead.
2. **Cross-form portability**: Canonical key resolution operates at the field level without JSONB blob parsing.
3. **Theoretical per-field access control**: Not implemented, but the schema supports it.

**Query trade-off**: Analytical JOINs through `form_fields` are required for type resolution. Acceptable because production analytics operate on `client_submissions` (finalized JSONB snapshots), not `user_field_values`. Per-user load queries are indexed by `user_id` → batch-filtered by `field_id` — fixed cost regardless of template count.

---

## 3. Referential Integrity Map

| Source | Ref Column | Target | FK Enforced? | Behavior | Justification |
|--------|-----------|--------|-------------|----------|---------------|
| `staff_profiles` | `cswd_id` | `staff_accounts.cswd_id` | Yes | RESTRICT | Profile must not exist without account |
| `form_field_options` | `field_id` | `form_fields.field_id` | Yes | CASCADE | Options are field metadata |
| `form_field_conditions` | `field_id` | `form_fields.field_id` | Yes | CASCADE | Conditions are field metadata |
| `form_sections` | `template_id` | `form_templates.template_id` | Yes | CASCADE | Sections are template metadata |
| `form_fields` | `template_id` | `form_templates.template_id` | Yes | CASCADE | Fields are template metadata |
| `user_field_values` | `field_id` | `form_fields.field_id` | Not enforced | Soft-archive | `FormBuilderService` soft-archives removed fields (lines 458-465) rather than hard-deleting |
| `user_field_values` | `user_id` | `user_accounts.user_id` | Not enforced | None | Cross-context: user may exist in Supabase Auth but not in `user_accounts` |
| `form_submission` | `user_id` | `user_accounts.user_id` | Not enforced | None | Cross-domain bridge |
| `client_submissions` | `session_id` | `form_submission.id` | Not enforced (unique on self) | None | Session may expire but submission must survive |
| `form_submission` | `template_id` | `form_templates.template_id` | Not enforced | None | Template may be archived but session must survive |
| `audit_logs` | `actor_id` | `staff_accounts.cswd_id` | Not enforced | None | Event store: account deletion must not erase audit evidence |
| `display_sessions` | `session_id` | `form_submission.id` | Not enforced | None | Realtime bridge; transient data |
| `dashboard_widget_configs` | `template_id` | `form_templates.template_id` | Not enforced | None | Display config; template deletion should not cascade |
| `user_notification_reads` | `user_id` | `user_accounts.user_id` | Not enforced | None | Cosmetic read tracking |

**Enforcement rule:** Strict FKs where data loss is unrecoverable (profile↔account, field metadata). Soft references where references span bounded contexts, must survive referenced entity deletion, or are transient/cosmetic.

### 3.1 The `user_field_values` Save Pattern

No `UNIQUE (user_id, field_id)` constraint exists. Application-level delete-then-insert is used instead:

```dart
// FieldValueService.saveUserFieldValues() (lines 115-131)
// Delete existing rows, then insert fresh ones
for (var i = 0; i < eligibleFieldIds.length; i += 50) {
  await _supabase.from('user_field_values')
      .delete().eq('user_id', userId).inFilter('field_id', chunk);
}
for (var i = 0; i < allRows.length; i += 50) {
  await _supabase.from('user_field_values').insert(chunk);
}
```

The `__CLEARED__` sentinel (lines 99-109) marks intentionally blanked fields. An upsert with `ON CONFLICT DO UPDATE` would overwrite rather than preserve sentinel rows — creating ambiguity between "never saved" and "intentionally cleared".

**Deduplication on read** (lines 163-170) keeps the most recently updated row per `field_id` using `updated_at DESC` ordering. This is deterministic without a composite unique constraint. **Acknowledged tech debt**: the unique constraint should be added in a future migration for defensive integrity.

### 3.2 `display_sessions` — Realtime Bridge

Optimized for Supabase Realtime subscription performance, not referential purity:

| Design Choice | Reason |
|--------------|--------|
| Text types for all columns | Avoids type-coercion edge cases in JSON serialization during Realtime broadcast |
| No foreign keys | Table must remain operational when referenced sessions expire or templates are archived |
| Nullable session/template columns | Represents `'standby'` state (no active session) |
| Denormalized `form_name` | Eliminates JOIN for stateless display monitor |

Access pattern (`lib/services/display_session_service.dart`): upsert on session start, upsert to standby on session end, subscribe via Realtime. Table is continuously overwritten — no long-lived data accumulates.

---

## 4. Constraint Enforcement

### 4.1 CHECK Constraints vs. ENUMs

Status and role columns use Postgres CHECK constraints rather than ENUM types:

| Table | Column | Domain | Evidence |
|-------|--------|--------|----------|
| `staff_accounts` | `role` | `admin`, `superadmin` | Edge Function line 525: `ALLOWED_ROLES = ['admin', 'superadmin']` |
| `staff_accounts` | `requested_role` | `admin`, `superadmin` | Doc 02 Section 2.6 |
| `staff_accounts` | `account_status` | `pending`, `active`, `deactivated` | Doc 02 Section 2.6 |
| `form_submission` | `status` | `active`, `scanned`, `completed`, `closed`, `expired` | `FormBuilderService._isStatusCheckConstraintError()` (line 36-40) catches PostgreSQL error code `23514` |
| `form_templates` | `status` | `draft`, `published`, `pushed_to_mobile`, `archived` | `FormBuilderService.archiveTemplate()` (line 732) |

CHECK constraints are preferred because:
- Adding a new constraint value uses `ALTER TABLE ... DROP/ADD CONSTRAINT` — both are transactional
- Adding an ENUM value uses `ALTER TYPE ... ADD VALUE` — **not transactional**, blocks concurrent access
- The application layer catches constraint violations (code `23514`) and provides fallback behavior:

```dart
// FormBuilderService.unpublishTemplate() (lines 688-708)
if (_isStatusCheckConstraintError(e)) {
  await _setLegacyArchiveFlag(templateId, archived: false, setInactive: true, statusOverride: 'draft');
}
```

### 4.2 Encryption Version Dispatch

The `encryption_version` column in `user_field_values` and `client_submissions` enables non-breaking cryptographic migration:

```dart
// field_value_service.dart (lines 211-224)
if (version == 2) {
  // Modern: server-derived HMAC-SHA256 key, AES-GCM encrypted
} else if (version == 0) {
  // Legacy: unencrypted plaintext
} else {
  continue; // Unknown version: skip safely
}
```

```typescript
// resolve-applicant-names/index.ts (lines 251-259)
if (version === 2) {
  resolved = await decryptField(rawValue, row['iv']?.toString() ?? '', key);
} else if (version === 0) {
  resolved = rawValue;
} else {
  console.warn(`Unsupported encryption_version=${version} — skipping`);
}
```

This provides forward compatibility (new schemes as `version=N+1`), zero-downtime migration (gradual row migration), and safe fallback (unknown versions are skipped, not crashed).

### 4.3 Atomic OTP Verification

`phone_otp` verification uses a dedicated RPC `verify_and_consume_phone_otp` that atomically verifies AND deletes the OTP in one transaction. This prevents:
1. **Replay attacks**: First verification succeeds; subsequent attempts find no row
2. **Race conditions**: Transaction isolation ensures only one verification succeeds

Rate limits: 3 requests/10min per phone (`send-phone-otp/index.ts`, lines 12-28), 10 verification attempts/15min (`verify-phone-otp/index.ts`, lines 10-27).

### 4.4 Race-Free Reference Sequence

`next_client_submission_ref` RPC (called from `encrypt-and-save-submission/index.ts`, lines 74-76) provides a sequence-based counter for intake references, replacing `form_templates.reference_counter` which serves as a configurable starting point only. Reference format: `{FORMCODE}-{YYYY}{MM}{DD}-{000001}`.

---

## 5. Schema Gaps and Type Divergence

### 5.1 `client_submissions.id` — int8 vs. UUID

All other tables use `uuid` primary keys. `client_submissions.id` uses `int8`. Rationale: server-created records do not require offline-generated UUIDs. Sequential int8 provides smaller index footprint (8 vs 16 bytes) and natural ordering. Type inconsistency is acknowledged but functional.

### 5.2 `client_submissions.data` — Dual-Mode Storage

| `data_encryption_version` | Content | Meaning |
|--------------------------|---------|---------|
| `0` | JSONB | Legacy unencrypted payload |
| `1` | base64 string | AES-256-GCM ciphertext |

```typescript
// decrypt-submission-batch/index.ts (lines 107-113)
if (row.data_encryption_version !== 1) {
  return { id: row.id, data: row.data, decrypted: false };
}
const payload = await decryptOne(row.data, row.data_iv, cryptoKey);
```

Legacy records are handled transparently. New submissions always use version 1. Recommendation: background migration to eliminate version 0 rows.

### 5.3 Repository Separation

`supabase/migrations/` was empty until the submission-deduplication work. It now holds the first version-controlled DDL in the repository:

| Migration | Purpose | Applied |
|-----------|---------|---------|
| `20260722_a_client_submissions_dedup_columns.sql` | Adds `client_submissions.content_hash` and `applicant_key` | ✅ |
| `20260722_b_client_submissions_dedup_lookup_index.sql` | Partial **non-unique** lookup index on `applicant_key`; defensively drops the unique index an earlier revision proposed | ✅ |

These are still applied by hand — there is no CI step that runs them — but they are now reviewable and reproducible. See `docs/15_Submission_Deduplication.md`. Treat this as the template for migrating the artifacts below into the repository.

There is **no** `UNIQUE (applicant_key, content_hash)` constraint, and adding one would be a regression: staff can override the duplicate warning, and a unique index would reject the acknowledged insert with SQLSTATE 23505. The migration file carries the same warning.

Applying migrations does not require the SQL Editor or a database password. The CLI runs them through the Management API:

```
supabase db query --linked -f supabase/migrations/<file>.sql
```

Note the filenames use a `YYYYMMDD_<letter>_` prefix rather than the Supabase CLI's expected 14-digit `YYYYMMDDHHMMSS_` format, so `supabase db push` and `supabase migration up` will not pick them up. That is intentional for now — this project has no migration history table, and the columns above were applied before the files existed. Adopt the 14-digit format if the migration history is ever initialized.

The following artifacts still exist only on the live database tier (Supabase SQL Editor) rather than in the application repository:

| Artifact | Purpose |
|----------|---------|
| Table DDL (CREATE TABLE) | Schema definitions |
| Index definitions | Performance optimization |
| CHECK constraint SQL | Domain enforcement |
| RPC definitions | `next_client_submission_ref`, `verify_and_consume_phone_otp`, `get_active_rsa_public_key`, `get_applicant_index`, `search_users_by_name_canonical` |
| `staff_display_view` | Database view for staff display |
| RLS policies | Row-level security for staff tables |
| `seed_superadmin.sql` | Referenced in `supabase/README_seed.md`, file absent from repo |

Edge Functions interact with the database through the Supabase JS client and service role key — not through SQL files in the repository. Recommendation: version-control these SQL definitions for production hardening.

---

*Cross-reference `docs/02_Database_Security_and_PII_Mapping.md` for encryption key hierarchy, RLS policy configurations, and security domain partitioning.*
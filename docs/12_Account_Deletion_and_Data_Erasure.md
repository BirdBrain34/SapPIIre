# 12. Account Deletion and Data Erasure (Right to Erasure)

## 1. Purpose

This document specifies the self-service **account deletion and data erasure** capability
added to the mobile client in v1.1.0. The feature operationalizes the data subject's **right
to erasure and blocking** already promised in the in-app privacy notice
(`lib/mobile/widgets/terms_and_condition.dart`, Section 5), which had previously been declared
but not implemented. It serves as an audit-ready reference for security reviewers and manuscript
evaluators.

## 2. Regulatory Basis

The capability implements the erasure right under the **Data Privacy Act of 2012 (Republic Act
No. 10173)** and the National Privacy Commission (NPC) rules. Consistent with a government CSWD
office's records-retention obligations, erasure is scoped to **user-owned personal data**;
records already submitted to and finalized by the office are retained as official records, and
the append-only audit trail is preserved as evidence.

| Principle | Implementation |
|-----------|----------------|
| Right to erasure (R.A. 10173 §16(e)) | User-initiated permanent deletion of login and PII |
| Records retention (official records) | `client_submissions` deliberately retained and remain visible to staff |
| Accountability / auditability | Erasure recorded in `audit_logs` before the purge |
| No cross-subject exposure | Server derives the target user from the JWT; a caller can only erase their own account |

## 3. User-Facing Flow

The action is surfaced in the mobile **Profile → Account Settings** section
(`lib/mobile/screens/auth/profile_screen.dart`) as a destructive `ProfileActionRow`
("Delete My Account", subtitle "Permanently erase your data (R.A. 10173)").

1. The user taps **Delete My Account**.
2. `ProfileController.handleDeleteAccount` guards against re-entrancy and blocks if there are
   pending unsaved profile edits (mirroring the logout guard).
3. A non-dismissible confirmation dialog (`lib/mobile/widgets/delete_account_dialog.dart`) is
   shown. It states the action is permanent, lists what is erased, carries a retention notice
   for already-submitted records, and enforces a **type-`DELETE`-to-confirm** gate before the
   destructive button is enabled.
4. On confirmation, `SupabaseService.deleteMyAccount` invokes the `manage-user-account` Edge
   Function. On success the local session and volatile crypto key cache are cleared, and the
   user is returned to the login screen with the full navigation stack removed.
5. On failure the dialog remains open and the error is surfaced via `SnackbarUtils.showError`,
   allowing a retry.

## 4. Architecture

Deletion is performed **server-side** in a new Supabase Edge Function using the service-role
key. A client-side deletion was rejected for two reasons: (a) the applicant tables have no
enforced Row-Level Security, so an anon-key delete would be callable against any user; and
(b) deleting the Supabase Auth identity requires the admin API, which is service-role only.
The function follows the established mobile/JWT authorization pattern of `derive-field-key` and
the action-discriminator shape of `manage-staff-account`.

### 4.1 Authorization Model

The target user is **never** taken from the request body. The caller's Supabase Auth JWT is
re-validated against the Auth service via `supabase.auth.getUser(token)`, and the resulting
`user.id` is the sole deletion target. This structurally prevents a user from deleting another
user's account, and prevents Insecure Direct Object Reference (IDOR).

### 4.2 Execution Order

The steps are ordered for resilience: deactivation first (so login is blocked even if a later
step fails), then the audit record (so the actor label survives the purge of the account row),
then the PII purge, then the Auth identity deletion.

## 5. Data Lifecycle: Erased vs. Retained

There are no `ON DELETE CASCADE` relationships on the user path, so the purge walks each table
explicitly.

| Table | Action | Rationale |
|-------|--------|-----------|
| `user_field_values` | **DELETE** by `user_id` | Primary encrypted PII store |
| `form_submission` | **DELETE** by `user_id` | Transient transport envelopes (10-minute `expires_at`) |
| `user_notification_reads` | **DELETE** by `user_id` | Read-tracking metadata |
| `user_accounts` | **DELETE** by `user_id` | Account identity (deactivated first, then removed) |
| `auth.users` | **DELETE** via `auth.admin.deleteUser` | Login identity |
| `client_submissions` | **RETAINED** | Finalized official intake records; shown in the web staff dashboard by `created_by` / `form_type`, independent of the deleted tables |
| `audit_logs` | **RETAINED** | Append-only, intentionally FK-free evidence trail |

> Because `client_submissions` carries its own AES-256-GCM ciphertext of the finalized record and
> is not keyed on `user_id`, submitted records survive erasure and remain reviewable by staff.

## 6. Edge Function ↔ Schema Map

### `manage-user-account`
**File:** `supabase/functions/manage-user-account/index.ts`
**Purpose:** Self-service applicant account actions. Action-discriminated (`delete_account`).
Authenticated by the caller's Supabase Auth JWT; target user derived server-side.

| Table | Column | Operation | Lines |
|-------|--------|-----------|-------|
| `user_accounts` | username | SELECT (audit label) | 70-75 |
| `user_accounts` | is_active | UPDATE → false (deactivate) | 80-83 |
| `audit_logs` | — | INSERT (`user_account_deleted`, best-effort) | 90-101 |
| `user_field_values` | user_id | DELETE | 109 |
| `form_submission` | user_id | DELETE | 110 |
| `user_notification_reads` | user_id | DELETE | 111 |
| `user_accounts` | user_id | DELETE | 112 |
| `auth.users` | id | DELETE (`auth.admin.deleteUser`) | 115 |
| Auth: `supabase.auth.getUser(token)` | — | JWT identity resolution | 52 |

**Environment:** `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`

## 7. Audit Logging

A `user_account_deleted` event is written with `category: 'auth'`, `severity: 'warning'`,
`actor_role: 'applicant'`, and `actor_id`/`target_id` set to the user's id, before any rows are
removed. The audit constant `kAuditUserAccountDeleted` is defined in
`lib/services/audit/audit_log_service.dart`, and human-readable label, description, and the
`applicant` role are rendered in the web audit viewer (`lib/web/screen/audit_logs_screen.dart`).

> The audit insert is wrapped in a best-effort `try/catch`. If the live `audit_logs` table has a
> `CHECK` constraint on `action_type` that rejects `user_account_deleted`, the write is skipped
> silently and the deletion still completes. To record the event, add the value to that
> constraint in the Supabase SQL editor.

## 8. Files Changed

| File | Change |
|------|--------|
| `supabase/functions/manage-user-account/index.ts` | **New.** `delete_account` Edge Function |
| `lib/services/supabase_service.dart` | Added `deleteMyAccount()`; clears session + crypto cache on success |
| `lib/mobile/widgets/delete_account_dialog.dart` | **New.** Danger-themed, type-`DELETE` confirmation dialog |
| `lib/mobile/controllers/profile_controller.dart` | Added `handleDeleteAccount()` |
| `lib/mobile/screens/auth/profile_screen.dart` | Added "Delete My Account" action row |
| `lib/services/audit/audit_log_service.dart` | Added `kAuditUserAccountDeleted` constant |
| `lib/web/screen/audit_logs_screen.dart` | Added label, description, and `applicant` role rendering |

## 9. Deployment

The Edge Function is deployed manually, consistent with project convention (no CI). No schema
migration is required — the purge reuses existing tables and `audit_logs`.

```bash
supabase functions deploy manage-user-account --project-ref tgbfxepldpdswxehhlkx
```

Reuses the existing `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` Edge Secrets already
configured for the other functions.

## 10. Verification

1. **Static checks:** `flutter analyze` on the changed files reports no new issues;
   `flutter test` passes the existing suite.
2. **End-to-end (throwaway account):**
   - Sign up, populate Profile PII, and complete one form/QR handshake so a `client_submissions`
     row exists.
   - Profile → Account Settings → **Delete My Account** → type `DELETE` → confirm.
   - Expected: returned to login; re-login fails; rows removed from `user_field_values`,
     `form_submission`, `user_notification_reads`, `user_accounts`, and the `auth.users` entry;
     `client_submissions` row still present and visible in the web dashboard; a
     `user_account_deleted` row present in `audit_logs`.
3. **Authorization:**
   - `delete_account` with a missing/invalid JWT → HTTP 401, no deletion.
   - `delete_account` with a valid JWT but a different `user_id` in the body → only the token's
     own account is deleted (the body value is ignored).

## 11. Related Documents

- [docs/02_Database_Security_and_PII_Mapping.md](docs/02_Database_Security_and_PII_Mapping.md) — PII table inventory and retention notes
- [docs/05_Mobile_Client_Core_Features.md](docs/05_Mobile_Client_Core_Features.md) — mobile identity and PII lifecycle
- [docs/09_Database_Normalization_Architecture.md](docs/09_Database_Normalization_Architecture.md) — non-enforced FKs and audit-log retention rationale
- [docs/EDGE_FUNCTION_SCHEMA_MAP.md](docs/EDGE_FUNCTION_SCHEMA_MAP.md) — full Edge Function ↔ schema map

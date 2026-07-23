# 13. Audit Trail Hardening for Sensitive Data Access

## 1. Purpose

This document records the remediation of a review finding that the audit trail did not adequately distinguish access to sensitive applicant information from routine system activity, and that its wording was not intelligible to the non-technical staff who operate the system.

The finding, as raised:

> Improve the audit trail for security actions; for example, specific wording like "Submission Decrypted" should be used as a critical warning or log entry when sensitive data is accessed.

It serves as an audit-ready reference alongside `02_Database_Security_and_PII_Mapping.md` §2.7 (Audit Domain), which defines the `audit_logs` table itself.

## 2. Pre-Remediation Baseline

The audit subsystem defined a three-tier severity model (`kSeverityInfo`, `kSeverityWarning`, `kSeverityCritical` — `lib/services/audit/audit_log_service.dart`) and the Audit Logs screen fully rendered it: a red colour treatment for critical entries, a severity filter, and a "Critical" summary tile.

**No code path in the system ever emitted a critical entry.** The tier existed in the schema and the interface with zero producers, so the summary tile permanently read `0` and filtering by critical returned an empty set. Decryption of a finalized applicant record — the single most sensitive operation the system performs — was recorded at `info`, indistinguishable from a routine sign-in.

Two further access paths wrote no audit entry at all, and one authorization gap suppressed logging silently:

| # | Baseline defect | Consequence |
|---|-----------------|-------------|
| 1 | Single-record decryption logged at `severity: 'info'` | Sensitive PII access indistinguishable from routine activity |
| 2 | `decrypt-submission-batch` wrote no audit entry | Bulk decryption for list rendering was entirely unaudited |
| 3 | `resolve-applicant-names` wrote no audit entry | Server-side decryption of applicant names was entirely unaudited |
| 4 | `decrypt-submission-data` accepted requests with no `staffId`, defaulting `actor_id` to the string `'anonymous'` | `audit_logs.actor_id` is a `uuid` column. The insert failed type validation, and because `supabase-js` returns errors rather than throwing, the failure was swallowed. **Unidentified callers could decrypt a record and leave no trace.** |
| 5 | Form approval and rejection wrote no audit entry | Privileged approval decisions were unrecorded. `kAuditTemplateRejected` was declared but never referenced anywhere in the codebase. |
| 6 | Interface wording was engineering terminology | Entries read `Submission Decrypted`, `Target Type: client_submission`, `Actor Role: superadmin`, `purpose: applicant_record_view`, `elapsed_ms: 1179` |

## 3. Severity Model

Severity is now assigned by the sensitivity of the data exposed, not by the technical mechanism used.

| Tier | Constant | Displayed as | Assigned when |
|------|----------|--------------|---------------|
| Critical | `kSeverityCritical` | **Sensitive** | A finalized applicant record was decrypted and viewed, individually or in bulk |
| Warning | `kSeverityWarning` | **Notice** | Partial PII exposure (names only), transient pre-save review, or a denial (failed sign-in, rejected form) |
| Info | `kSeverityInfo` | **Routine** | Ordinary operational activity |

Denials are deliberately placed at warning level, consistent with the existing `login_failed` precedent: a refused action is a case a reviewer needs to locate later.

## 4. Remediation Matrix

### 4.1 Server-Side (Edge Functions)

| # | Change | Severity emitted | File | Status |
|---|--------|------------------|------|--------|
| 1 | `submission_decrypted` escalated from `info` to `critical`; entry enriched with `actor_role`, `target_type`, `target_id` | `critical` | `supabase/functions/decrypt-submission-data/index.ts` (lines 151-157) | ✅ Deployed |
| 2 | `staffId` made unconditionally required; account validated for `role`, `is_active`, and `account_status` before any decryption | — | `decrypt-submission-data/index.ts` (lines 51, 74, 88-89) | ✅ Deployed |
| 3 | Bulk decryption now writes **one aggregated** critical entry per call carrying `count`, `ids`, and `purpose: 'list_view'` | `critical` | `decrypt-submission-batch/index.ts` (lines 153-162) | ✅ Deployed |
| 4 | Session preview decryption raised from `info` to `warning` | `warning` | `serve-submission-for-review/index.ts` (lines 203-205) | ✅ Deployed |
| 5 | Server-side name resolution now writes one aggregated entry per call carrying `requested` and `resolved` counts | `warning` | `resolve-applicant-names/index.ts` (lines 282-284) | ✅ Deployed |

**Aggregation rationale.** Bulk decryption and name resolution are invoked on every applicant-list render, up to 20 records per call. Emitting one entry per record would bury every other event in the log. Each call therefore writes a single summarizing entry, and the interface additionally collapses repeated entries by the same actor within a five-minute window (`_collapsibleActions`, `audit_logs_screen.dart`).

### 4.2 Client-Side (Flutter)

| # | Change | File | Status |
|---|--------|------|--------|
| 6 | Approving a form now writes an audit entry. The Approvals screen previously wrote none. | `lib/web/controllers/approvals_controller.dart` (line 70) | ✅ Implemented |
| 7 | Rejecting a form now writes a warning-level entry including the reason given, on both reject paths | `approvals_controller.dart` (lines 111-113), `form_builder_screen_controller.dart` (line 881) | ✅ Implemented |
| 8 | `ApprovalsController` given actor context (`cswdId`, `displayName`, `role`) so approval decisions are attributable | `approvals_controller.dart`, `approvals_screen.dart` | ✅ Implemented |
| 9 | Action constants added for previously unlabelled server-emitted types | `lib/services/audit/audit_log_service.dart` (lines 21-27) | ✅ Implemented |

## 5. Plain-Language Presentation

The Audit Logs screen is read by caseworkers and senior officials. All displayed text was rewritten in everyday office language, with no database or cryptography terminology on screen. Filter and query values are unchanged; only presentation was altered.

### 5.1 Activity Wording

| Stored `action_type` | Previously displayed | Now displayed |
|----------------------|---------------------|---------------|
| `submission_decrypted` | Submission Decrypted | **Applicant record opened** |
| `submission_preview_decrypted` | Submission Preview Decrypted | Submitted form reviewed |
| `applicant_names_resolved` | Applicant Names Resolved | Applicant names displayed |
| `submission_created` / `_edited` / `_deleted` | Submission Created / Edited / Deleted | Applicant record saved / edited / deleted |
| `login` / `login_failed` / `logout` | Login / Login Failed / Logout | Signed in / Failed sign-in attempt / Signed out |
| `session_started` / `_completed` / `_closed` | Session Started / Completed / Closed | Intake session started / completed / closed |
| `template_created` / `_published` | Template Created / Published | Form created / published |
| `template_pushed_to_mobile` | Pushed to Mobile | Form sent to mobile app |
| `template_submitted_for_approval` | Template Submitted for Approval | Form sent for approval |
| `template_approved` / `_rejected` | Template Approved / Rejected | Form approved / rejected |
| `canonical_key_created` / `_deactivated` | Canonical Key Created / Deactivated | Shared field added / removed |
| `role_changed` | Role Changed | Staff role changed |

The term "decrypted" was removed from the interface entirely. Staff do not need to know that data is encrypted at rest; they need to know that a person opened another person's private information. "Template" was replaced with "form" throughout, matching the vocabulary staff already use.

### 5.2 Supporting Vocabulary

| Element | Before | After |
|---------|--------|-------|
| Category chips | `auth`, `submission`, `template`, `session`, `staff` | Sign-in, Applicant records, Forms, Intake sessions, Staff accounts |
| Severity badge | `INFO` / `WARNING` / `CRITICAL` | ROUTINE / NOTICE / **SENSITIVE** |
| Role | `superadmin` / `admin` | Super Administrator / Administrator |
| Target type | `client_submission`, `form_template`, `user_field_values` | Applicant record, Form, Applicant details |
| Detail fields | `Actor`, `Actor Role`, `Target Type`, `Target ID` | Performed by, Role, Item type, Reference (item) |
| Detail values | `purpose: list_view`, `elapsed_ms: 1179`, `true` | Reason: Showing the applicant list, Time taken: 1.2 seconds, Yes |

### 5.3 Explanatory Text and Noise Suppression

Each entry's detail dialog now opens with a sentence stating what occurred and why it is recorded (`_actionDescription`, `audit_logs_screen.dart` line 370). For record access it reads:

> An applicant's protected personal information was opened and viewed. Personal details are kept locked in storage, so every time someone views them it is recorded here.

Internal diagnostic keys that carry no meaning for an operator (`query_hash`, `token_count`, `query_length`, `filters`, `ids`, `transmission_version`) are suppressed from display via `_hiddenDetailKeys` (line 510). The underlying `details` payload is unchanged in the database; only rendering is filtered. Actor and target identifiers are retained for investigation but relocated to the foot of the dialog and labelled as reference numbers.

### 5.4 Acknowledged Duplicate Submissions

A `submission_created` entry may carry `details.outcome = "duplicate_acknowledged"`, meaning staff were warned the form exactly matched an earlier submission by the same applicant and chose **Save anyway**. Accompanying keys: `duplicate_of_submission_id`, `duplicate_of_intake_reference`, `duplicate_of_created_at`.

This deliberately reuses the existing `submission_created` action type rather than introducing a new one. `audit_logs.action_type` is governed by a live CHECK constraint, and an unrecognized value causes the audit row to be **rejected outright** — losing the record of the very action being audited. Discriminating within `details` keeps the entry writable while remaining queryable:

```sql
select * from audit_logs
where action_type = 'submission_created'
  and details->>'outcome' = 'duplicate_acknowledged';
```

Only acknowledged saves are logged. A cancelled duplicate writes nothing at all — no submission row and no audit row — since nothing happened. See `docs/15_Submission_Deduplication.md`.

Presentation helpers: `_actionLabel` (303), `_actionDescription` (370), `_categoryLabel` (447), `_severityLabel` (466), `_roleLabel` (477), `_targetTypeLabel` (490), `_detailKeyLabel` (522), `_detailValueLabel` (554).

## 6. Files Changed

| File | Change Type |
|------|-------------|
| `supabase/functions/decrypt-submission-data/index.ts` | Severity escalation; mandatory staff authentication |
| `supabase/functions/decrypt-submission-batch/index.ts` | New aggregated audit entry |
| `supabase/functions/serve-submission-for-review/index.ts` | Severity escalation |
| `supabase/functions/resolve-applicant-names/index.ts` | New aggregated audit entry |
| `lib/services/audit/audit_log_service.dart` | Action-type constants |
| `lib/web/screen/audit_logs_screen.dart` | Plain-language presentation layer |
| `lib/web/controllers/approvals_controller.dart` | Approval/rejection audit logging; actor context |
| `lib/web/screen/approvals_screen.dart` | Controller construction with actor context |
| `lib/web/controllers/form_builder_screen_controller.dart` | Rejection audit logging |

## 7. Verification

Server-side changes were deployed to the production project (`tgbfxepldpdswxehhlkx`) and exercised directly against the live Edge Functions.

### 7.1 Authorization Enforcement

| Request | Result |
|---------|--------|
| `decrypt-submission-data` with no `staffId` | `400 Missing required field: staffId` — previously returned decrypted PII with no audit entry |
| `decrypt-submission-data` with a non-existent `staffId` | `403 Staff record not found` |
| `decrypt-submission-data` with a valid active `staffId` | `200`, record returned, audit entry written |

### 7.2 Audit Entries Produced

Entries observed in `audit_logs` following the test invocations:

```
submission_decrypted     | severity=critical | role=superadmin | target=client_submission/86
                         | details={"purpose":"applicant_record_view"}

submission_decrypted     | severity=critical | role=superadmin | target=client_submission
                         | details={"ids":[85,86],"count":2,"purpose":"list_view"}

applicant_names_resolved | severity=warning  | role=superadmin | target=user_field_values
                         | details={"requested":3,"resolved":2,"purpose":"list_view"}
```

Both decryption paths now produce critical entries; the previously unaudited bulk path produces one aggregated entry for two records, confirming the aggregation behaviour.

### 7.3 Static Analysis

`flutter analyze` reports no errors or warnings in any modified file.

## 8. Outstanding Items

1. **Client-side changes are not yet runtime-verified.** Items 6-9 in §4.2 and the presentation layer in §5 pass static analysis but have not been exercised in the running application. Confirmation requires creating a form, submitting it for approval, and approving and rejecting it while observing the Audit Logs screen.
2. **`serve-submission-for-review` severity change is untested at runtime.** Verification requires an active scanned QR session. The change is a single severity literal and carries correspondingly low risk.
3. **Audit writes remain best-effort.** `AuditLogService.log` and the Edge Function inserts suppress their own failures so that an audit error never fails the operation being audited. This is deliberate, but it means a persistent audit outage would be silent. Consider a periodic write-canary if non-repudiation guarantees are to be strengthened.
4. **Authorization remains partly client-side.** The restriction of approval to Super Administrators is enforced in `WebNavigator`, not in the database. See `02_Database_Security_and_PII_Mapping.md` §7 for the corresponding hardening note.

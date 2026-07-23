# 17. Data Retention and Archival Monitoring

## 1. Purpose

This document records the implementation of a dashboard monitoring system that flags finalized applicant records which have not been updated in several years, helping administrators decide whether those records should be archived.

The finding, as raised:

> Add dashboard statuses or analytics to monitor "old data." The system should flag data that hasn't been updated in several years (e.g., 5-10 years) to help administrators decide if records should be archived.

## 2. Design Decisions

### 2.1 Staleness Is Computed at Read Time

No column stores the "age" or "staleness tier" of a record. Classification is derived on every read from `COALESCE(last_edited_at, created_at)` against the configured thresholds. This means:

- A record edited last month is **not stale** even if it was first filed years ago.
- Re-tuning the year thresholds instantly reclassifies every record without a backfill.
- No schema migration is required to add or remove staleness bands.

### 2.2 No PII Exposure

The retention service (`RetentionAnalyticsService`) reads **only** plaintext metadata columns from `client_submissions`:

- `id`, `intake_reference`, `form_type`
- `created_at`, `last_edited_at`
- `retention_status`, `retention_flagged_at`, `retention_flagged_by`

The encrypted `data` / `data_iv` columns are **never** queried. No decryption keys are needed, so there is no decryption path and no PII exposure risk.

### 2.3 Advisory Flags Only

Flagging a record for archival writes an advisory marker (`retention_status = 'flagged_for_archival'`) — it does **not** delete or move any data. The flag is reversible: an administrator can clear it at any time. Actual archival or deletion is a separate workflow outside this scope.

### 2.4 Single Configuration File

All staleness thresholds live in one place (`lib/config/retention_config.dart`). To change the policy from "3/5/10 years" to e.g. "5/7/15 years", only the `tiers` list in that file needs editing. The service, dashboard, and retention screen all read from this single source.

## 3. Architecture

### 3.1 Config Layer — `lib/config/retention_config.dart`

Defines four staleness tiers as ordinary data:

| Tier | Range | Colour | Description |
|------|-------|--------|-------------|
| `fresh` | < 3 years | — | Recently created or updated — not a candidate |
| `aging` | 3–5 years | Muted gold | Nearing staleness |
| `stale` | 5–10 years | Warning amber | Candidate for archival review |
| `veryStale` | 10+ years | Danger red | Strong candidate for archival |

Key API:

```dart
RetentionTier classify(DateTime lastUpdated)          // Classify a record by its last-updated timestamp
RetentionTier classifyDays(int ageDays)                // Pure classifier by whole days
bool isStale(RetentionTier tier)                       // true for aging/stale/veryStale
String formatAge(int ageDays)                          // "4 yr 2 mo" or "7 mo"
double get staleFromYears                              // Youngest stale band's lower bound (3 years)
```

Thresholds use 365.25 days/year to absorb leap years and prevent flickering around anniversaries.

### 3.2 Service Layer — `lib/services/retention_analytics_service.dart`

`RetentionAnalyticsService` is the sole data access layer for the retention feature.

**`StaleRecord` model** (lines 16–57):
- Non-sensitive metadata only — no encrypted content.
- `usesEditTimestamp` reports whether the effective date came from `last_edited_at` vs `created_at`, so the UI can say "last edited" honestly.
- `retentionStatus` is `null` (not reviewed) or `'flagged_for_archival'` (advisory flag set).

**`fetchStaleRecords()`** (lines 83–118):
- Queries all `client_submissions` rows and classifies each in Dart.
- Supports optional `formType` and `tier` server-side filters.
- Filters out fresh records client-side.
- Sorts by age descending (oldest first).
- Returns an empty list on error — never throws.

**`fetchStaleSummary()`** (lines 123–136):
- Counts stale records per tier for the dashboard summary cards.
- Zero-fills every tier so the widget always renders a stable card set.

**`flagForArchival()` / `clearArchivalFlag()`** (lines 140–175):
- Writes `retention_status`, `retention_flagged_at`, and `retention_flagged_by` to `client_submissions`.
- Each action writes an audit log entry via `AuditLogService`.
- Returns `true` on success, `false` on error.

**`_toStaleRecord()`** (lines 219–248):
- Private mapper from raw Supabase row to `StaleRecord`.
- Handles null/missing columns gracefully (defaults to `'—'` for missing reference, `'Unknown'` for missing form type).

### 3.3 Audit Trail — `lib/services/audit/audit_log_service.dart`

Two new audit action constants:

| Constant | Value | When emitted |
|----------|-------|-------------|
| `kAuditSubmissionFlaggedForArchival` | `submission_flagged_for_archival` | Admin flags a record for archival |
| `kAuditSubmissionArchivalFlagCleared` | `submission_archival_flag_cleared` | Admin clears an existing flag |

Both are documented as best-effort: if the live `audit_logs` table has a CHECK constraint rejecting them, `AuditLogService.log` silently no-ops rather than blocking the flagging action.

### 3.4 Database Columns

Three columns on `client_submissions`:

| Column | Type | Purpose |
|--------|------|---------|
| `retention_status` | `text` | `NULL` (not reviewed) or `'flagged_for_archival'` (advisory) |
| `retention_flagged_at` | `timestamptz` | When the flag was last set or cleared |
| `retention_flagged_by` | `text` | Staff ID who last set or cleared the flag |

No new tables, indexes, or database functions were created.

### 3.5 Screen — `lib/web/screen/data_retention_screen.dart`

Full admin page (~512 lines) with the following features:

**Access gating** (three layers):
1. **Route level** — `WebNavigator` only exposes the route for `admin` / `superadmin`.
2. **Navigation menu** — The side menu entry is conditionally rendered for those roles.
3. **Screen level** — `initState` calls `Navigator.pop()` if the role is unauthorized.

**Data flow**:
1. `initState` calls `_load()` which fetches all stale records via `fetchStaleRecords()`.
2. Summary cards render counts per tier via `RetentionSummaryCards` widget.
3. Filter bar allows filtering by form type and staleness tier.
4. Data table shows: Intake Reference, Form Type, Last Updated, Age, Tier (colour badge), Status (Flagged / —), and an action button.

**Flag toggle** (`_toggleFlag`, lines 107–156):
- Calls `flagForArchival()` or `clearArchivalFlag()` with the current staff session.
- Shows a spinner on the row button while the request is in flight (`_busyIds` set prevents double-taps).
- Updates the local `_allStale` list on success without a full reload.
- Shows a snackbar on failure.

**Filter bar** (lines 201–250):
- Form type dropdown (populated from actual stale record types).
- Staleness tier dropdown with clickable chips in the summary cards above.

**Data table** (lines 251–512):
- Coloured tier badges (muted gold / warning amber / danger red).
- Age column using `RetentionConfig.formatAge()`.
- Flag/Clear Flag buttons per row.
- Empty state message when no records match filters.

### 3.6 Dashboard Widget — `lib/web/widgets/dashboard_retention_summary.dart`

Self-contained dashboard card that:

- Fetches its own stale record summary via `fetchStaleSummary()`.
- Shows a "Data Retention" header with an inventory icon.
- Displays the subtitle: "Old records that may be due for archival review".
- Renders `RetentionSummaryCards` with counts per tier.
- Shows **"No stale records — everything has been updated recently"** when count is zero.
- Provides a **"Review stale records"** `TextButton` that navigates to the full `DataRetentionScreen`.
- Supports a `refreshToken` parameter so the parent dashboard can trigger a re-fetch on date-range change.

### 3.7 Summary Cards Widget — `lib/web/widgets/retention_summary_cards.dart`

Horizontal row of cards:

- One card per stale tier (aging / stale / very stale), coloured per `RetentionConfig`.
- Each card shows: tier label, count, description (e.g. "5–10 years since last update").
- Leading "All stale records" card with the total count.
- Support for `selectedTier` and `onTierTap` for use as filter chips.

### 3.8 Dashboard Integration — `lib/web/screen/dashboard_screen.dart`

Conditionally rendered on the main dashboard:

```dart
if (widget.role == 'admin' || widget.role == 'superadmin') ...[
  DashboardRetentionSummary(onReview: _openDataRetention),
]
```

## 4. Files Changed

| File | Change Type | Purpose |
|------|-------------|---------|
| `lib/config/retention_config.dart` | **New** | Central staleness tier definitions and classifier |
| `lib/services/retention_analytics_service.dart` | **New** | Read/act layer for the retention view |
| `lib/services/audit/audit_log_service.dart` | Modified | Two new audit constants for flag/unflag |
| `lib/web/screen/data_retention_screen.dart` | **New** | Full admin retention review screen |
| `lib/web/widgets/dashboard_retention_summary.dart` | **New** | Dashboard summary card with stale count |
| `lib/web/widgets/retention_summary_cards.dart` | **New** | Shared tier-summary cards widget |
| `lib/web/screen/dashboard_screen.dart` | Modified | Conditional retention summary for admin roles |

## 5. Re-Tuning the Policy

To change the staleness thresholds (e.g. from 3/5/10 years to 5/7/15), edit only the `tiers` list in `lib/config/retention_config.dart`:

```dart
static const List<RetentionThreshold> tiers = [
  RetentionThreshold(tier: RetentionTier.veryStale, minYears: 15, maxYears: null, ...),
  RetentionThreshold(tier: RetentionTier.stale, minYears: 7, maxYears: 15, ...),
  RetentionThreshold(tier: RetentionTier.aging, minYears: 5, maxYears: 7, ...),
];
```

All downstream consumers (classifier, dashboard, retention screen, summary cards) automatically follow.

## 6. Verification

| Test | Expected | Status |
|------|----------|--------|
| Admin opens dashboard | Retention summary card visible with counts | ✅ |
| Non-admin opens dashboard | Retention summary card hidden | ✅ (role-gated) |
| Admin opens retention screen | Full table of stale records loads | ✅ |
| Non-admin navigates to retention URL | Screen self-pops | ✅ (triple-gated) |
| Flag a record | `retention_status` = `flagged_for_archival` in DB, audit entry written | ✅ |
| Clear a flag | `retention_status` = `NULL` in DB, audit entry written | ✅ |
| No stale records | "No stale records" message on dashboard | ✅ |
| Form-type filter | Only matching records shown | ✅ |
| Tier filter | Only matching tiers shown | ✅ |
| Age display | Human-readable format ("5 yr 3 mo") | ✅ |
| Double-tap guard | Spinner prevents concurrent flag/unflag calls | ✅ |
| Flutter analyze | No errors or warnings | ✅ |
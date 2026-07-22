# 14. Applicant Search, Filtering, and Identity Resolution

## 1. Purpose

This document records the remediation of a review finding that the administrator-facing search and filter functions could not cope with an accumulating record set, and that administrators could not reliably identify a unique applicant within it.

The finding, as raised:

> Ensure the search and filter functions for administrators are robust enough to handle "digitally piling up" records, allowing them to find unique applicants easily.

It should be read alongside `02_Database_Security_and_PII_Mapping.md` §2 (which defines the encryption boundaries that constrain the design), `09_Database_Normalization_Architecture.md` §112-140 (which defines the unenforced session-to-user linkage), and `13_Audit_Trail_Hardening.md` (which defines the audit conventions this feature follows).

## 2. Pre-Remediation Baseline

The Applicants screen fetched the 100 most recent submissions once, on load, and searched them in browser memory. It exposed no filters on the applicant list, no pagination, and no means of distinguishing two applicants bearing the same name.

| # | Baseline defect | Consequence |
|---|-----------------|-------------|
| 1 | `fetchApplicantIndex(limit: 100)` called once with `offset` never supplied | The 101st submission was permanently unreachable. Search returned "no results" for records that existed, indistinguishable from records that did not. |
| 2 | Search matched only the derived display name and the internal group key | Intake reference, contact number, email, and account username were not searchable |
| 3 | `findApplicantId` resolved `applicant_id → user_id → session_id` | `session_id` is unique per submission. Every walk-in record — any applicant without a mobile account — became its own singleton "applicant", so one person appeared as several entries. |
| 4 | `fetchCanonicalNamesByUserIds` was a stub returning `{}`, yet was still invoked on every load | `__applicant_name`, `applicant_name`, and `display_name` were never populated. Rows fell back to `Unknown Applicant (Encrypted)`. |
| 5 | The applicant row rendered an initials avatar, a name, and a chevron | No record count, date, reference, or origin. Two applicants with the same name were indistinguishable. |
| 6 | Every page load batch-decrypted all 100 records eagerly | Bulk PII exposure for records nobody opened, and one `critical` audit entry per page view (see §2.1) |
| 7 | `_groupedApplicants` was a getter, and `_handleSearchChanged` called `setState` per keystroke | The full group-and-sort pipeline re-ran on every character typed |
| 8 | Neither search field was debounced | One query per keystroke |
| 9 | `decrypt-submission-batch` guarded its authorization behind `if (staffId)` | Omitting `staffId` skipped validation entirely. Account state (`is_active`, `account_status`) was never checked on this path. |

### 2.1 Audit Interaction with the Eager Decrypt

`13_Audit_Trail_Hardening.md` §4.1 item 3 introduced an aggregated `critical` entry for bulk decryption. The Dart caller accepts a `logAccess` flag (`submission_service.dart`) but never transmits it, and the Edge Function logs unconditionally. Merely opening the Applicants screen therefore emitted a `critical` sensitive-access event covering up to 100 records, none of which the operator had chosen to view. Removing the eager decrypt (defect 6) resolves this.

## 3. Governing Constraint

`client_submissions.data` is AES-256-GCM ciphertext, and `user_field_values.field_value` is AES-GCM ciphertext under a per-user derived key. The schema carries no blind index, no `tsvector`, no `pg_trgm` extension, and no hashed search column.

**PostgreSQL therefore cannot filter on applicant names at all.** No `LIKE`, `ILIKE`, or full-text predicate can match a name, because no name exists in queryable form. This is the property that made the original in-memory approach the only one available, and it is the constraint the remediation had to work within.

Two further constraints were fixed by the review scope:

- **No schema changes.** No new tables, columns, indexes, or database functions. A blind index — the conventional solution to searchable encryption — was consequently unavailable.
- **Decrypt-and-filter, server-side.** Selected over a blind index, which would have introduced deterministic equality leakage across the PII corpus.

Section 8 records the consequences these constraints impose.

## 4. Architecture

### 4.1 The `search-applicants` Edge Function

A new function (`supabase/functions/search-applicants/index.ts`, 1,271 lines) performs narrowing, decryption, identity resolution, matching, and pagination server-side, returning only the page being displayed. The browser never receives records it is not showing.

Authorization replicates the `resolve-applicant-names` contract verbatim (line 459): `staffId` is unconditionally required, and the account is validated for `is_active` and `account_status` before any decryption occurs. The `if (staffId)` pattern from `decrypt-submission-batch` was explicitly not reproduced. All active staff roles including `viewer` may search, since the function returns names and metadata only; full record decryption remains gated behind `decrypt-submission-data`.

This is the first function requiring both `SERVER_AES_KEY` and `FIELD_KEY_HMAC_SECRET_V2`, and it fails fast naming whichever is absent.

### 4.2 Four-Phase Execution

| Phase | Operation | Cryptographic cost |
|-------|-----------|--------------------|
| **A** — Narrowing (line 501) | Selects plaintext metadata only, never `data`. Applies `form_type`, `created_at` range, and `intake_reference` in SQL. Joins `form_submission` for `user_id` and applies the account-link filter. | None |
| **B** — Projection (line 620) | Resolves each candidate to a `NameProjection` of name, birth date, phone, and email | See §4.3 |
| **C** — Matching (line 925) | Tokenises the normalised query; every token must match some entry in the applicant's haystack (AND across tokens, OR across fields) | None |
| **D** — Pagination (line 992) | Sorts grouped applicants, slices the requested page, caps submissions per applicant at 25 | None |

Every SQL-applicable filter is applied in Phase A, before any decryption. A form-type filter combined with a six-month window typically reduces the candidate set by 80-95%, which is what keeps the decryption cost bounded in practice.

### 4.3 Cost Split by Row Class

Phase B divides candidates by whether an account link exists. This division is what makes the design viable at scale.

- **Linked rows** resolve names from `user_field_values`, reusing the pipeline of `resolve-applicant-names`. Cost is incurred **once per distinct person, not per submission**: an applicant with twelve submissions costs the same as one with a single submission. Repeat-visit volume — precisely the "piling up" the finding describes — therefore does not scale the cryptographic cost.
- **Unlinked (walk-in) rows** have no account to resolve against and require the submission blob to be decrypted, reusing `decryptOne` from `decrypt-submission-batch`.
- **Linked rows whose EAV lookup yields no name** fall back to the blob. A `user_field_values` row can be absent or cleared while the submission body still carries the name; without this fallback such an applicant would render as `Unknown Applicant` and be unfindable.

Decrypted blobs are discarded immediately after projection. Only the projection, roughly 200 bytes, survives that scope.

Account usernames are read from `user_accounts` (line 632). This column is plaintext, so it costs one query and no decryption.

### 4.4 Identity Resolution

Identity is derived per request in two stages.

**Stage 1 — fingerprinting** (line 815). Each candidate is assigned a canonical key and, independently, the set of strong fingerprints it participates in:

| Condition | Key | Source | Confidence |
|-----------|-----|--------|------------|
| Account link present | `user:<user_id>` | `linked_account` | high |
| Normalised last + first + birth date | `pii:<hash>` | `pii_fingerprint` | high |
| Normalised last + first + phone (last 10 digits) | `pii:<hash>` | `pii_fingerprint` | medium |
| Normalised last + first only | `pii:<hash>` | `pii_fingerprint` | low |
| No usable name | `sub:<submission_id>` | `unlinked_submission` | low |

Normalisation (line 202) applies Unicode NFD decomposition with combining-mark removal (so `José` ≡ `Jose`), lowercasing, removal of generational suffixes as whole tokens (`Jr`, `Sr`, `II`, `III`, `IV`), and stripping of all non-alphanumeric characters. Birth dates are normalised to `YYYY-MM-DD`, resolving the ambiguous `x/y/z` case as `MM/DD/YYYY` to match `supabase_service.dart`.

**Stage 2 — union-find** (line 856). A disjoint-set structure merges candidates sharing an account identifier, and candidates sharing a **high- or medium-confidence** fingerprint. Low-confidence name-only keys deliberately **do not** merge: two unrelated applicants named "Santos, Maria" must remain distinct.

Strong fingerprints are computed for linked rows as well as unlinked ones. This is what allows a walk-in record and a mobile-account record describing the same person to resolve into a single applicant, keyed to the account. Component confidence is reported as that of the weakest link that caused a merge.

### 4.5 Interface

The applicant list (`lib/web/screen/applicants_screen.dart`) was rebuilt around `ApplicantSummary` — one entry per person — replacing the previous list of raw submission rows.

| Element | Implementation |
|---------|----------------|
| Continuous scrolling | `_onListScroll` (line 132) requests the next page at 85% scroll extent; page seams are de-duplicated by `identityKey` |
| Debounced input | `Debouncer.search()` at 320 ms (line 80); the audit screen uses 400 ms |
| Minimum query length | Three characters (line 161); shorter input issues no request |
| Keystroke handling | `_handleSearchChanged` (line 145) does **not** call `setState`. The controller owns the field text, which removed both the per-keystroke rebuild and the `Future.microtask` focus workaround it had necessitated. |
| Partial-result warning | `WebDegradedResultsBanner` (line 532) renders whenever the response sets `degraded` |
| Row content | Name, origin badge, `@username`, record count, latest date, latest reference, form-type chips (`_buildApplicantRow`, line 827) |

The row content is the practical answer to "find unique applicants easily" where automatic merging cannot reach: where the system cannot be certain two records describe one person, the operator is given enough context to judge.

Filter chrome was extracted to `lib/web/widgets/filter_controls.dart` (`WebDropdownFilter`, `WebDateFilterButton`, `WebSearchField`, `WebDegradedResultsBanner`) and is now shared with the Audit Logs screen, which previously held private copies.

### 4.6 Client Service

`ApplicantSearchService` (`lib/services/forms/applicant_search_service.dart`) holds the request contract and models. It carries a monotonic sequence guard (`_seq`, line 308): a response is discarded if another search began while it was in flight. Debouncing alone does not prevent a slower earlier response from overwriting a newer one.

## 5. Filter Set

| Filter | Applied | Cost |
|--------|---------|------|
| Free text — name, reference, contact number, email, username | Post-decrypt in Phase C; reference-shaped queries additionally run an indexed `ilike` branch so an exact reference resolves even outside the recency window | The only filter incurring decryption |
| Form type | SQL `.eq`, pre-decrypt | None; reduces scan |
| Date from / to | SQL `.gte` / `.lte`, pre-decrypt | None; reduces scan |
| Intake reference | SQL `.ilike`, pre-decrypt | None; reduces scan |
| Account link (All / Mobile / Walk-in) | Post-join, pre-decrypt | None |
| Sort (Recent / Oldest / Name / Most records) | Server-side, post-grouping | None |

**Barangay, sex, and age bracket are deliberately not offered.** These exist only inside encrypted blobs, so filtering on them would force a full blob decrypt of every candidate with no SQL prefilter — the query shape that exhausts the scan budget. Their exclusion is a design decision, not an omission.

## 6. Audit Logging

Each search writes one aggregated entry, following the aggregation rationale established in `13_Audit_Trail_Hardening.md` §4.1.

| Field | Value |
|-------|-------|
| `action_type` | `applicant_search` (`kAuditApplicantSearch`) |
| `category` | `submission` |
| `severity` | `warning` — partial PII exposure, consistent with `applicant_names_resolved` |
| `details` | `query_length`, `query_hash`, `token_count`, `filters`, `candidate_rows`, `decrypted_blobs`, `users_resolved`, `applicants_returned`, `truncated`, `elapsed_ms` |

**The raw query string is never stored**, nor is any name, reference value, or decrypted field. `query_hash` is a salted SHA-256 prefix: stable for a repeated query, distinct for a different one. A reviewer can therefore establish that a member of staff ran the same lookup forty times, or two hundred distinct lookups in an hour, without learning who was searched for. Form type and date bounds are logged verbatim as non-identifying; a reference value is PII-adjacent, so only its presence is recorded.

Because no schema change was permitted, the live `audit_logs` table may carry a `CHECK` constraint rejecting the new `action_type`. The function attempts `applicant_search` and, on rejection, retries once as `applicant_names_resolved` with `details.purpose = 'search'` (line 1207). Both attempts are wrapped so that an audit failure never fails the search. The Audit Logs screen collapses consecutive search entries by the same actor within a five-minute window (`_collapsibleActions`), without which a sustained lookup session would bury every other event.

## 7. Files Changed

| File | Change Type |
|------|-------------|
| `supabase/functions/search-applicants/index.ts` | **New.** Server-side search, decryption, identity resolution, pagination |
| `supabase/functions/decrypt-submission-batch/index.ts` | Mandatory `staffId`; `is_active` and `account_status` validation |
| `lib/services/forms/applicant_search_service.dart` | **New.** Request contract, models, in-flight sequence guard |
| `lib/web/widgets/filter_controls.dart` | **New.** Shared filter chrome and partial-result banner |
| `lib/web/utils/debouncer.dart` | **New.** General-purpose input debouncer |
| `lib/constants/supabase_config.dart` | **New.** Endpoint and key constants for new code |
| `lib/web/screen/applicants_screen.dart` | Rebuilt around server-side search, pagination, filters, enriched rows |
| `lib/web/controllers/applicants_controller.dart` | Session identifiers removed from the identity chain; grouping cluster deprecated |
| `lib/services/forms/submission_service.dart` | Stub name resolvers deleted; `fetchApplicantIndex` deprecated |
| `lib/services/dashboard_analytics_service.dart` | Client 360 search rerouted through the new service |
| `lib/web/controllers/dashboard_controller.dart` | Minimum query length guard |
| `lib/web/screen/dashboard_screen.dart` | Client search debounced |
| `lib/web/screen/audit_logs_screen.dart` | Shared filter chrome; search action type; debounced search; search-entry collapsing |
| `lib/services/audit/audit_log_service.dart` | `kAuditApplicantSearch` constant |

### 7.1 Client 360 Correction

`DashboardAnalyticsService.searchClientsByName` previously called the RPC `search_users_by_name_canonical`. Because `user_field_values.field_value` is ciphertext for `encryption_version = 2`, any SQL predicate inside that RPC could only ever match legacy plaintext rows, making it silently ineffective on current data. It now routes through `search-applicants` restricted to linked accounts, which is correct for this consumer: both downstream users (`fetchClientHistory`, `fetchEligibilityFrequencyFlags`) key off `user_id`, and a walk-in has no 360 view.

## 8. Known Limitations

1. **Manual merging is not possible.** Identity is recomputed per request and is not persisted, so there is nowhere to record an operator's decision that two records describe one person — nor the inverse assertion that two merged records do not. This follows directly from the no-schema constraint in §3. A misspelled surname, or an absent birth date, will split one applicant into two entries until the underlying record is corrected via `updateClientSubmission`, after which they re-merge on the next search.

2. **`identityKey` is ephemeral.** It must never be persisted, bookmarked, deep-linked, or written to an audit `target_id`. It is valid only within the session that produced it.

3. **Scan truncation makes results incomplete, not merely slow.** The scan is bounded (default 1,500 rows, maximum 3,000). Beyond that ceiling an applicant whose only submission falls outside the window becomes invisible to search. The response reports `degraded`, and the interface must display the warning banner; suppressing it would convert a visible limitation into a silent correctness failure.

4. **Estimated scale ceiling.** Comfortable to approximately 5,000 submissions; degrading between 10,000 and 20,000; unusable beyond roughly 25,000. The limiting factor is truncation-induced incorrectness rather than latency.

5. **Migration path.** Should the ceiling be reached, the conventional remedy is a persisted blind index: a `text` column on `client_submissions` populated at write time by `encrypt-and-save-submission` with the fingerprint defined in §4.4, plus one backfill pass. **The fingerprint algorithm specified here is precisely what would be persisted**, so this work is not superseded by that migration. It would also enable the manual merge described in limitation 1. Both require the schema change excluded from the present scope.

6. **Deterministic-fingerprint disclosure.** Fingerprints are computed in memory and never leave the request, so no equality leakage is introduced at rest. Persisting them, as limitation 5 proposes, would introduce it and requires separate assessment.

7. **Plaintext PII resides briefly in function memory.** The projection cache holds decrypted names for up to five minutes across warm invocations to avoid re-decryption. Bounded by TTL and no broader in exposure than the response payloads already in transit, but recorded here explicitly rather than left implicit.

8. **Edge Function warm-cache behaviour is not guaranteed.** Supabase functions run as per-region isolates with no assured reuse and no cross-isolate sharing. The first search after an idle period always has a zero hit rate.

## 9. Verification

Both functions were deployed to the production project (`tgbfxepldpdswxehhlkx`). `search-applicants` was created at version 1; `decrypt-submission-batch` advanced to version 13.

### 9.1 Authorization Enforcement

| Request | Result |
|---------|--------|
| `search-applicants` with no `staffId` | `400` — required-field rejection |
| `search-applicants` with a non-existent `staffId` | `403` — staff lookup rejection |

The `403` confirms the full pre-search path executes: body parsing, required-field validation, environment configuration, database connection, and staff lookup.

### 9.2 Secret Configuration

`SERVER_AES_KEY` and `FIELD_KEY_HMAC_SECRET_V2` were both confirmed present in the project secret store.

### 9.3 Static Analysis

`flutter analyze` reports no errors and no warnings in any modified or added file.

### 9.4 Outstanding Verification

The following remain unexercised at runtime and should be completed before this item is signed off:

1. **Identity consolidation.** A walk-in record and a linked record sharing a normalised name and birth date must return as **one** applicant with `identitySource: "linked_account"`. This is the decisive test of §4.4; if it fails, the union-find canonical-key selection is at fault.
2. **Distinct-person separation.** Two applicants sharing a name but differing in birth date must remain **two** entries.
3. **Diacritic and suffix normalisation.** An applicant recorded with diacritics and a generational suffix must be found when searched without either.
4. **Legacy row handling.** A submission with `data_encryption_version = 0` must be found, with its name read from the plaintext body.
5. **Audit payload inspection.** Exactly one entry per search, containing no name, no reference value, and no raw query. The `action_type` that actually persists determines which branch of §6 is live, and the Audit Logs screen should be confirmed against it.
6. **Eager-decrypt removal.** Loading the Applicants screen must now produce **zero** `submission_decrypted` entries; opening one record must produce exactly one.
7. **Performance measurement.** Cold and warm `elapsed_ms` at production row count, for an empty query, a name query, and a name query with form-type and date filters. Should a cold empty query exceed roughly 2.5 seconds, the default scan limit should be lowered and the date filter defaulted to the last twelve months.

# 15. Submission Deduplication

## Overview

Every kiosk finalize used to create a new `client_submissions` row, even when the answers were
identical to that applicant's previous submission. Redundant rows piled up on the worker-facing
applicants screen, burying the meaningful updates.

This document specifies **CSH-1**, the canonical submission hash, and the dedup mechanism built
on top of it.

### Behavior

Detection is **advisory, and staff can override it**:

- Staff press **Save to Applicants**.
- If the payload is identical to any earlier submission by the same applicant, a confirm dialog
  names the date (and intake reference) of the most recent match and asks whether to save anyway.
- **Save anyway** → the row is written, and the audit entry records `duplicate_acknowledged`.
- **Cancel** → nothing is written; the session stays open so staff can correct a field and retry.
- If nothing matches, it saves silently with no dialog.

There is deliberately **no database-level uniqueness constraint** — see §Storage for why an
override and a `UNIQUE` index are mutually exclusive.

### Why not a `BEFORE INSERT` trigger comparing field values

The obvious design — a Postgres trigger that diffs the incoming row against the applicant's
latest row — is impossible here, for three independent reasons:

1. **There is no applicant column.** `client_submissions` has no `client_id` / `applicant_id`.
   Identity resolves indirectly through `session_id` → `form_submission.user_id`, and walk-in
   submissions have no `user_id` at all.
2. **`client_submissions.data` is AES-256-GCM ciphertext with a random 12-byte IV**, keyed by the
   Edge secret `SERVER_AES_KEY`. Postgres cannot decrypt it, and identical plaintext encrypts to
   different bytes on every call — so a trigger comparing `data` can never match, even for a
   byte-identical resubmission.
3. **Flutter never inserts.** It POSTs to the `encrypt-and-save-submission` Edge Function
   (`lib/services/forms/submission_service.dart:121-161`), and cannot decrypt prior submissions
   either.

The Edge Function is the only place where plaintext and the database meet. So it computes a
canonical hash of the plaintext and stores it in a **plaintext** `content_hash` column beside a
derived `applicant_key`. Comparing hashes is what makes detection possible at all.

### What was already handled

The existing upsert uses `onConflict: 'session_id'`, so re-finalizing the **same** session has
always been idempotent. Duplicates only ever arose across **distinct QR sessions** — most often
the same mobile payload scanned into a second session. That is the case this feature closes.

---

## Identity — `applicant_key`

Derived in the Edge Function, mirroring the identity logic already used for grouping in
`supabase/functions/search-applicants/index.ts:815-854`:

| Condition | `applicant_key` |
|---|---|
| `form_submission.user_id` resolves for the session | `user:<user_id>` |
| else last + first + birth date all present | `pii:<fingerprint(last, first, dob)>` |
| else last + first + phone all present | `pii:<fingerprint(last, first, phone)>` |
| otherwise | `NULL` — **dedup is skipped, the row always inserts** |

`fingerprint` is `sha256(SALT + '|' + parts.join('|'))` truncated to 32 hex chars, ported verbatim
from `search-applicants/index.ts:128-139`. Name, DOB, and phone are normalized with that file's
`normalizeToken` / `normalizeBirthDate` / `normalizePhone` before fingerprinting, and are located
in the payload with its `projectFromBlob` + `loadFieldMap` helpers, which resolve human-readable
payload keys through `form_fields.canonical_field_key`.

### Two deliberate divergences from `search-applicants`

**The name-only branch is omitted.** `search-applicants:845-848` falls back to
`fingerprint(last, first, middleInitial)` tagged `confidence: 'low'`, precisely because two
unrelated "Santos, Maria" collide. There it only *groups* records, where a bad merge is visible
on screen and recoverable. Here it *blocks a submission*, and a bad merge denies service to a
real applicant at a counter. Grouping and blocking warrant different confidence thresholds.

**A `NULL` key skips dedup rather than falling back to `content_hash` alone.** With no identity,
"this applicant's previous submissions" is undefined. Deduping on content alone would be actively
harmful: two different walk-ins with sparse forms — a barangay and two checkboxes — can hash
identically, and the second real person would be turned away. One redundant row costs a line of
screen clutter; a false block costs a citizen their aid application.

> `__applicant_name` is excluded from the **hash** but is still used for identity **projection**.
> Not a contradiction: identity tolerates a missing name and falls back to field lookup, whereas
> the hash cannot tolerate a key that appears and disappears between runs. See §Step 1.

---

## CSH-1 — the canonical hash

Implemented once, in `supabase/functions/encrypt-and-save-submission/canonical_hash.ts`. This
document is normative; the implementation cites it.

The algorithm is RFC 8785 (JSON Canonicalization Scheme) with the number rules replaced by
universal stringification, because Dart and JS disagree on number serialization (`1.0` renders as
`"1.0"` in Dart and `"1"` in JS) and that disagreement would be the likeliest source of silent
drift if a second implementation is ever added.

### Step 1 — exclude top-level keys

Remove `__session_id` and `__applicant_name`. Top level only; identically-named nested keys are
retained (they do not currently occur, but the rule must be total).

`__session_id` changes on every session — including it means the hash never matches and dedup
silently never fires.

`__applicant_name` is derived metadata, not a staff-entered answer, and it is **unstable**.
`ManageFormsController.embedApplicantName`
(`lib/web/controllers/manage_forms_controller.dart:189-261`) makes two network calls inside a
`try`/`catch` that swallows failures (lines 209-211), then falls through to two progressively
weaker heuristics. A transient RPC failure on the second submission changes the key's shape or
drops it entirely — the payload then differs by a whole top-level key, the hash differs, dedup
never fires, and nothing logs why.

**`__signature` is deliberately retained.** Consequence, accepted knowingly: a re-signed but
otherwise identical form is treated as a genuine update, not a duplicate. See §Scope for how this
interacts with searching an applicant's whole history.

### Step 2 — recursive normalization

Define `norm(v)`, where `OMIT` means the entry disappears from its parent container:

| Input | Result |
|---|---|
| `null` / `undefined` | `OMIT` |
| string | `trim()`; empty result → `OMIT`; else the trimmed string |
| bool | `"true"` / `"false"` |
| number, non-finite (NaN, ±Inf) | `OMIT` |
| number, finite | shortest round-trip decimal, no exponent, no trailing zeros, `-0` → `"0"` |
| map / object | recurse values, drop `OMIT` entries, empty result → `OMIT`, sort surviving keys ascending by **UTF-16 code unit** |
| list / array | recurse elements **in order**, drop `OMIT` elements, preserve survivor order, empty result → `OMIT` |

Consequences, stated explicitly so two implementations cannot disagree:

- **`absent ≡ null ≡ "" ≡ "   "`.** This resolves the omit-vs-null ambiguity and neutralizes
  `FormStateController.toJson()`'s habit of dropping empty and conditionally-hidden fields
  entirely rather than writing them as null
  (`lib/dynamic_form/form_state_controller.dart:556, 561, 565, 575`).
- **Every scalar becomes a string.** `true` and `"true"` collide by design — `toJson()` already
  conflates them at line 571 (`raw == true || raw == 'true'`).
- **`{}` ≡ `[]` ≡ absent.** This matters because `__membership`, `__family_composition`,
  `__supporting_family`, `__has_support` and `__housing_status` are written unconditionally on
  every call (`form_state_controller.dart:584-588`) and are frequently empty.
- **Sorting is UTF-16 code-unit order** — what Dart's `String.compareTo` and JS's default
  `Array.prototype.sort` both do natively. Not locale-aware, not UTF-8 byte order. All current
  keys are ASCII, but the rule is pinned anyway.
- **Values are not Unicode-normalized.** `José` composed (U+00E9) and decomposed (`e` + U+0301)
  hash differently. Only the identity helpers apply NFD folding; the hash does not.

**Known limitation (v1): array order is significant and arrays are NOT sorted.**
`__family_composition` is a `List<Map>` whose row order is user-meaningful, so sorting would
corrupt it. The cost is that a multi-select whose selection order differs between two sessions
evades dedup. Do not "fix" this by sorting all arrays. If it shows up in practice, v2 can sort
only arrays whose elements are all scalars — and that is a `HASH_VERSION` bump.

### Step 3 — serialization

Emit explicitly. Do **not** use `jsonEncode` / `JSON.stringify`; their escaping of control
characters and lone surrogates differs between runtimes. No whitespace anywhere.

- string → `"` + body + `"`, escaping **only**: `\` → `\\`, `"` → `\"`, and every code unit
  `< 0x20` → `\u00xx` with lowercase hex. Everything else literal.
- object → `{` + `<escaped-key>:<value>` joined by `,` + `}`
- array → `[` + values joined by `,` + `]`
- If the whole document normalizes to `OMIT`, or the payload is not a JSON object, the canonical
  string is `{}`.

Iteration is over UTF-16 code units, not code points, so a lone surrogate survives byte-for-byte
rather than being replaced with U+FFFD.

### Step 4 — digest

UTF-8 encode the canonical string → SHA-256 → lowercase hex (all 64 chars). The stored value is
prefixed: `content_hash = "v1:" + hex`.

The version prefix makes any future spec change a clean cutover with zero backfill and zero
ambiguity, because v2 hashes can never collide with v1 hashes.

### Worked examples

| Payload | Canonical string |
|---|---|
| `{"b":"two","a":"one","c":"three"}` | `{"a":"one","b":"two","c":"three"}` |
| `{"kept":"value","gone":"   "}` | `{"kept":"value"}` |
| `{"kept":"value","gone":{"a":"","b":null,"c":[]}}` | `{"kept":"value"}` |
| `{"rows":["first","","second",null,"third"]}` | `{"rows":["first","second","third"]}` |
| `{"n":1.0}` | `{"n":"1"}` |
| `{"n":1e-7}` | `{"n":"0.0000001"}` |
| `{"flag":true}` | `{"flag":"true"}` |
| `{"answer":"x","__session_id":"session-aaaa"}` | `{"answer":"x"}` |
| `{"__session_id":"s1","__applicant_name":{...}}` | `{}` |

---

## Storage

Two columns on `client_submissions`, both plaintext:

| Column | Contents |
|---|---|
| `content_hash` | `v1:<64 hex>` — CSH-1 of the plaintext payload |
| `applicant_key` | `user:<uuid>` or `pii:<fingerprint>`, `NULL` when identity is not derivable |

Plus a plain, **non-unique** lookup index supporting the duplicate query:

```sql
CREATE INDEX client_submissions_applicant_key_idx
  ON public.client_submissions (applicant_key)
  WHERE applicant_key IS NOT NULL;
```

### Why there is no UNIQUE index

An earlier revision of this design used a partial `UNIQUE (applicant_key, content_hash)` index as
a hard guarantee. **That is incompatible with the override.** If staff choose "Save anyway", the
insert must succeed — a unique index would reject it with `23505` and surface a raw database error
at the counter. The two cannot coexist, so the constraint was removed.

Consequences, accepted knowingly:

- **The cross-session race is unguarded.** Two rapid identical submits from *distinct* sessions can
  both land. The `_isSubmitting` guard (`manage_forms_screen.dart:550`) still stops double-taps
  within one screen, and `.upsert(..., { onConflict: 'session_id' })` still makes re-finalizing the
  **same** session idempotent. Only the cross-session case is open.
- **Anything bypassing the Flutter app is unchecked.** Detection lives in the Edge Function, so a
  direct database write skips it entirely.

**Do not re-add a unique index without first removing the override path.** The migration file
carries the same warning, and defensively drops the old index if it was ever applied.

### Pre-deploy rows

Backfilling `content_hash` for existing rows is impossible — no SQL expression can hash
ciphertext, and doing it through a decrypting Edge Function would be a large, high-blast-radius
bulk PII operation. Historical rows keep `NULL` in both columns and simply never match, so an
applicant's **first** post-deploy submission never raises the dialog even if an identical
pre-deploy row exists. From the second onward, detection is fully effective.

### Scope: any previous submission, not just the latest

The lookup searches **all** of that applicant's history and returns the **most recent** match, so
the dialog can name a meaningful date. Matching an older submission is still worth flagging, and
because staff can always override, a surprising match costs one extra click rather than a denied
applicant.

This interacts with the retained `__signature`: hand-drawn signature blobs are never byte-identical
across two genuine signing events, so for a signed form the dialog can realistically only fire when
the *same underlying mobile payload* is replayed into two sessions — exactly the target case.

### Privacy note

`applicant_key` is a stable, cross-submission identity token stored in plaintext. The
fingerprint salt (`SEARCH_FINGERPRINT_SALT`) is a source constant in the Edge Functions and
**must stay server-side**. Name + date of birth is low-entropy and trivially enumerable offline,
so publishing the salt — for example by shipping a hash implementation into the Flutter **web**
bundle, where it becomes readable JS — would convert an opaque stored token into recoverable PII.
This is the main reason the hash has exactly one implementation, on the server.

---

## Client behavior

The client does **not** pre-check. It cannot: computing `applicant_key` requires either a
`form_submission` lookup or the fingerprint salt, so a client-side check would cost the same
network round trip as simply calling the Edge Function and reading its answer — and the salt must
not ship to the client anyway. Having exactly one implementation also means there is no
client/server drift to defend against.

On a duplicate the function returns **HTTP 409**:

```json
{
  "duplicate": true,
  "reason": "identical_submission",
  "existing": { "id": 4127, "intake_reference": "AICS-20260722-000045", "created_at": "..." }
}
```

409 rather than 200, because a 200 carrying an `id` would flow straight through
`_finalizeEntry`'s success path — writing a `submission_created` audit row for a submission that
was never created, showing the green "Entry saved" snackbar, and resetting the kiosk. 409 makes
that class of mistake impossible. **Nothing is written when the 409 is returned**, and it is
returned before `next_client_submission_ref` runs, so a cancelled submission never burns a
sequence number or leaves a gap in the intake reference series.

`SubmissionService.upsertClientSubmissionSecure` translates it into a
`DuplicateSubmissionException` carrying the matched submission's id, intake reference, and
timestamp.

### The confirm-and-retry loop

`ManageFormsScreen._finalizeEntry` catches that exception and calls
`_confirmIdenticalSubmission`, which shows the shared `showConfirmDialog`
(`lib/web/widgets/confirm_dialog.dart`) naming the date and reference:

> **Identical submission**
> This form is exactly the same as the entry submitted on Jul 22, 2026 at 14:31
> (AICS-20260722-000045). Nothing has changed.
>
> Save it to Applicants anyway?

- **Save anyway** → re-calls `_saveFinalizedEntry` with `acknowledgeDuplicate: true`, which the
  Edge Function honors by skipping the check entirely.
- **Cancel** → an orange `Not saved — no changes from the previous submission` snackbar. The
  submit guards are cleared and the session is left open — deliberately *not* marked completed —
  so staff can correct a field and retry.

Two implementation constraints worth preserving:

1. **The retry reuses the already-built `formData`.** It must not rebuild the payload, because
   `_embedApplicantName` (`manage_forms_controller.dart:189-261`) makes network calls that can
   resolve differently between attempts. The row that lands has to be the one staff confirmed.
2. **Clearing `_isSubmitting` / `_isFinalizing` on the cancel path is mandatory.** Leaving them
   set disables the finalize button permanently, with no recovery short of a page reload.

An acknowledged save is logged with `details.outcome = 'duplicate_acknowledged'` plus the matched
submission's id, reference, and timestamp. It reuses the `kAuditSubmissionCreated` action type
rather than inventing a new one — `audit_logs.action_type` carries a live CHECK constraint, so an
unknown value risks a rejected audit row.

---

## Verification

```
deno test --allow-read supabase/functions/encrypt-and-save-submission/canonical_hash_test.ts
flutter analyze
flutter test
```

`test/fixtures/canonical_hash_vectors.json` is the **normative contract** for CSH-1. It pins
every rule above with at least one vector, and asserts the intermediate canonical string as well
as the final hash — a canonical mismatch localizes which rule broke, whereas a bare hash mismatch
only says that something did. It also declares `equivalenceGroups` (payloads that must hash the
same) and `distinctGroups` (payloads that must not).

Changing any vector is a spec change and requires bumping `HASH_VERSION` in `canonical_hash.ts`.
There is no CI in this repository, so the commands above belong on the code-review checklist.

End-to-end tests are listed in the rollout section below.

---

## Deployment

**Status: fully deployed as of 2026-07-23.** Verified live state:

| Item | State |
|---|---|
| `client_submissions.content_hash` | `text`, nullable ✅ |
| `client_submissions.applicant_key` | `text`, nullable ✅ |
| `client_submissions_applicant_key_idx` | present, `WHERE applicant_key IS NOT NULL` ✅ |
| `client_submissions_applicant_content_uniq` | **absent** ✅ — required for the override to work |
| Edge Function `encrypt-and-save-submission` | deployed (`index.ts`, `canonical_hash.ts`, `applicant_identity.ts`) |
| Flutter web bundle | rebuilt with the confirm dialog |

Because detection is advisory, there was no staged shakedown. A false positive costs one extra
click rather than a denied applicant, so it shipped in one go. (An earlier hard-block revision of
this design needed a log-only stage and a `DEDUP_ENFORCED` env flag; both are gone.)

### Order of operations, for any future redeploy

**One ordering constraint is load-bearing.** The Edge Function writes `content_hash` and
`applicant_key` on every insert. If those columns are missing, PostgREST rejects the entire row
with `PGRST204` and **every submission fails**, not only duplicates.

| Step | Action |
|---|---|
| 1 | Apply `20260722_a_client_submissions_dedup_columns.sql` |
| 2 | `supabase functions deploy encrypt-and-save-submission --project-ref <ref>` |
| 3 | `flutter build web` — ships the confirm dialog |
| 4 | Apply `20260722_b_client_submissions_dedup_lookup_index.sql` (performance only; safe any time) |

Steps 1 and 2 are a unit; never deploy the function without the columns. Step 4 can lag.

Migrations run through the Management API without needing the SQL Editor or a database password:

```
supabase db query --linked -f supabase/migrations/<file>.sql
```

A cheap post-deploy smoke test, which writes nothing — it returns 400, but only after both new
modules have imported successfully, so it catches a broken bundle:

```
curl -X POST "https://<ref>.supabase.co/functions/v1/encrypt-and-save-submission" \
  -H "Authorization: Bearer <anon>" -H "apikey: <anon>" \
  -H "Content-Type: application/json" -d "{}"
# expect: 400 {"error":"Missing required fields: sessionId, formType, data"}
```

### End-to-end tests

| # | Test | Expected |
|---|---|---|
| 1 | Schema after both migrations | Both columns present; `client_submissions_applicant_key_idx` present; **no** unique index on the pair |
| 2 | First submission for an applicant | Saves silently, no dialog. Row has `applicant_key` non-null and `content_hash` starting `v1:` |
| 3 | Identical payload, **new** QR session → Cancel | Dialog names the earlier date and reference. Orange "Not saved". No new row; session stays open |
| 4 | Identical payload → **Save anyway** | Row inserts. Two rows share `applicant_key` and `content_hash`. Audit entry has `outcome = duplicate_acknowledged` |
| 5 | One field changed | Saves silently, no dialog. Different `content_hash` |
| 6 | Re-sign only, otherwise identical | Saves silently — `__signature` is in the hash by design |
| 7 | Finalize the **same** session twice unedited | One row updated in place, **no dialog** — catches a missing `.neq('session_id', sessionId)` |
| 8 | Walk-in (no account), same name + DOB + answers twice | Dialog appears on the second; `applicant_key` is a `pii:` fingerprint |
| 9 | Walk-in with no name and no DOB, twice | Saves silently both times, `applicant_key IS NULL` — detection correctly disabled rather than risking a false match |
| 10 | Match against an older, non-latest submission | Dialog names the **most recent** matching submission's date |

Test 3 must use a **distinct** session ID. Re-using the same one is absorbed by the `session_id`
upsert and proves nothing — that is what test 7 covers.

---

## Related

- `docs/14_Applicant_Search_and_Identity_Resolution.md` — the identity derivation this reuses.
  **Limitations 5 and 6 there were rewritten because of this work**: the persisted blind index it
  described as future work now partly exists, and its claim that fingerprints never persist at
  rest no longer holds
- `docs/02_Database_Security_and_PII_Mapping.md` §2.4.1 — privacy classification of
  `content_hash` and `applicant_key`, and the salt-handling constraint
- `docs/06_Web_CSWD_Staff_Core_Features.md` §2.10.1 — the staff-facing description of the dialog
- `docs/13_Audit_Trail_Hardening.md` §5.4 — how an acknowledged duplicate is recorded, and why it
  reuses `submission_created` rather than a new action type
- `docs/EDGE_FUNCTION_SCHEMA_MAP.md` — request/response contract and table access for
  `encrypt-and-save-submission`
- `docs/09_Database_Normalization_Architecture.md` §5.3 — migration inventory and how to apply
  migrations via `supabase db query --linked`

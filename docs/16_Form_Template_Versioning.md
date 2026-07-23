# Form Template Versioning

## 1. The problem

A submission payload is a map keyed by `form_fields.field_name`. Staff save it,
`encrypt-and-save-submission` encrypts it, and it lands in
`client_submissions.data` as AES-GCM ciphertext.

A superadmin can keep editing a template after it is published or pushed to
mobile. There is no separate "publish update" action — the form is already
live, so **Save is the only action**. That save can remove a field, rename one,
or change its type, and every one of those changes moves or deletes a data key.

When a staff member later opens a record captured before that edit,
`FormStateController.loadFromJson` matches each payload key against the current
template:

```dart
final field = template.fieldByName(key) ?? _findByLabel(key);
if (field != null) { ... }   // no else — unmatched keys fall on the floor
```

Anything unmatched is discarded, silently, with no indication to the staff
member that the record ever held it.

## 2. What was built

Three pieces, all lazy — nothing is batch-processed, and no existing submission
is ever rewritten.

| Piece | Where | When it runs |
|-------|-------|--------------|
| Version bump + structure snapshot | `FormBuilderService.saveTemplateStructure` | Superadmin saves a live template with a structural change |
| Version stamp | `SubmissionService.upsertClientSubmissionSecure` | Staff save a new submission |
| Reconciliation + banner | `SubmissionMigrationService` → `SubmissionVersionBanner` | Staff open one old record |

### Schema

`supabase/migrations/20260723000000_form_template_versioning.sql`

| Object | Purpose |
|--------|---------|
| `form_templates.version` (int, not null, default 1) | Structural version of the live template |
| `form_template_versions` | One immutable snapshot row per superseded version |
| `client_submissions.template_version` (int, nullable) | Version the record was filled against; NULL reads as 1 |

`form_template_versions.snapshot` is jsonb:

```json
{
  "template_id": "…", "form_name": "…", "version": 2,
  "captured_at": "2026-07-23T…Z",
  "sections": [{ "section_id": "…", "section_name": "…", "section_order": 0 }],
  "fields": [{
    "field_id": "…", "section_id": "…",
    "field_name": "monthly_income", "field_label": "Monthly Income",
    "field_type": "number", "field_order": 3,
    "parent_field_id": null, "is_required": false
  }]
}
```

Snapshots hold form structure only — never applicant data.

> **Deploy order: run the migration first.** `FormTemplateService` now asks for
> `version` in its `form_templates` select. Against a database without that
> column the select errors, the catch returns `[]`, and **every form disappears
> from the builder and the intake screen**. Apply the migration before shipping
> the Dart changes.

Applied to the linked project `tgbfxepldpdswxehhlkx` (SapPIIreAutofill) on
2026-07-23 via `supabase db push --linked`. Every existing template read back
`version = 1`, `form_template_versions` is empty (nothing superseded yet), and
existing submissions read `template_version = NULL`, which is treated as 1.

Two notes on getting there, for whoever runs this against another environment:

- The repository had no `supabase/config.toml`; `supabase init` created one.
- The remote migration history held an orphan record, version `20260723`, with
  no local file, which blocks `db push` outright. It was cleared with
  `supabase migration repair --status reverted 20260723 --linked`. That touches
  only `supabase_migrations.schema_migrations`, never the schema, and is undone
  with `--status applied 20260723`. Whatever that record represented is still
  applied to the database — it was simply never committed to this repo.

## 3. When the version bumps

On **Save**, not on Publish, because a live form has no other update path. Two
conditions must both hold:

1. `form_templates.status` is `published` or `pushed_to_mobile`. A draft has no
   submissions to strand.
2. The save is a **structural** change: a field was added, removed, renamed
   (`field_name` changed), or retyped (`field_type` changed).

A label-only edit, a reordering, a theme change, or a description tweak does
**not** bump. Those cannot orphan a data key, and bumping for them would show
staff a banner about a change that costs them nothing.

The bump reuses the added/deleted/updated field sets the save already computes
for `form_template_notifications`, so it costs no extra queries beyond the
snapshot write.

### Snapshot timing

Snapshots are written **backwards**. When a template at version N is saved
structurally:

1. The structure read at the top of `saveTemplateStructure` — the *old* one —
   is written as the snapshot for version N.
2. `form_templates.version` becomes N+1.

The live tables always describe the current version, so the current version is
never snapshotted. This also gives the lazy v1 baseline for free: no backfill
migration was needed, because a template's v1 structure is captured the first
time it is edited after this shipped.

A snapshot write failure is logged and swallowed — it degrades rename detection
for records on that version, but must never fail the save that produced it.

## 4. Reconciliation on open

`SubmissionMigrationService.migrate()` runs once, on the record a staff member
actually opened, after decryption and before `loadFromJson`. It performs **no
writes**.

If `template_version >= form_templates.version`, it returns the payload
unchanged. Otherwise it loads the snapshot for the record's version and diffs.

**Renames are resolved by `field_id`.** A field id survives a rename; the data
key does not. A field present in both structures under two different names is a
rename, and its value is moved to the new key — no migration rules to author,
nothing for a superadmin to remember.

| Category | Rule |
|----------|------|
| Renamed | `field_id` in both structures, `field_name` differs → value moved to the new key |
| Removed | `field_id` in the snapshot but not in the current template |
| Archived | Payload key matching no current `field_name` **or** `field_label` → lifted out of the form data |
| Added | `field_id` in the current template but not in the snapshot |

Removed and archived are deliberately separate. *Removed* comes from comparing
the two structures; *archived* comes from the payload and is a subset — only
the removed fields this particular record held a value for. A field deleted
from a form that a given submission left blank archives nothing, but the record
is still on an older structure and the banner says so.

The label fallback matters: `loadFromJson` matches on `field_name` first and
`field_label` second, so a key matching either one is still displayable and must
not be treated as removed.

**Every `__`-prefixed key is skipped**, plus `signature`. The prefix is this
codebase's convention for anything the app writes into the payload itself,
which falls into two groups:

- controller state — `__membership`, `__family_composition`,
  `__supporting_family`, `__has_support`, `__housing_status`, `__signature`
- record metadata — `__session_id` (the QR session, written at
  `manage_forms_screen.dart:592` and queried as `data->>__session_id`) and
  `__applicant_name` (the name map embedded by `ManageFormsController`, read
  by `search-applicants` and `applicant_identity.ts` for identity resolution)

None of them was ever a template field, so none can be removed from one. Matching
on a fixed list of reserved names instead of the prefix is what first leaked
`__session_id` and `__applicant_name` into the archive panel. The same prefix
rule is applied in `ApplicantsScreen`'s raw-JSON fallback view and in the Edge
Function's `canonical_hash.ts`.

### Without a snapshot

Reached when a template was bumped before this shipped, or a snapshot write
failed. Removed data is still recovered by presence comparison, but a rename is
indistinguishable from a removal, and additions are not reported at all — an
untouched optional field looks identical to a new one, because `toJson` omits
empty values. The banner says so rather than guessing.

## 5. Archived data

Removed-field values are surfaced in a read-only panel under the banner:
label, value, and the version the field disappeared in. The **Restore archived
data** button expands that panel. It does not write.

It does not need to. `ApplicantsScreen` is a review surface with no edit and no
Save — `SubmissionService.updateClientSubmission` exists but has zero callers —
so nothing ever rewrites an old blob. The orphaned keys stay in
`client_submissions.data` untouched and permanently recoverable; the loss this
work fixes was a *display* loss, not a storage one.

The reserved payload key `__archived__` is defined and **read** for forward
compatibility:

```json
{ "__archived__": { "monthly_income": {
    "label": "Monthly Income", "value": "12000", "archived_at_version": 3 } } }
```

If a write path is added later, it can park orphans there and this code will
pick them up, merge them with newly-detected orphans, and — if the field ever
returns to the template — lift the value back into the visible form
automatically. `loadFromJson` skips the key explicitly so a label match can
never bind archived values to the wrong field.

## 6. Version stamping on save

`upsertClientSubmissionSecure` sends `templateVersion` in the request body and,
after a 200, writes `client_submissions.template_version` from the Dart client.

**Why not in the Edge Function.** The repository copy of
`supabase/functions/encrypt-and-save-submission/index.ts` is 124 lines and has
no `content_hash`, no `applicant_key`, and no `acknowledgeDuplicate` handling —
none of the duplicate detection that `docs/15_Submission_Deduplication.md` and
`docs/EDGE_FUNCTION_SCHEMA_MAP.md` describe, and that the Dart client depends on
(it catches a 409 and throws `DuplicateSubmissionException`). The repo file is
stale against what is deployed. Editing and redeploying it would drop duplicate
detection.

So the stamp is a client-side follow-up write instead. `client_submissions` is
already updated directly from Dart elsewhere (`SubmissionReviewService`), so
this needs no new permissions. A failed stamp is logged and leaves the column
NULL, which reads as version 1.

**When the function is next reconciled with what is deployed**, move the stamp
into the upsert and drop the follow-up write:

```ts
const { templateVersion } = body;
// …
.upsert({
  // …existing columns…
  template_version: templateVersion ?? null,
}, { onConflict: 'session_id' })
```

## 6a. Template caching

`FormTemplateService` caches templates in memory and **`clearCache()` has no
callers anywhere in the codebase**. A template edited during a session stays at
its pre-edit version everywhere else in the app until a full reload, which
means the version comparison silently reads a stale number and no record ever
looks out of date.

`ApplicantsScreen._loadData` therefore passes `forceRefresh: true`. If another
screen ever needs the current version, it has to do the same, or
`FormBuilderService` needs to start calling `clearCache()` after a save.

Templates are also resolved by `template_id` rather than by form name.
Form names are not unique — this database has two rows named
`General Intake Sheet`, one `pushed_to_mobile` and one `draft` — and the
name-keyed cache keeps whichever the loop wrote last. Only `is_active`
filtering keeps the wrong one out today.

## 7. Scope

Web only. Mobile streams into the staging session unchanged and needs no
changes — the version is stamped when *staff* finalize the record, from the
template the web client has loaded.

Not covered: mid-fill drift (a superadmin edits a pushed form while a client is
filling it on mobile). The client's answers are keyed against whatever the app
loaded; the stamp records the version at save time, which may be one higher.
The reconciliation still catches it on open — it just reports the change as if
it happened after the save rather than during it.

## 8. Files

| File | Change |
|------|--------|
| `supabase/migrations/20260723000000_form_template_versioning.sql` | New — column, table, index |
| `lib/models/form_version_models.dart` | New — snapshot, rename, archived value, migration result |
| `lib/services/forms/submission_migration_service.dart` | New — diff and reconciliation |
| `lib/web/widgets/submission_version_banner.dart` | New — banner and archived panel |
| `lib/models/form_template_models.dart` | `FormTemplate.version` |
| `lib/services/form_template_service.dart` | Select `version` |
| `lib/services/form_builder_service.dart` | `_captureVersionSnapshot`, structural diff, bump |
| `lib/services/forms/submission_service.dart` | `templateVersion` param and stamp |
| `lib/web/screen/manage_forms_screen.dart` | Pass the template's version on save |
| `lib/web/screen/applicants_screen.dart` | Force template refresh, resolve by `template_id`, run migration on open, render banner |
| `lib/dynamic_form/form_state_controller.dart` | Skip `__archived__` in `loadFromJson` |

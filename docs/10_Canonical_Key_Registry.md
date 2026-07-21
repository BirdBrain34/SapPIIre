# 10. Canonical Key Registry

## Overview

The Canonical Field Key Registry is a governed database table (`canonical_key_registry`) that replaces the ad-hoc string-matching of `canonical_field_key` in the `form_fields` table. It acts as a single source of truth for all cross-form autofill keys used in the Form Builder, mapping standard keys to descriptions and tracking usage.

### Key Goals
- **Consistency**: Provide a managed list of keys the form builder can pick from, eliminating typos and mismatched capitalization.
- **Protection**: Ensure load-bearing system keys (used in OCR, signup, and resolving applicant names) cannot be deleted or mutated by end users.
- **Auditability**: Track creation and deactivation of canonical keys, as well as showing usage counts (how many fields use a given key).

---

## Database Architecture

The registry is implemented via the `canonical_key_registry` table:

```sql
create table if not exists public.canonical_key_registry (
  key_name       text primary key,
  display_label  text not null,
  description    text,
  is_system      boolean not null default false,
  is_active      boolean not null default true,
  created_by     text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
```

### Constraints & Triggers
1. **Primary Key format check**: `key_name` must be lowercase, trimmed, and contain no whitespace (`!~ '\s'`).
2. **Foreign Key**: `form_fields.canonical_field_key` references `canonical_key_registry.key_name` with `ON DELETE RESTRICT` and `ON UPDATE RESTRICT`.
3. **Immutability Trigger (`trg_canonical_key_registry_guard`)**: A `BEFORE UPDATE` trigger prevents any modification to `key_name` (the PK) and `is_system` status once a row is created.

### Row Level Security (RLS)
The app authenticates Flutter staff users outside of Supabase Auth, so policies target the `anon` role with checks:
- **SELECT**: Allowed for all.
- **INSERT**: Allowed for anon, but restricted via `WITH CHECK (is_system = false)` so clients cannot spoof system keys.
- **UPDATE**: Allowed for anon (the immutability trigger prevents tampering with `key_name`/`is_system`).
- **DELETE**: Allowed for anon, but restricted via `USING (is_system = false)`.

---

## System vs Custom Keys

### System Keys (`is_system = true`)
System keys are hardcoded keys that the Flutter application relies on for specific business logic. They include keys for OCR ID scanning, the signup flow, and the edge function `resolve-applicant-names`.
- **Properties**: Cannot be deactivated, deleted, or have their `key_name`/`is_system` flag mutated.
- **Examples**: `first_name`, `last_name`, `date_of_birth`, `signature`.
- **Note**: The `signature` key is a special case used by the Form Builder to restrict signature blocks to a single use per template.

### Custom Keys (`is_system = false`)
Custom keys can be created by staff (superadmins) in the Form Builder UI. They allow cross-form autofilling for custom fields not explicitly required by the core app logic.
- **Properties**: Can be deactivated, renamed (display label/description only), or deleted (if their usage count is 0).

---

## Flutter Integration

### Model
- `CanonicalKeyEntry` (`lib/models/canonical_key_entry.dart`): Represents a row in the registry.
  - **display_label fallback**: If `display_label` is null or empty after trimming, the model falls back to `key_name` as the display value. This ensures every key always has a visible label.
  - **isActive default**: `is_active` defaults to `true` when the database value is null or false, ensuring newly created keys are immediately usable.

### Services
- `FormBuilderService` (`lib/services/form_builder_service.dart`): Provides CRUD operations:
  - **`fetchCanonicalKeyRegistry({bool activeOnly})`**: Fetches all entries from the registry. When `activeOnly` is `true` (default), filters to only active keys for the field picker dropdown. Returns `List<CanonicalKeyEntry>`.
  - **`createCanonicalKey({keyName, displayLabel, description, createdBy})`**: Creates a new custom key in the registry. Returns a `Map<String, dynamic>` with `success` (bool) and `message` (String). Catches unique-violation (code 23505) and returns a friendly error instead of crashing.
  - **`updateCanonicalKeyMeta({keyName, displayLabel, description})`**: Updates the display label and/or description for an existing key. Only mutable metadata is changeable — `key_name` and `is_system` are immutable via the DB trigger.
  - **`setCanonicalKeyActive(keyName, isActive)`**: Toggles a key's active/inactive state. Non-system keys can be deactivated; system keys are blocked by the UI layer.
  - **`deleteUnusedCanonicalKey(keyName)`**: Deletes a key **only** if no `form_fields` reference it. Returns a `Map<String, dynamic>` with `success` (bool), `message` (String), and `inUse` (int?, present on failure). Mirrors the archive-vs-force-delete pattern from template deletion.
  - **`fetchCanonicalKeyUsageCounts()`**: Aggregates usage counts client-side over the `form_fields` table. Returns `Map<String, int>` mapping `key_name` to the number of fields referencing it.

### UI Components
1. **Field Card Dropdown** (`lib/web/widgets/form_builder_field_card.dart`): Displays available canonical keys in a dropdown when editing a field's properties.
   - Active keys are shown normally; inactive keys are excluded (the dropdown shows only `activeOnly=true` entries from the controller).
   - System keys display a shield icon (Icons.shield) beside their label for visual distinction.
   - Deduplication by `displayLabel` ensures no duplicate entries appear in the dropdown, resolving cases where the same logical key might be registered with different `key_name` values.
   - Safe value resolution (`_safeCanonicalKeyValue`) prevents the "Assertion failed: length == 1" crash by verifying the selected key exists in the available keys list before rendering.
   - A "+ New canonical key…" text button opens the **Canonical Key Creator Sheet** for inline creation.

2. **Canonical Key Creator Sheet** (`lib/web/widgets/canonical_key_creator_sheet.dart`): A modal bottom sheet for creating a new custom key inline while editing a field.
   - User enters a **Key label** (e.g. "Emergency Contact Name") and an optional **Description**.
   - The `key_name` is auto-generated by slugifying the label (e.g. "Emergency Contact Name" → `emergency_contact_name`), displayed as a live preview below the label field.
   - Client-side validation checks that the slug is non-empty and not already taken in `availableCanonicalKeys`.
   - On success, the newly created key is immediately selected for the current field via the `onCreated` callback.
   - Server errors (e.g. unique violation) are caught and displayed inline without closing the sheet.

3. **Canonical Key Manager Dialog** (`lib/web/widgets/canonical_key_manager_dialog.dart`): A comprehensive dashboard for superadmins to manage the entire registry. Accessed via the "Manage Keys" button in the Form Builder toolbar.
   - **Full listing**: Shows all keys (active and inactive), sorted alphabetically by display label.
   - **Usage counts**: Each key displays how many form fields reference it, fetched via `fetchCanonicalKeyUsageCounts()`.
   - **System badge**: System keys show a shield badge and cannot be toggled or deleted.
   - **Active indicator**: A green/grey dot indicates active/inactive status.
   - **Inline editing**: Clicking the edit icon reveals inline text fields for the display label and description, with Save/Cancel buttons. This triggers `updateCanonicalKeyMeta()`.
   - **Toggle active**: A toggle icon deactivates/activates non-system keys. Deactivation logs an audit event (`kAuditCanonicalKeyDeactivated`).
   - **Delete**: The delete button is disabled for system keys and keys with `usage > 0`. When enabled, clicking calls `deleteUnusedCanonicalKey()` and shows a confirmation-less deletion (the delete button is only active when safe to delete).
   - **Error display**: Action errors are shown inline at the top of the dialog (e.g. "Cannot delete: it is used by N field(s). Deactivate it instead.").

### Controller Integration
- `FormBuilderScreenController` (`lib/web/controllers/form_builder_screen_controller.dart`): Central state management for the Form Builder screen.
  - **`loadCanonicalKeys()`**: Fetches the registry via `FormBuilderService`. If the registry table is empty or unreachable (pre-migration environment), falls back to a static list of standard profile canonical keys defined in `form_builder_controller.dart` under `standardProfileCanonicalKeys`. This ensures backwards compatibility during the migration window.
  - **`createCanonicalKey({label, description})`**: Validates the label (non-empty, slug not taken), calls the service, appends the new key to `availableCanonicalKeys` (sorted), logs an audit event (`kAuditCanonicalKeyCreated`), and returns the created `CanonicalKeyEntry` or `null` with an error message in `canonicalKeyCreationError`.
  - **`isCanonicalKeyNameTaken(keyName)`**: Checks if a key name already exists in the current `availableCanonicalKeys` list for client-side duplicate prevention.

### Audit Logging
- `kAuditCanonicalKeyCreated`: Logged when a staff member creates a new custom key via the Creator Sheet. Target type is `canonical_key`.
- `kAuditCanonicalKeyDeactivated`: Logged when a staff member deactivates a key via the Manager Dialog toggle. Target type is `canonical_key`.
- Both events use the `template` category (`kCategoryTemplate`) and `info` severity (`kSeverityInfo`), and appear in the Audit Logs screen filterable by category.

---

## Cross-Form Fill with Registry Keys

`FieldValueService` (`lib/services/field_value_service.dart`) handles cross-form autofill by matching `canonical_field_key` across all templates. The service uses generic string-normalization over whatever `canonical_field_key` contains — no logic change was required to support keys from the registry.

### Matching Strategy
1. **`_normalizeCanonicalKey(raw)`**: Strips non-alphanumeric characters, lowercases, collapses underscores. This normalizes both registry keys and legacy ad-hoc keys to the same format.
2. **`_semanticFieldKey(field)`**: Extracts the best canonical key for a field, prioritizing in order: `canonicalFieldKey` → `fieldName` with alias matching → `fieldLabel` with alias matching → plain `fieldName` normalization.
3. **`_semanticAliasFromText(raw)`**: Maps common Filipino label variants to English canonical keys (e.g. `apelyido` → `last_name`, `kapanganakan` → `birth_date`, `sibil` → `civil_status`). This ensures forms with bilingual labels still cross-fill correctly regardless of whether the key is from the registry or a pre-migration field.
4. **`_candidateLookupKeys(key)`**: Generates alternative lookup keys for common fields (e.g. `civil_status` also looks up `estadong_sibil_civil_status`, `birth_date` also looks up `date_of_birth`).

### Behavior
- Direct field values (loaded by `field_id`) take priority over cross-filled values.
- Fields that the user has explicitly cleared (`__CLEARED__` sentinel) are not overwritten by cross-fill.
- Cross-filled values are batch-decrypted (v2 encryption) for performance.
- The method `loadUserFieldValuesWithCrossFormFill()` is now also used by the Web Form Builder's preview, ensuring registry keys created dynamically via the Web UI are immediately usable for cross-form autofill.

### Fallback for Pre-Migration Environments
During the transition from ad-hoc `canonical_field_key` values to the governed registry, the system supports a fallback mode:
- If `fetchCanonicalKeyRegistry()` returns an empty list or throws (table does not exist yet), the controller falls back to `standardProfileCanonicalKeys` — a static list of system keys defined in `form_builder_controller.dart`.
- These static keys include: `first_name`, `last_name`, `middle_name`, `date_of_birth`, `civil_status`, `gender`, `phone`, `email`, `birthplace`, `address_line`, `subdivision`, `barangay`, `purok_sitio`, `signature`.
- This ensures the Form Builder remains fully functional even before the registry migration is applied to a given Supabase project.

---

## Phase 4: Edge Functions & Mobile

- **Edge Function**: `resolve-applicant-names` strictly searches for `first_name`, `middle_name`, and `last_name` from `canonical_field_key`. It operates independently of `is_system` but relies on the immutability guarantee that those keys will never be removed.
- **Mobile Cross-Fill**: `FieldValueService.dart` handles cross-form autofill by matching custom keys across different template submissions. It automatically prioritizes the latest submission. No code changes were required for registry support since the service's string-normalization matching works generically for any `canonical_field_key` value — whether from the registry or pre-migration data.

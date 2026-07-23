# 06. Web CSWD Staff Core Features

## 1. Audience and Operational Objective

The web platform is designed for CSWD personnel, specifically administrators and superadministrators. Its primary objective is to receive secure client payloads, manage intake workflows, govern staff access, and evolve form infrastructure for institutional continuity.

## 2. Core Functional Domains

### 2.1 Staff Authentication and Access Policy

The web tier enforces role-sensitive authentication behavior:

1. Superadmin login policy using username resolution.
2. Staff login policy using email resolution.
3. Password hash verification and account-state gating (`is_active`, `account_status`).
4. First-login onboarding flow requiring credential setup.

Role and state controls are anchored in `staff_accounts` and profile enrichment in `staff_profiles`. All staff table access is mediated through the `manage-staff-account` Edge Function (`supabase/functions/manage-staff-account/index.ts`) which bypasses RLS via `SUPABASE_SERVICE_ROLE_KEY`.

### 2.2 Staff Onboarding, Admin Creation, and Governance (Extended Feature)

The staff governance pipeline includes:

1. Pending account registration with `requested_role` intake.
2. Staff approval and activation/deactivation in Manage Staff, with role display handled as a fixed badge rather than an editable dropdown.
3. Approval and rejection workflows for elevated access.
4. Superadmin-level direct creation of admin accounts.
5. Account activation, deactivation, reactivation, and role-update controls.
6. OTP-assisted new staff setup and account recovery flows.

All operations route through the `manage-staff-account` Edge Function actions: `create_pending`, `create_admin`, `update_account`, `fetch_accounts`, `fetch_staff_batch`.

### 2.3 Session-Oriented Intake Operations

The Manage Forms workflow orchestrates secure intake sessions:

1. Template selection and session creation in `form_submission`.
2. QR generation for client pairing — the QR code now encodes a JSON payload (`{"sessionId": "...", "templateId": "..."}`) binding the session to the selected form template.
3. Mobile payload validation via the `decrypt-qr-payload` Edge Function (`supabase/functions/decrypt-qr-payload/index.ts`), which authenticates the mobile user's JWT, validates envelope completeness, and transitions `form_submission.status` to `'scanned'`.
4. **Zero-Knowledge Staging:** On-demand decryption of encrypted envelope via `serve-submission-for-review` Edge Function (`supabase/functions/serve-submission-for-review/index.ts`), delivering plaintext in-memory to dashboard without database persistence. Staff authorization validated against `staff_accounts` (role, is_active, account_status). Session expiry returns HTTP 410.
5. Autofilled form review and controlled finalization.
6. Session closure and display reset behaviors.

**Form Template Mismatch Prevention:** The QR's embedded `templateId` enables the mobile client to validate that the client's selected form matches the staff's active session template before any data is transmitted. If a mismatch is detected, transmission is blocked with a user-facing warning, and the camera is re-activated for re-scanning. Legacy single-UUID QR codes continue to work for backward compatibility.

**Session Expiry Handling:** The `serve-submission-for-review` Edge Function returns HTTP 410 with `reason = 'session_expired'` when `expires_at` has elapsed, so staff workflows and diagnostics can distinguish stale sessions from generic decryption failures.

This is the operational heart of CSWD intake execution.

### 2.4 Secured Autofill Engine Consumption

The web layer consumes backend-decrypted payload data through the Zero-Knowledge Staging architecture:

1. When a session with `status='scanned'` and empty `form_data` is detected, the dashboard controller (`ManageFormsController`) invokes on-demand decryption.
2. The `serve-submission-for-review` Edge Function (`supabase/functions/serve-submission-for-review/index.ts`) validates staff authorization against `staff_accounts`, unwraps the RSA-encrypted AES key using `RSA_PRIVATE_KEY_PEM` from Edge Secrets, decrypts the payload in-memory, and returns plaintext JSON in the HTTP response, or returns HTTP 410 `session_expired` when the session lifetime has elapsed. Audit event logged to `audit_logs`.
3. Staff perform quality review and final record commitment into `client_submissions`.

**Cross-User Name Resolution (`resolve-applicant-names` Edge Function):** When staff view applicant records, the `resolve-applicant-names` Edge Function (`supabase/functions/resolve-applicant-names/index.ts`) decrypts applicant first/middle/last names from `user_field_values` server-side. Staff never need encryption keys client-side. The function validates staff authorization against `staff_accounts`, queries `form_fields` for field IDs matching `canonical_field_key IN ('first_name', 'middle_name', 'last_name')`, fetches encrypted values, derives the HMAC-SHA256 key server-side, and returns plaintext names ephemerally.

Critical security guarantee: Plaintext is never written back to `form_submission`. The encrypted envelope remains the authoritative storage form until finalization.

This creates a deliberate separation between encrypted-session state and finalized applicant records.

### 2.5 Applicant Archive and Case History

The Applicants workflow and dashboard services provide:

1. Retrieval of finalized submissions.
2. Editable record review within role-governed boundaries.
3. Applicant-level history and form-type views.
4. Intake reference continuity via `intake_reference` metadata.
5. **Batch decryption optimization**: The applicants screen now loads 5-10x faster using the `decrypt-submission-batch` Edge Function (`supabase/functions/decrypt-submission-batch/index.ts`), which decrypts up to 20 records per request in parallel with a single key import operation. Staff role validated once per batch.

### 2.6 Dynamic Form Builder and Runtime Evolution

The web platform hosts the institutional form lifecycle module:

1. Draft form authoring.
2. Structural editing of sections, fields, options, and conditions.
3. Publication and push-to-mobile transitions.
4. Dynamic rendering compatibility for both staff and mobile clients.

This allows CSWD form policy evolution without schema-per-form redesign.

### 2.6.1 Form Builder Unsaved Changes Detection

The form builder screen implements change tracking to prevent accidental loss of template edits:

1. A `_hasUnsavedChanges` flag is set to true whenever a field, section, condition, or reference format is modified.
2. When the user navigates away or closes the form builder, a WillPopScope dialog is presented if unsaved changes are detected.
3. The dialog offers two options: **Save** (which executes `_saveTemplate()`) or **Leave without saving** (which discards pending edits).
4. The title bar displays a visual indicator ("•  unsaved changes") when the template has pending modifications.

This ensures form editors have explicit control over template publication without accidental overwrites.

### 2.6.2 Template and Field Notification Broadcasting

When staff editors modify form templates, `FormBuilderService.saveTemplateStructure()` (lines 484-581) populates the `form_template_notifications` table with events including:

1. **Template lifecycle events**: `added`, `updated`, `deleted`, `published`, `pushed_to_mobile`, `archived`.
2. **Field lifecycle events**: `field_added`, `field_updated`, `field_deleted`.

The `FormTemplateNotificationService` broadcasts these events via Supabase Realtime to all connected clients (both web and mobile), ensuring:

- Mobile users are notified in near-real-time when forms they are viewing or about to use are modified.
- Web editors receive notifications confirming their publishing and push actions.
- Clients can choose to reload the form manifest immediately via a RELOAD button on the notification.
- Read state is tracked per user in `user_notification_reads`.

### 2.7 Conditional Logic and Computed Runtime

The web runtime supports complex form semantics including conditional visibility and computed/aggregate field behavior, providing robust intake modeling for varied social-case requirements.

### 2.8 Dashboard Analytics and Planning Views

The dashboard includes workload and intake analytics modules (counts, trends, distributions) for operational monitoring and planning.

**Enhanced Analytics Features**:

1. **Worker Drill-Down**: Interactive bar charts allow clicking on individual workers to view their submission breakdown by form type via `DashboardAnalyticsService.fetchSubmissionsByFormTypeForWorker()`.

2. **Client Search**: TextField filter in widgets list UI enables filtering clients by name for quick access.

3. **Configurable Card Elevation**: `AppColors.cardDecoration` accepts elevation parameter (1–3) controlling shadow depth, making visual hierarchy configurable.

4. **Time-Frame Filtering**: Dashboard supports time-based filtering for workload analysis (work in progress).

5. **Batch Data Processing**: Dashboard analytics now use `batchDecryptSubmissions()` for efficient bulk record loading via `decrypt-submission-batch` Edge Function.

6. **Chart Simplification**: The dashboard keeps only line, horizontal bar, and bar chart types, removing unused chart widgets for a cleaner analytics surface.

7. **Dashboard Configuration Tables**: Per-template chart and card settings are stored in `dashboard_widget_configs` and `dashboard_card_settings`, keeping analytics presentation metadata-driven.

### 2.9 Display Session Management (Extended Feature)

The web tier controls station-linked display synchronization through `display_sessions`, enabling customer-facing monitor updates and queue/session status projection.

The customer display screen now also includes an applicant mirror form so the public-facing view can mirror the active intake session state.

### 2.10 Client Submissions Encryption (Extended Feature)

Finalized applicant records written to `client_submissions` are encrypted server-side using AES-256-GCM:

1. When staff finalize a session by calling `_finalizeEntry()`, the form data is sent to the `encrypt-and-save-submission` Edge Function (`supabase/functions/encrypt-and-save-submission/index.ts`).
2. The Edge Function generates a random 12-byte IV and encrypts the JSON payload using AES-256-GCM with a `SERVER_AES_KEY` stored in Supabase Edge Secrets.
3. The encrypted data is stored in `client_submissions.data` (Base64 encoded), with the IV stored in `data_iv` and `data_encryption_version` set to 1.
4. When staff need to retrieve the finalized record, the `decryptSubmissionData()` method calls the `decrypt-submission-data` Edge Function (`supabase/functions/decrypt-submission-data/index.ts`), which verifies staff authorization against `staff_accounts` and returns plaintext JSON.
5. The decryption is transparent to downstream rendering—staff view plaintext records in the Applicants screen as before.

This provides a server-side encryption layer protecting finalized applicant records at rest, complementing the client-side encryption for user PII in `user_field_values` and the hybrid transport encryption in `form_submission`.

### 2.10.1 Duplicate Submission Warning

Before encrypting, the same Edge Function checks whether the payload is identical to an earlier submission by that applicant, so redundant entries stop piling up on the Applicants screen.

**What staff see.** On pressing **Save to Applicants**:

- **No match** — saves silently, exactly as before. No extra dialog, no added click.
- **Match** — a confirm dialog naming the date and intake reference of the most recent identical submission:

  > **Identical submission**
  > This form is exactly the same as the entry submitted on Jul 22, 2026 at 14:31 (AICS-20260722-000045). Nothing has changed.
  >
  > Save it to Applicants anyway?

  **Save anyway** writes the row and records `outcome = duplicate_acknowledged` in the audit log. **Cancel** writes nothing and leaves the session open, so staff can correct a field and retry.

**How the comparison works.** `client_submissions.data` is ciphertext with a random IV, so identical answers produce different bytes and nothing in SQL can compare two submissions. The Edge Function instead hashes the plaintext before encrypting it (CSH-1) into a plaintext `content_hash` column, and derives an `applicant_key` identity token from the linked account or a salted name+birth-date fingerprint. Detection compares those two columns.

**Three behaviours that look like faults but are intentional:**

1. **Detection is advisory, with no database constraint.** Staff can always override, which rules out a `UNIQUE` index — it would reject the acknowledged insert outright. The consequence is that two simultaneous identical submissions from *different* sessions can both land.
2. **Walk-ins with no name or birth date are never flagged.** Identity cannot be derived, and matching on content alone would wrongly tell staff that two different people are the same applicant.
3. **A re-signed form is not a duplicate.** The signature is part of the hash, so re-signing counts as a genuine change.

Submissions predating the deployment hold `NULL` in both columns and can never match; backfilling would require bulk-decrypting the archive. Full specification: `docs/15_Submission_Deduplication.md`.

### 2.11 Applicant Review Workflow (Approve / Deny)

The web platform provides staff with the ability to review finalized applicant submissions and issue a decision (approve or deny), which is then reflected in real-time on the citizen's mobile history screen.

#### 2.11.1 Review Lifecycle

Each finalized submission in `client_submissions` carries a `review_status` column with three possible values:

1. **`pending`** (default) — The submission has been finalized but not yet reviewed.
2. **`approved`** — The application has been approved by staff.
3. **`denied`** — The application has been denied, with an optional `review_notes` field explaining the reason.

Staff can change the review status through the applicant detail view in the Applicants screen. When a decision is made:

- The `review_status` column is updated on the `client_submissions` row.
- The `reviewed_by` column records the staff member's identifier.
- The `reviewed_at` column records the timestamp of the decision.
- The `review_notes` column stores the denial reason (if denied).

#### 2.11.2 Database Triggers for Notification Propagation

Two database triggers automatically populate the `user_submission_notifications` table, which the mobile client consumes:

- **Trigger 1 (form_submission.status change):** When `form_submission.status` transitions (e.g. `active` → `scanned` → `completed`), a notification is inserted with messages like "Your QR code has been scanned" or "Your form has been saved".
- **Trigger 2 (client_submissions.review_status change):** When `review_status` changes from `pending` to `approved` or `denied`, a notification is inserted with messages like "Your application has been approved!" or "Your application has been denied. Reason: [notes]".

These triggers ensure that the mobile client receives status updates without requiring polling from the web side.

#### 2.11.3 Search-Applicants Edge Function Integration

The `search-applicants` Edge Function (`supabase/functions/search-applicants/index.ts`) was updated to include `review_status` in its metadata query and response. When staff search for applicants by name, the returned records now include each applicant's current review status, enabling staff to see the approval state directly in search results without requiring an extra database query.

### 2.12 Audit and Administrative Forensics

Audit log views provide privileged inspection of high-impact events (auth, staff, template, session, submission categories), strengthening accountability and incident traceability.

**Enhanced Audit Capabilities**:

1. **Submission Decryption Logging**: The `decrypt-submission-data` Edge Function automatically logs all decryption events with:
   - `action_type`: `submission_decrypted`
   - `category`: `submission`
   - `severity`: `info`
   - Actor ID and target submission ID for forensic traceability.

2. **Session Preview Logging**: The `serve-submission-for-review` Edge Function logs `submission_preview_decrypted` events to `audit_logs` (lines 202-210).

3. **Action Type Filtering**: Audit logs screen includes filter dropdown to narrow logs by specific action types, improving investigative efficiency.

## 3. Web Architecture: Separation of Concerns

The web tier implements a layered architecture that cleanly separates business logic from UI rendering, mirroring the mobile pattern:

### 3.1 Controllers Layer (Business Logic & State Management)

Controllers (`lib/web/controllers/`) encapsulate application logic and state coordination:

- **`ManageFormsController`**: Session orchestration, payload fingerprinting, intake reference formatting, session state coordination, QR template binding validation.
- **`FormBuilderController`**: Utility functions for form template construction (UUID generation, code sanitization, reference formatting, token/separator management).
- **`FormBuilderScreenController`**: Complete form builder state management (template loading, field/section/condition editing, publication workflow, unsaved changes tracking).
- **`DashboardController`**: Analytics data loading, chart generation, client search, workload distribution coordination.
- **`ApplicantsController`**: Finalized submission retrieval, record editing, applicant history navigation.
- **`ManageStaffController`**: Staff account lifecycle (pending approvals, activation/deactivation, and role display only in Manage Staff).

Controllers extend `ChangeNotifier` for reactive state management and coordinate service interactions.

### 3.2 Screens Layer (UI Rendering)

Screens (`lib/web/screen/`) handle UI presentation and delegate business logic to controllers:

- Receive state updates from controllers via listeners.
- Translate user interactions into controller method calls.
- Render dynamic forms, data tables, charts, dialogs, and navigation flows.
- Manage UI-specific state (scroll position, expanded/collapsed panels) separately from business logic.

This separation allows screens to remain thin and testable, with complex logic residing in controllers.

### 3.3 Components Layer (Reusable Analytics & Chart Components)

Components (`lib/web/components/`) provide specialized, reusable pieces for analytics and visualization:

- **`AutoChartBuilder`**: Dynamic chart generation based on analytics data.
- **`IntakeChartWidgets`**: Visualization components for intake trends, demographics, and workload distribution.
- **`FormTypeAnalyticsConfig`**: Configuration for form-type-specific analytics rendering.

Components are independent and composed by screens and controllers.

### 3.4 Widgets Layer (Reusable UI Components)

Widgets (`lib/web/widgets/`) provide composable UI building blocks:

- **Form builder components**: `FormBuilderFieldCard`, `FormBuilderSectionHeader`, `FormBuilderTitleCard`, `FormBuilderTemplateListPanel`, `FormBuilderStatusCard` - enabling massive form builder screen reduction and reusability.
- **Dialog components**: `LogoutConfirmationDialog`.
- **Navigation components**: `SideMenu`, `WebShell`.

Widgets are independent and reusable across multiple screens, reducing duplication.

### 3.5 Utilities Layer (Shared Helpers)

Utilities (`lib/web/utils/`) provide cross-cutting functionality:

- **`PageTransitions`**: Animated page transition definitions for navigation.
- **`WebNavigator`**: Centralized navigation routing and context management for staff screens.

This refactoring improves code reusability, testability, and maintainability while optimizing state management. The form builder was particularly heavily refactored: the original 4776-line monolithic screen was split into a controller (964 lines), helper functions (452 lines), reusable widget cards (2151+ lines), enabling future maintenance and feature additions without further bloat.

## 4. Security and Governance Control Surface

The web tier contributes the following controls:

1. Role-constrained interface exposure by staff privilege tier.
2. Account-status enforcement (`pending`, `active`, `deactivated`).
3. OTP-assisted staff setup and reset mechanisms.
4. Session lifecycle containment through `form_submission` status and expiry controls.
5. Audit logging for sensitive administrative actions.
6. Server-side AES-256-GCM encryption of finalized records in `client_submissions`.
7. Server-side name resolution via `resolve-applicant-names` Edge Function — encryption keys never reach the browser.

### 4.1 Staff Table RLS Architecture

`staff_accounts`, `staff_profiles`, and `staff_display_view` are protected by restrictive RLS policies. Direct table access from `anon` and `authenticated` is denied, and all staff data operations are mediated through the `manage-staff-account` Edge Function using `SUPABASE_SERVICE_ROLE_KEY`.

| Dart File | Edge Function Actions Used |
|---|---|
| `web_auth_service.dart` | `login`, `update_last_login`, `fetch_profile`, `fetch_password_hash`, `update_account` |
| `web_signup_service.dart` | `check_username`, `create_pending` |
| `staff_admin_service.dart` | `check_username_unique`, `fetch_accounts`, `update_account`, `create_admin` |
| `staff_email_service.dart` | `fetch_account` |
| `web_shell.dart` | `fetch_account`, `fetch_profile` |

**Key security properties:**
- The anon key shipped with the client cannot read or write any staff table directly
- Password hashes are validated server-side via bcrypt in the `manage-staff-account` Edge Function
- Account creation includes automatic rollback if profile insertion fails
- `staff_accounts`, `staff_profiles`, and `staff_display_view` are protected by restrictive RLS policies
- All access to staff tables is mediated through the `manage-staff-account` Edge Function using `SUPABASE_SERVICE_ROLE_KEY`

## 5. Manuscript Alignment and Added Capabilities

### 5.1 Manuscript-Aligned Web Core

1. CSWD staff dashboard for intake management.
2. Secured autofill consumption after backend decryption.
3. Basic role-based access for decrypted applicant records.

### 5.2 Added Web Enhancements

1. Dedicated admin creation and staff lifecycle governance.
2. Dynamic form builder with publication pipeline.
3. Form builder unsaved changes detection and discard workflow.
4. Template and field lifecycle notifications via Realtime broadcasting to all connected clients.
5. Customer-display session broadcasting.
6. Client submissions server-side AES-256-GCM encryption for finalized applicant records.
7. **Batch decryption optimization**: 5-10x faster applicants screen loading via `decrypt-submission-batch` Edge Function.
8. Audit log observability with submission decryption tracking and action type filtering.
9. **Enhanced dashboard analytics**: Worker drill-down, client search, configurable card elevation, time-frame filtering, batch data processing, and chart simplification.
10. Layered architecture with clean separation of concerns: Controllers (business logic), Screens (UI rendering), Components (analytics/chart), Widgets (reusable UI), Utilities (shared helpers).

## 6. Primary Data Touchpoints

Web workflows interact primarily with:

1. `staff_accounts`
2. `staff_profiles`
3. `form_submission`
4. `client_submissions`
5. `form_templates`
6. `form_sections`
7. `form_fields`
8. `form_field_options`
9. `form_field_conditions`
10. `display_sessions`
11. `audit_logs`
12. `form_template_notifications` (write via `FormBuilderService`, read via Realtime)
13. `user_notification_reads` (read state tracking)
14. `dashboard_widget_configs` (chart configuration)
15. `dashboard_card_settings` (card elevation preferences)
16. `app_rsa_keypairs` (via `get_active_rsa_public_key` RPC for public key distribution)
17. `user_field_values` (via `resolve-applicant-names` Edge Function for name resolution)

This table footprint reflects the web role as intake adjudicator, governance surface, and system configuration authority.
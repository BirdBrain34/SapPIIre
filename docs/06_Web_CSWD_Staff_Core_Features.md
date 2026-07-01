# 06. Web CSWD Staff Core Features

## 1. Audience and Operational Objective

The web platform is designed for CSWD personnel, including viewers, form editors, administrators, and superadministrators. Its primary objective is to receive secure client payloads, manage intake workflows, govern staff access, and evolve form infrastructure for institutional continuity.

## 2. Core Functional Domains

### 2.1 Staff Authentication and Access Policy

The web tier enforces role-sensitive authentication behavior:

1. Superadmin login policy using username resolution.
2. Staff login policy using email resolution.
3. Password hash verification and account-state gating (`is_active`, `account_status`).
4. First-login onboarding flow requiring credential setup.

Role and state controls are anchored in `staff_accounts` and profile enrichment in `staff_profiles`.

### 2.2 Staff Onboarding, Admin Creation, and Governance (Extended Feature)

The staff governance pipeline includes:

1. Pending account registration with `requested_role` intake.
2. Approval and rejection workflows for elevated access.
3. Superadmin-level direct creation of admin accounts.
4. Account activation, deactivation, reactivation, and role-update controls.
5. OTP-assisted new staff setup and account recovery flows.

This capability directly supports institutional staffing realities and reduces manual account-administration overhead.

### 2.3 Session-Oriented Intake Operations

The Manage Forms workflow orchestrates secure intake sessions:

1. Template selection and session creation in `form_submission`.
2. QR generation for client pairing.
3. Realtime ingestion of mobile-transmitted payload state.
4. **Zero-Knowledge Staging:** On-demand decryption of encrypted envelope via `serve-submission-for-review` Edge Function, delivering plaintext in-memory to dashboard without database persistence.
5. Autofilled form review and controlled finalization.
6. Session closure and display reset behaviors.

This is the operational heart of CSWD intake execution.

### 2.4 Secured Autofill Engine Consumption

The web layer consumes backend-decrypted payload data through the Zero-Knowledge Staging architecture:

1. When a session with `status='scanned'` and empty `form_data` is detected, the dashboard controller (`ManageFormsController`) invokes on-demand decryption.
2. The `serve-submission-for-review` Edge Function unwraps the RSA-encrypted AES key, decrypts the payload in-memory, and returns plaintext JSON in the HTTP response.
3. Staff perform quality review and final record commitment into `client_submissions`.

Critical security guarantee: Plaintext is never written back to `form_submission`. The encrypted envelope remains the authoritative storage form until finalization.

This creates a deliberate separation between encrypted-session state and finalized applicant records.

### 2.5 Applicant Archive and Case History

The Applicants workflow and dashboard services provide:

1. Retrieval of finalized submissions.
2. Editable record review within role-governed boundaries.
3. Applicant-level history and form-type views.
4. Intake reference continuity via `intake_reference` metadata.
5. **Batch decryption optimization**: The applicants screen now loads 5-10x faster using the `decrypt-submission-batch` Edge Function, which decrypts up to 20 records per request in parallel with a single key import operation.

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

When staff editors modify form templates, database triggers populate the `form_template_notifications` table with events including:

1. **Template lifecycle events**: `added`, `updated`, `deleted`, `published`, `pushed_to_mobile`, `archived`.
2. **Field lifecycle events**: `field_added`, `field_updated`, `field_deleted`.

The `FormTemplateNotificationService` broadcasts these events via Supabase Realtime to all connected clients (both web and mobile), ensuring:

- Mobile users are notified in near-real-time when forms they are viewing or about to use are modified.
- Web editors receive notifications confirming their publishing and push actions.
- Clients can choose to reload the form manifest immediately via a RELOAD button on the notification.
- The online notification path is stable end-to-end, so live clients receive updates without stale builder state.

### 2.7 Conditional Logic and Computed Runtime

The web runtime supports complex form semantics including conditional visibility and computed/aggregate field behavior, providing robust intake modeling for varied social-case requirements.

### 2.8 Dashboard Analytics and Planning Views

The dashboard includes workload and intake analytics modules (counts, trends, distributions) for operational monitoring and planning.

**Enhanced Analytics Features**:

1. **Worker Drill-Down**: Interactive bar charts allow clicking on individual workers to view their submission breakdown by form type via `DashboardAnalyticsService.fetchSubmissionsByFormTypeForWorker()`.

2. **Client Search**: TextField filter in widgets list UI enables filtering clients by name for quick access.

3. **Configurable Card Elevation**: `AppColors.cardDecoration` accepts elevation parameter (1–3) controlling shadow depth, making visual hierarchy configurable.

4. **Time-Frame Filtering**: Dashboard supports time-based filtering for workload analysis (work in progress).

5. **Batch Data Processing**: Dashboard analytics now use `batchDecryptSubmissions()` for efficient bulk record loading.

6. **Chart Simplification**: The dashboard keeps only line, horizontal bar, and bar chart types, removing unused chart widgets for a cleaner analytics surface.

7. **Dashboard Configuration Tables**: Per-template chart and card settings are stored in `dashboard_widget_configs` and `dashboard_card_settings`, keeping analytics presentation metadata-driven.

### 2.9 Display Session Management (Extended Feature)

The web tier controls station-linked display synchronization through `display_sessions`, enabling customer-facing monitor updates and queue/session status projection.

The customer display screen now also includes an applicant mirror form so the public-facing view can mirror the active intake session state.

### 2.10 Client Submissions Encryption (Extended Feature)

Finalized applicant records written to `client_submissions` are encrypted server-side using AES-256-GCM:

1. When staff finalize a session by calling `_finalizeEntry()`, the form data is sent to the `encrypt-and-save-submission` Edge Function.
2. The Edge Function generates a random 12-byte IV and encrypts the JSON payload using AES-256-GCM with a `SERVER_AES_KEY` stored in Supabase Edge Secrets.
3. The encrypted data is stored in `client_submissions.data` (Base64 encoded), with the IV stored in `data_iv` and `data_encryption_version` set to 1.
4. When staff need to retrieve the finalized record, the `decryptSubmissionData()` method calls the `decrypt-submission-data` Edge Function, which verifies staff authorization and returns plaintext JSON.
5. The decryption is transparent to downstream rendering—staff view plaintext records in the Applicants screen as before.

This provides a server-side encryption layer protecting finalized applicant records at rest, complementing the client-side encryption for user PII in `user_field_values` and the hybrid transport encryption in `form_submission`.

### 2.11 Audit and Administrative Forensics

Audit log views provide privileged inspection of high-impact events (auth, staff, template, session, submission categories), strengthening accountability and incident traceability.

**Enhanced Audit Capabilities**:

1. **Submission Decryption Logging**: The `decrypt-submission-data` Edge Function automatically logs all decryption events with:
   - `action_type`: `submission_decrypted`
   - `category`: `submission`
   - `severity`: `info`
   - Actor ID and target submission ID for forensic traceability.

2. **Action Type Filtering**: Audit logs screen includes filter dropdown to narrow logs by specific action types, improving investigative efficiency.

## 3. Web Architecture: Separation of Concerns

The web tier implements a layered architecture that cleanly separates business logic from UI rendering, mirroring the mobile pattern:

### 3.1 Controllers Layer (Business Logic & State Management)

Controllers (`lib/web/controllers/`) encapsulate application logic and state coordination:

- **`ManageFormsController`**: Session orchestration, payload fingerprinting, intake reference formatting, session state coordination.
- **`FormBuilderController`**: Utility functions for form template construction (UUID generation, code sanitization, reference formatting, token/separator management).
- **`FormBuilderScreenController`**: Complete form builder state management (template loading, field/section/condition editing, publication workflow, unsaved changes tracking).
- **`DashboardController`**: Analytics data loading, chart generation, client search, workload distribution coordination.
- **`ApplicantsController`**: Finalized submission retrieval, record editing, applicant history navigation.
- **`ManageStaffController`**: Staff account lifecycle (pending approvals, role updates, activation/deactivation).

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
9. **Enhanced dashboard analytics**: Worker drill-down, client search, configurable chart elevation, time-frame filtering, batch data processing, and chart simplification.
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

This table footprint reflects the web role as intake adjudicator, governance surface, and system configuration authority.

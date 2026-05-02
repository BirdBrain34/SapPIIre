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
5. OTP-assisted new staff setup and reset flows.

This capability directly supports institutional staffing realities and reduces manual account-administration overhead.

### 2.3 Session-Oriented Intake Operations

The Manage Forms workflow orchestrates secure intake sessions:

1. Template selection and session creation in `form_submission`.
2. QR generation for client pairing.
3. Realtime ingestion of mobile-transmitted payload state.
4. Autofilled form review and controlled finalization.
5. Session closure and display reset behaviors.

This is the operational heart of CSWD intake execution.

### 2.4 Secured Autofill Engine Consumption

The web layer consumes backend-decrypted payload data by binding `form_submission.form_data` into dynamic controllers. Staff then perform quality review and final record commitment into `client_submissions`.

This creates a deliberate separation between scanned-session state and finalized applicant records.

### 2.5 Applicant Archive and Case History

The Applicants workflow and dashboard services provide:

1. Retrieval of finalized submissions.
2. Editable record review within role-governed boundaries.
3. Applicant-level history and form-type views.
4. Intake reference continuity via `intake_reference` metadata.

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

### 2.7 Conditional Logic and Computed Runtime

The web runtime supports complex form semantics including conditional visibility and computed/aggregate field behavior, providing robust intake modeling for varied social-case requirements.

### 2.8 Dashboard Analytics and Planning Views

The dashboard includes workload and intake analytics modules (counts, trends, distributions) for operational monitoring and planning.

### 2.9 Display Session Management (Extended Feature)

The web tier controls station-linked display synchronization through `display_sessions`, enabling customer-facing monitor updates and queue/session status projection.

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

## 3. Security and Governance Control Surface

The web tier contributes the following controls:

1. Role-constrained interface exposure by staff privilege tier.
2. Account-status enforcement (`pending`, `active`, `deactivated`).
3. OTP-assisted staff setup and reset mechanisms.
4. Session lifecycle containment through `form_submission` status and expiry controls.
5. Audit logging for sensitive administrative actions.

## 4. Manuscript Alignment and Added Capabilities

### 4.1 Manuscript-Aligned Web Core

1. CSWD staff dashboard for intake management.
2. Secured autofill consumption after backend decryption.
3. Basic role-based access for decrypted applicant records.

### 4.2 Added Web Enhancements Beyond Initial Prompt

1. Dedicated admin creation and staff lifecycle governance.
2. Dynamic form builder with publication pipeline.
3. Form builder unsaved changes detection and discard workflow.
4. Template and field lifecycle notifications via Realtime broadcasting to all connected clients.
5. Customer-display session broadcasting.
6. Client submissions server-side AES-256-GCM encryption for finalized applicant records.
7. Audit log observability and analytics modules.

## 5. Primary Data Touchpoints

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
12. `staff_password_reset_otp`

This table footprint reflects the web role as intake adjudicator, governance surface, and system configuration authority.

# 05. Mobile Client Core Features

## 1. Audience and Operational Objective

The mobile application is designed for citizen or client users whose primary objective is to maintain personal profile data and securely transmit selected data to CSWD staff during intake sessions. The mobile tier is therefore user-data centric and privacy-first.

## 2. Core Functional Domains

### 2.1 Account Access and Verification

The mobile identity flow includes:

1. Username-password sign-in for returning users.
2. Multi-step signup with profile completion.
3. Email OTP verification through Supabase Auth pathways.
4. Phone OTP verification via the `send-phone-otp` Edge Function (`supabase/functions/send-phone-otp/index.ts`), which calls the Semaphore SMS API from cloud infrastructure (faster than mobile-initiated calls), verifies the SMS was queued by parsing the Semaphore response, and refreshes the `phone_otp` record with a delete-then-insert to prevent stale code collisions. OTP expiry window is 10 minutes; the mobile countdown timer is 120 seconds. Verification is handled by the `verify-phone-otp` Edge Function (`supabase/functions/verify-phone-otp/index.ts`), which calls `verify_and_consume_phone_otp` RPC for atomic verification-and-deletion — preventing replay attacks.
5. Incomplete signup retry support: if a previous signup attempt left an orphaned `user_accounts` record with no `user_field_values`, `checkDuplicateSignup` returns `incomplete: true` with the existing `user_id`, allowing the user to resume without contacting support.
6. Phone-only signup defers Supabase Auth user creation to the credentials step, using a deterministic synthetic email (`<digits>@sappiire.phone`) so no real email is required.
7. Password reset services with email and phone-assisted recovery flows.

This layered entry process aligns user convenience with risk-reduction for account misuse.

### 2.2 PII Capture and Lifecycle Management

The mobile user manages profile fields through dynamic templates and form-state controllers. Data entry supports:

1. Manual profile editing.
2. Persistent storage via field-level save routines.
3. Canonical-field reuse across multiple templates.
4. Explicit field-selection controls for selective transmission.

Persistent PII values are mapped into `user_field_values` by `field_id`, supporting cross-template continuity and downstream autofill consistency.

### 2.3 Encrypted Data-at-Rest Semantics

For protected rows, user field values are persisted with encryption metadata (`iv`, `encryption_version`). The mobile app now retrieves AES keys through the `derive-field-key` Edge Function (`supabase/functions/derive-field-key/index.ts`), which validates the caller's JWT, derives the key using `FIELD_KEY_HMAC_SECRET_V2` in Edge Secrets, and prevents IDOR by verifying record ownership. The derived key is cached only in volatile memory on the device and destroyed upon logout. See [docs/01_QR_Handshake_and_Cryptography.md](docs/01_QR_Handshake_and_Cryptography.md) for the v1-to-v2 comparison.

### 2.4 InfoScanner OCR Workflow (Extended Feature)

The InfoScanner module operationalizes ID-assisted onboarding through:

1. Camera capture pipeline.
2. OCR extraction via `google_mlkit_text_recognition`.
3. Front/back ID parsing logic for key identity attributes.
4. User confirmation and save routing to field-value persistence.

This feature reduces manual encoding effort and improves intake throughput while keeping the user in control of final submitted values.

**Security hardening (v1.0.0):** After OCR text is extracted from the captured ID photo, the temporary image file is immediately deleted from the app cache via a best-effort cleanup in `finally` block. This prevents PII-containing images (name, DOB, address) from lingering on disk.

### 2.5 QR Session Transmission and Secure Autofill Trigger

The mobile app performs session-targeted data transmission by:

1. Scanning staff-generated session QR identifiers (now JSON-encoded with `sessionId` + `templateId`).
2. **Validating form template match** between the scanned QR's `templateId` and the mobile user's currently selected template:
   - If templates match, proceed with transmission.
   - If templates mismatch, display a warning dialog and block transmission, re-activating the camera for re-scanning.
   - Legacy plain-text UUID QR codes are accepted for backward compatibility.
3. Building a filtered payload from user-selected fields.
4. Packaging encrypted envelope artifacts (`encrypted_payload`, `payload_iv`, `encrypted_aes_key`).
5. Sending the envelope to the `decrypt-qr-payload` Edge Function (`supabase/functions/decrypt-qr-payload/index.ts`), which authenticates via JWT, validates envelope completeness, and transitions `form_submission.status` to `'scanned'`. This function does NOT decrypt — decryption is deferred.
6. **Zero-Knowledge Staging:** Encrypted envelope persists in `form_submission`; decryption occurs in-memory on staff request via `serve-submission-for-review` Edge Function, ensuring no plaintext persistence.

If the session is already expired, the mobile QR controller treats the transmission result as `expired`, shows an expired-session UI state, and prompts the user to scan again.

This is the client-side entry point of the hybrid cryptosystem handshake, now including a pre-transmission template guard to prevent cross-template data corruption.

### 2.6 Unsaved Changes Detection and Discard Workflow

The mobile client implements real-time change detection through form state fingerprinting:

1. On form load, a cryptographic fingerprint of the form state is captured and stored as `_savedFormFingerprint`.
2. As users edit fields, a listener tracks mutations and recomputes the current fingerprint.
3. If the fingerprint diverges from `_savedFormFingerprint`, the client marks the form as having unsaved changes.
4. On navigation or logout, the unsaved changes dialog is presented with options to Save or Discard.
5. Selecting Discard triggers `_discardPendingChangesAndRefresh()`, which reloads the last-saved form state from the server and cancels all pending mutations.

This provides user transparency for data entry intent and prevents accidental loss of committed changes while allowing explicit rollback of in-flight edits.

### 2.7 Real-Time Form Template Notifications

Mobile clients subscribe to real-time `form_template_notifications` table broadcasts via the `FormTemplateNotificationService`. Notifications are triggered by `FormBuilderService` when staff editors modify form templates in the web builder and include:

1. **Template-level events**: `added`, `updated`, `deleted`, `published`, `pushed_to_mobile`, `archived`.
2. **Field-level events**: `field_added`, `field_updated`, `field_deleted`.

Each notification includes a `change_type`, `changeSummary`, and `templateName`. On the mobile client:

- Notifications are classified by change category and rendered as floating SnackBars.
- Field-level changes display with a pencil icon (indicating field edits).
- New template arrivals display with a star-burst icon.
- Template removal displays with a minus-circle icon.
- Each notification includes a RELOAD action, allowing the user to refresh the form manifest immediately.

### 2.8 Mobile Notification Center

The **NotificationScreen** provides a centralized view of all form template notifications for the user:

1. **Notification List**: Displays all template and field change events with visual categorization:
   - Color-coded accent based on change type (green for added, blue for updated, red for removed).
   - Icon badges representing each change category.
   - Unread indicators (blue dot) and unread count in the app bar.
   - Time-ago timestamps for each notification.

2. **Expandable Details**: Notifications with field-level changes can be expanded to show bullet-point details:
   - "Added [Field Label]"
   - "Updated [Field Label]"
   - "Removed [Field Label]"

3. **Read State Management**:
   - Tap notification to mark as read.
   - "Mark all read" button in app bar for bulk operations.
   - Visual distinction between read (white background) and unread (blue tint) notifications.
   - Read state persisted in `user_notification_reads` table.

4. **Pull-to-Refresh**: Swipe down to reload notifications from server.

5. **Service Integration**: Powered by `SupabaseService.fetchAppNotifications()` and `markNotificationsRead()` methods, which query `form_template_notifications` and `user_notification_reads` tables.

This enables mobile users to stay informed of form infrastructure changes in near-real-time and provides full notification history with granular detail visibility.

### 2.9 User History and Profile Transparency

The mobile interface includes:

1. Submission history views linked to finalized records.
2. Profile dashboards for reviewing and updating stored identity fields.
3. Session-safe logout and account controls.
4. **Notification Center**: Dedicated NotificationScreen accessible from main navigation, providing centralized view of all form template changes with expandable details.

These functions improve user transparency regarding what has been submitted and what profile state remains active.

### 2.10 Read-Only and Computed Field Visual Cues

Dynamic form rendering now distinguishes immutable or computed values from editable fields:

1. Read-only fields use lock icons and distinct color treatment.
2. Computed fields receive stronger visual emphasis so users can see which values are system-derived.
3. Form state logic only applies the strongest visual indicator to computed fields after the latest refinement.

This keeps the mobile intake UI legible while preserving the difference between user-input fields and calculated outputs.

## 3. Mobile Architecture: Separation of Concerns

The mobile tier implements a layered architecture that cleanly separates business logic from UI rendering:

### 3.1 Controllers Layer (Business Logic & State Management)

Controllers (`lib/mobile/controllers/`) encapsulate application logic and state:

- **`ManageInfoController`**: Form template orchestration, field-state coordination, profile persistence, QR transmission payload building.
- **`LoginController`**: Authentication flow, credential validation, session initialization.
- **`SignupController`**: Multi-step registration state, OTP verification sequences, user account provisioning.
- **`HistoryController`**: Submission history retrieval, filtering, sorting, record access.
- **`ChangePasswordController`**: Password update flows, validation, OTP-assisted reset.
- **`InfoScannerController`**: OCR coordination, ID field extraction and mapping.
- **`ProfileController`**: User profile data retrieval and editing.
- **`QRScannerController`**: Session QR scanning, template validation, and encrypted payload transmission with explicit expired-session handling.

Controllers extend `ChangeNotifier` for reactive state management and coordinate service interactions.

### 3.2 Screens Layer (UI Rendering)

Screens (`lib/mobile/screens/auth/`) handle UI presentation and delegate business logic to controllers:

- Receive state updates from controllers via listeners.
- Translate user interactions into controller method calls.
- Render dynamic forms, input fields, dialogs, and navigation flows.
- Manage UI-specific state (scroll position, visibility flags) separately from business logic.

This separation allows screens to remain thin and testable, with complex logic residing in controllers.

### 3.3 Widgets Layer (Reusable UI Components)

Custom widgets (`lib/mobile/widgets/`) provide composable UI building blocks:

- **Input components**: `CustomTextField`, `LoginFloatingField`, `SignupTextField`, date pickers, dropdowns.
- **Dialog components**: `UnsavedChangesDialog`, `LogoutConfirmationDialog`, `PasswordChangedDialog`.
- **Form components**: `SignaturePadWidget`, `EditableTextField`, `EditableRadioGroup`.
- **Display components**: `ProfileHeader`, `HistoryCard`, `BottomNavBar`.
- **Specialized components**: `InfoScannerButton`, `SelectAllButton`, `SortChip`.

Widgets are independent and reusable across multiple screens, reducing duplication.

### 3.4 Utilities Layer (Shared Helpers)

Utilities (`lib/mobile/utils/`) provide cross-cutting functionality:

- **`AppDateUtils`**: Date parsing, formatting (e.g., "Jan 15, 2026 3:45 PM"), UUID validation.
- **`SnackbarUtils`**: Consistent feedback messages (`showError`, `showSuccess`, `showCustom`) with branded colors.

This refactoring improves code reusability, testability, and maintainability while optimizing state management and reducing widget rebuilds.

## 4. Security and Privacy Control Surface

The mobile tier contributes the following controls:

1. Selective field transmission rather than blanket payload sharing.
2. Hybrid cryptographic payload packaging before transit.
3. OTP-backed identity verification for sensitive account flows via `send-phone-otp` + `verify-phone-otp` Edge Functions.
4. At-rest protected field persistence model using `derive-field-key` Edge Function for key derivation.
5. Timestamped session handoff boundaries through `form_submission` lifecycle states.
6. Key derivation keys cached only in volatile memory, cleared on sign-out.
7. **Android platform hardening (v1.0.0):**
   - Data backup disabled (`android:allowBackup="false"`) to prevent PII from being included in Android auto-backup.
   - External storage permissions (`READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE`) explicitly removed from merged manifest — the app only uses the app-sandboxed camera cache.
   - Release build configured for production signing via `key.properties` (team must supply a keystore); no longer signs with the well-known debug certificate.

## 5. Manuscript Alignment and Added Capabilities

### 5.1 Manuscript-Aligned Mobile Core

1. Mobile PII management for form-ready identity data.
2. Hybrid crypto payload generation for secure transit.
3. QR handshake participation as the mobile transmitter endpoint.

### 5.2 Added Mobile Enhancements

1. InfoScanner OCR-assisted profile capture.
2. Extended OTP and password recovery workflows via `send-phone-otp` / `verify-phone-otp` Edge Functions.
3. Cross-template semantic autofill continuity through canonical field handling.
4. Unsaved changes detection with form-fingerprint tracking and explicit discard workflow.
5. Real-time template notifications for field and template lifecycle events, enabling mobile users to be aware of form infrastructure changes.
6. **Mobile Notification Center**: Dedicated NotificationScreen with expandable notification details, read state management (`user_notification_reads`), and pull-to-refresh.
7. Read-only and computed field visualization with lock-style affordances and distinct colors.
8. Layered architecture with clean separation of concerns: Controllers (business logic), Screens (UI rendering), Widgets (reusable components), Utilities (shared helpers).

## 6. Primary Data Touchpoints

Mobile workflows interact primarily with:

1. `user_accounts`
2. `user_field_values`
3. `form_submission`
4. `phone_otp`
5. `form_template_notifications` (Realtime subscription for template change awareness)
6. `user_notification_reads` (read state tracking for notifications)

This table footprint reflects the mobile role as secure data producer and controlled transmitter, not final record adjudicator.
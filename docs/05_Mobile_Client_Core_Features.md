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

**Release-mode log stripping (v1.0.1):** All `debugPrint()` calls in PII-handling services (`supabase_service.dart`, `hybrid_crypto_service.dart`) were migrated to `LogUtil.debugPrint()`. In release builds (`flutter build --release`), the `kReleaseMode` compile-time constant eliminates these calls entirely, ensuring no sensitive data is written to device logs in production. See [docs/02_Database_Security_and_PII_Mapping.md#72-release-mode-log-stripping-v101](docs/02_Database_Security_and_PII_Mapping.md#72-release-mode-log-stripping-v101) for details.

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

This is the client-side entry point of the hybrid cryptosystem handshake, now including a pre-transmission template guard to prevent cross-template data corruption and a pre-transmission OTP identity verification gate.

#### 2.5.1 Pre-Transmission OTP Gate

After QR template validation passes but before any payload encryption or transmission, the mobile client challenges the signed-in user with a "confirm it's you" OTP dialog (`lib/mobile/widgets/qr_transmission_otp_dialog.dart`):

1. The controller (`lib/mobile/controllers/qr_transmission_otp_controller.dart`) resolves the user's registered contact channels from `user_accounts` — email or phone.
2. The destination address is **always resolved server-side** — never accepted from the UI.
3. The displayed address is **masked** (e.g. `j***@email.com` or `****1234`) for privacy.
4. The user has **5 attempts** to enter the 6-digit code, with a **60-second resend cooldown**.
5. Email OTPs use Supabase Auth's `signInWithOtp`/`verifyOTP` via `PasswordResetService`.
6. Phone OTPs use the `send-phone-otp`/`verify-phone-otp` Edge Functions, with the verify call going directly to the Edge Function for full rate limiting (10 attempts/15 min).
7. Both success and failure are logged to `audit_logs` with action types `qr_transmission_otp_verified` and `qr_transmission_otp_failed`.

If the user cancels or verification fails, the scanner re-activates and no data is transmitted. Unauthenticated users (null `userId`) are also blocked from transmission.

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

#### 2.7.1 Deduplication and Debounce Batching

The notification system applies **four layers of defense** to prevent duplicate toasts and badge increments, which was a critical issue when editing large templates (e.g. GIS with dozens of fields):

1. **Service-level ID deduplication** (`FormTemplateNotificationService`): A `_processedIds` set tracks every notification ID already emitted. When Supabase Realtime delivers the same row in consecutive callbacks (initial snapshot + INSERT event), the duplicate ID is silently dropped. On `startListening()`, the set is cleared so a fresh subscription does not skip newly arrived rows.

2. **UI-level ID deduplication** (`_uiProcessedNotifIds` in `manage_info_screen.dart`): A second `Set<String>` at the UI listener provides an additional filter. Even if the service layer emits the same ID twice (due to stream controller timing), the UI skips it on second arrival.

3. **Debounce batching** (1.2s window): All notifications that arrive within a 1.2-second window are accumulated into a batch. When the timer fires, a single aggregated SnackBar is shown — e.g. *"3 form change(s) detected for 'Test Form'. Tap RELOAD."* — instead of N individual toasts. This prevents the toast overflow that would occur when a single save operation generates multiple field-level notification rows.

4. **Toast cooldown guard** (3s): After a SnackBar is shown, no new toast can appear for 3 seconds. This is the final backstop against any delayed duplicates that slip past the earlier layers.

#### 2.7.2 Notification Rendering

When the batch timer fires, notifications are classified by change category and rendered as a single floating SnackBar:
- Field-level changes display with a pencil icon (indicating field edits).
- New template arrivals display with a star-burst icon.
- Template removal displays with a minus-circle icon.
- The aggregated toast includes a RELOAD action, allowing the user to refresh the form manifest immediately.

#### 2.7.3 Bell Badge

The unread notification badge in the AppBar refreshes from the server (`_loadUnreadCount()`) after each batch is processed, rather than incrementing a local counter (`_unreadNotifCount++`). This ensures the badge always reflects the true unread count from `user_notification_reads`, regardless of how many notifications arrived in the batch.

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

### 2.10 Submission Status Workflow (Real-Time Review Visibility)

The mobile client provides real-time visibility into the lifecycle of finalized submissions once they have been transmitted and saved by CSWD staff. This bridges the gap between the initial QR scanning workflow and the eventual review decision (approve or deny).

#### 2.10.1 Status Lifecycle

Each submission in the citizen's history screen passes through the following status progression:

1. **Pending** (default) — The submission has been transmitted and saved by staff, but no review decision has been made. Displayed as an **amber** badge.
2. **Approved** — The application has been approved by CSWD staff. Displayed as a **green** badge.
3. **Denied** — The application has been denied, with an optional review note explaining the reason. Displayed as a **red** badge.

The `review_status` column on `client_submissions` is the authoritative source for the review state. Staff modify this column through the web applicant review workflow, and changes are propagated to the mobile client through three complementary mechanisms.

#### 2.10.2 Three-Layer Notification Architecture

The `HistoryController` (`lib/mobile/controllers/history_controller.dart`) implements a redundant delivery approach to ensure citizens are notified of review decisions even if one channel fails:

**Layer 1 — Realtime Subscription (Instant)**
- Subscribes to `user_notification_service.streamNotifications(userId)`, which listens to the `user_submission_notifications` table via Supabase Realtime.
- DB triggers automatically insert a notification row when `client_submissions.review_status` changes — e.g. "Your application has been approved!" or "Your application has been denied. Reason: [notes]".
- When a notification with `status = 'approved'` or `status = 'denied'` arrives, the controller immediately reloads the full history and fires the `onReviewDecision` callback.

**Layer 2 — Periodic Polling (Fallback, 20s interval)**
- As a fallback for when Realtime is not fully configured, a `Timer.periodic` polls every 20 seconds.
- The lightweight query `SELECT id, review_status, form_type FROM client_submissions WHERE session_id IN (...)` fetches only the status columns — avoiding the larger `data` blobs.
- Tracks `_lastReviewStatuses` in a map; when a status changes from `pending` to `approved`/`denied`, it triggers the same reload and callback as Layer 1.

**Layer 3 — Toast Notification (User-Facing Feedback)**
- The `onReviewDecision` callback is wired in `HistoryScreen.initState()`.
- A floating **SnackBar** slides in at the bottom of the screen:
  - **Green** background for approved: `"[Form Type] — Approved!"`
  - **Red** background for denied: `"[Form Type] — Denied"`
- The SnackBar includes a "View" action button and auto-dismisses after 4 seconds.
- The HistoryScreen also pushes a refresh indicator via the `RefreshIndicator` widget for manual pull-to-refresh.

#### 2.10.3 History Card Status Badge

Each `HistoryCard` (`lib/mobile/widgets/history_card.dart`) now renders a **StatusBadgeWidget** that replaces the former static "Submitted" label:

- **Pending** — Amber chip (`Color(0xFFF59E0B)`)
- **Approved** — Green chip (`Color(0xFF10B981)`)
- **Denied** — Red chip (`Color(0xFFEF4444)`)

The badge reads the `review_status` field from the submission item. If no `review_status` is set, it defaults to `pending`.

#### 2.10.4 History Detail Timeline

The **HistoryDetailDialog** (`lib/mobile/widgets/history_detail_dialog.dart`) uses the **ReviewTimelineWidget** to render a visual timeline of the submission lifecycle:

1. **QR Scanned** — When the mobile user scanned the staff's QR code (from `form_submission.scanned_at`).
2. **Form Saved** — When staff finalized the submission into `client_submissions` (from `client_submissions.created_at`).
3. **Under Review** — Shown while `review_status` is `pending`.
4. **Approved / Denied** — Final status with timestamp (`reviewed_at`) and notes (`review_notes`) if denied.

The timeline uses a vertical column of dots connected by lines, with status-appropriate colors: blue for scanned/saved, amber for pending, green for approved, red for denied.

#### 2.10.5 Notification Center — "My Submissions" Tab

The `NotificationScreen` (`lib/mobile/screens/auth/notification_screen.dart`) adds a second tab labeled **"My Submissions"** alongside the existing template change notifications tab:

- Calls `UserNotificationService.streamNotifications(userId)` for real-time updates.
- Each notification row displays:
  - **Status Badge** — colored chip matching the notification status
  - **Form Type** — e.g. "PWD Application"
  - **Message** — e.g. "Your application has been approved!"
  - **Intake Reference** — e.g. "CSWD-2026-00042"
  - **Timestamp** — relative (e.g. "2 hours ago")
- Tapping a notification marks it as read via `markRead(notificationId)`.
- An unread badge count appears on the tab label.

#### 2.10.6 Database Artifacts

The supporting database infrastructure includes:

- `client_submissions.review_status` column (`text`): values `pending`, `approved`, `denied`.
- `user_submission_notifications` table: auto-populated by DB triggers when `form_submission.status` or `client_submissions.review_status` changes. Includes `status`, `message`, `intake_reference`, `form_type`, `is_read`.
- DB Trigger 1: On `form_submission.status` change → inserts notification (e.g. "Your QR code has been scanned", "Your form has been saved").
- DB Trigger 2: On `client_submissions.review_status` change → inserts notification (e.g. "Your application has been approved!", "Your application has been denied. Reason: ...").

#### 2.10.7 Edge Function Integration

The `search-applicants` Edge Function (`supabase/functions/search-applicants/index.ts`) was updated to include `review_status` in its metadata query and response. When staff search for applicants by name on the web applicants screen, the returned records now include each applicant's current review status, enabling staff to see the approval state directly in search results without requiring an extra database query.

### 2.11 Read-Only and Computed Field Visual Cues

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
   - Release build configured for production signing via `key.properties` with a generated RSA 2048-bit keystore (`app/sappiire-release.jks`); no longer signs with the well-known debug certificate (resolves MobSF high-severity finding).
   - **Minimum SDK raised to 29 (v1.0.1):** `minSdk` set to 29 (Android 10), ensuring the app only installs on devices receiving standard security updates (resolves MobSF high-severity finding).

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
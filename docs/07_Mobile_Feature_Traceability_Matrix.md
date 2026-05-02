# 07. Mobile Feature Traceability Matrix

## 1. Scope

This matrix traces mobile-client capabilities to implementation surfaces and data artifacts. It is intended for audience-specific validation of citizen-facing functionality.

The mobile tier implements a **layered architecture** with clear separation of concerns:
- **Controllers** (`lib/mobile/controllers/`): Business logic, state management, service coordination
- **Screens** (`lib/mobile/screens/`): UI rendering, user interaction handling, navigation
- **Widgets** (`lib/mobile/widgets/`): Reusable UI components (inputs, dialogs, displays)
- **Utilities** (`lib/mobile/utils/`): Shared helpers (date formatting, feedback messages)

This architecture ensures reusability, testability, and maintainability across the mobile surface.

## 2. Traceability Matrix

| Mobile Feature | User Intent | Primary Mobile Modules | Primary Tables | Security or Governance Outcome |
| --- | --- | --- | --- | --- |
| Mobile login and authenticated access | Enter existing account and continue profile workflows | Controller: `LoginController` → Screen: `login_screen.dart` → Service: `SupabaseService.login` | `user_accounts` | Blocks deactivated accounts and preserves authenticated session boundary |
| Multi-step signup with verification | Register account and establish verified identity | Controller: `SignupController` → Screen: `signup_screen.dart` → Service: OTP flows via `SupabaseService` | `user_accounts`, `phone_otp` | Multi-factor verification posture for account creation |
| Password recovery and reset | Recover locked or forgotten access | Controller: `ChangePasswordController` → Service: `PasswordResetService` | `phone_otp`, `user_accounts` | Reduces account lockout risk while preserving verification controls |
| Dynamic profile capture and edit | Maintain current personal data for form reuse | Controller: `ManageInfoController` → Screen: `manage_info_screen.dart` → Service: `DynamicFormRenderer`, `FieldValueService` | `user_field_values`, `form_fields` | Structured user-owned PII persistence |
| Encrypted field persistence semantics | Protect sensitive values at rest | Controller: `ManageInfoController` → Service: `FieldValueService`, `HybridCryptoService` | `user_field_values` (`field_value`, `iv`, `encryption_version`) | Data-at-rest confidentiality model |
| Cross-template semantic fill | Reuse prior profile values across templates | Controller: `ManageInfoController` → Service: `FieldValueService.loadUserFieldValuesWithCrossFormFill` | `form_fields` (`canonical_field_key`), `user_field_values` | Reduces duplicate entry and mapping drift |
| Unsaved changes detection and discard | Prevent accidental loss of in-flight profile edits | Controller: `ManageInfoController` (fingerprinting) → Widget: `UnsavedChangesDialog` → Screen: `manage_info_screen.dart` | `user_field_values` | User intent protection with explicit discard workflow |
| Real-time template notifications | Stay aware of form infrastructure changes on mobile | Service: `FormTemplateNotificationService` → Screen: `manage_info_screen.dart` (SnackBar rendering) | `form_template_notifications` (Realtime subscription) | Reduces confusion from form changes during active use |
| InfoScanner OCR capture | Accelerate ID-based onboarding and reduce typing | Controller: `InfoScannerController` → Screen: `InfoScannerScreen.dart` → Service: `camera`, `google_mlkit_text_recognition` | `user_field_values` (persisted mapped outputs) | Improves data entry throughput with user confirmation gate |
| QR session scanner | Pair with active staff session | Controller: `QRScannerController` → Screen: `qr_scanner_screen.dart` → Service: `mobile_scanner` | `form_submission` (session ID target) | Session-bound transmission rather than broadcast sharing |
| Selective payload transmission | Send only chosen fields to staff dashboard | Controller: `ManageInfoController.buildTransmitPayload` (checkbox model) → Widget: `SelectAllButton` | `submission_field_values`, `form_submission` | Data minimization during transfer |
| Hybrid encrypted payload packaging | Protect payload confidentiality in transit | Service: `HybridCryptoService.encryptForTransmission` → Screen: `manage_info_screen.dart` → Service: `SupabaseService.sendDataToWebSession` | `form_submission` (`encrypted_payload`, `payload_iv`, `encrypted_aes_key`, `transmission_version`) | AES/RSA protected transport envelope |
| Client submission history | Review prior finalized submissions | Controller: `HistoryController` → Screen: `HistoryScreen.dart` → Widget: `HistoryCard` → Service: `SupabaseService.fetchClientSubmissionHistoryByUser` | `client_submissions`, `form_submission` | User transparency for historical submissions |
| Profile transparency and consent controls | Review and modify stored profile values | Controller: `ProfileController` → Screen: `ProfileScreen.dart` → Service: save/load via `FieldValueService` | `user_field_values`, `user_accounts` | Supports informed user control over stored PII |

## 3. Validation Notes

1. Mobile traceability should be demonstrated with one complete run: signup or login, profile save, unsaved-changes discard test, InfoScanner-assisted fill, QR transmit, template notification receipt, and history verification.
2. Evidence should include encrypted envelope presence in `form_submission`, encrypted row indicators in `user_field_values`, and form-state fingerprinting in unsaved changes detection.
3. OCR output should be validated as user-confirmed rather than blind auto-commit.
4. Template notifications should be verified as Realtime events received by mobile client with appropriate icons and colors for different change types.

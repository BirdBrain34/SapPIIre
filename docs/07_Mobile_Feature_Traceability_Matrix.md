# 07. Mobile Feature Traceability Matrix

## 1. Scope

This matrix traces mobile-client capabilities to implementation surfaces and data artifacts. It is intended for audience-specific validation of citizen-facing functionality.

## 2. Traceability Matrix

| Mobile Feature | User Intent | Primary Mobile Modules | Primary Tables | Security or Governance Outcome |
| --- | --- | --- | --- | --- |
| Mobile login and authenticated access | Enter existing account and continue profile workflows | `login_screen.dart`, `SupabaseService.login` | `user_accounts` | Blocks deactivated accounts and preserves authenticated session boundary |
| Multi-step signup with verification | Register account and establish verified identity | `signup_screen.dart`, `SupabaseService.signUpWithEmail`, OTP flows | `user_accounts`, `phone_otp` | Multi-factor verification posture for account creation |
| Password recovery and reset | Recover locked or forgotten access | `ChangePassword` flows, `PasswordResetService` | `phone_otp`, `user_accounts` | Reduces account lockout risk while preserving verification controls |
| Dynamic profile capture and edit | Maintain current personal data for form reuse | `manage_info_screen.dart`, `manage_info_controller.dart`, `DynamicFormRenderer` | `user_field_values`, `form_fields` | Structured user-owned PII persistence |
| Encrypted field persistence semantics | Protect sensitive values at rest | `FieldValueService`, `HybridCryptoService` | `user_field_values` (`field_value`, `iv`, `encryption_version`) | Data-at-rest confidentiality model |
| Cross-template semantic fill | Reuse prior profile values across templates | `FieldValueService.loadUserFieldValuesWithCrossFormFill` | `form_fields` (`canonical_field_key`), `user_field_values` | Reduces duplicate entry and mapping drift |
| InfoScanner OCR capture | Accelerate ID-based onboarding and reduce typing | `InfoScannerScreen.dart`, `camera`, `google_mlkit_text_recognition` | `user_field_values` (persisted mapped outputs) | Improves data entry throughput with user confirmation gate |
| QR session scanner | Pair with active staff session | `qr_scanner_screen.dart`, `mobile_scanner` | `form_submission` (session ID target) | Session-bound transmission rather than broadcast sharing |
| Selective payload transmission | Send only chosen fields to staff dashboard | `ManageInfoController.buildTransmitPayload`, checkbox model | `submission_field_values`, `form_submission` | Data minimization during transfer |
| Hybrid encrypted payload packaging | Protect payload confidentiality in transit | `HybridCryptoService.encryptForTransmission`, `SupabaseService.sendDataToWebSession` | `form_submission` (`encrypted_payload`, `payload_iv`, `encrypted_aes_key`, `transmission_version`) | AES/RSA protected transport envelope |
| Client submission history | Review prior finalized submissions | `HistoryScreen.dart`, `SupabaseService.fetchClientSubmissionHistoryByUser` | `client_submissions`, `form_submission` | User transparency for historical submissions |
| Profile transparency and consent controls | Review and modify stored profile values | `ProfileScreen.dart`, save/load services | `user_field_values`, `user_accounts` | Supports informed user control over stored PII |

## 3. Validation Notes

1. Mobile traceability should be demonstrated with one complete run: signup or login, profile save, InfoScanner-assisted fill, QR transmit, and history verification.
2. Evidence should include encrypted envelope presence in `form_submission` and encrypted row indicators in `user_field_values`.
3. OCR output should be validated as user-confirmed rather than blind auto-commit.

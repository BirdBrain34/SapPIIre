# 04. Feature Summary and Documentation Map

## 1. Purpose

This document now serves as the executive summary of implemented capabilities. It provides a high-level synthesis of manuscript-core and extended features, while delegating detailed audience-specific traceability to separate matrix documents.

## 2. High-Level Capability Summary

| Domain | Primary User | Core Objective | Representative Tables |
| --- | --- | --- | --- |
| Mobile Client Layer | Citizen/client user | Capture, protect, and selectively transmit PII for intake | `user_accounts`, `user_field_values`, `form_submission`, `phone_otp` |
| Web Staff Layer | CSWD staff and administrators | Receive secure payloads, manage sessions, finalize records, govern forms and staff | `staff_accounts`, `staff_profiles`, `form_submission`, `client_submissions`, `form_templates`, `dashboard_widget_configs`, `dashboard_card_settings` |
| Security Layer | System-wide | Enforce data-at-rest, data-in-transit, access, verification, and audit controls | `app_rsa_keypairs`, `form_submission`, `phone_otp`, `audit_logs` |

## 3. Manuscript-Core Feature Coverage

1. Mobile PII management (data at rest).
2. Hybrid cryptosystem (AES-256-GCM and RSA-2048 OAEP).
3. QR handshake protocol (mobile to web session channel).
4. Secured autofill engine (Zero-Knowledge Staging: Edge decryption delivers plaintext in-memory to staff dashboard without database persistence).
5. CSWD dashboard operations for intake records.
6. Basic role-based access for protected staff workflows.

## 4. Extended Feature Coverage

1. Dynamic form template builder and runtime rendering.
2. Conditional logic engine and computed-field behavior, including distinct read-only/computed field visuals.
3. InfoScanner OCR-assisted ID extraction.
4. OTP-enabled user and staff security workflows with dedicated Edge Functions; phone OTP dispatched from cloud via `send-phone-otp` Edge Function (Semaphore SMS API) for faster delivery and response validation; incomplete signup retry support prevents orphaned-record lockout.
5. Admin creation, pending approval, and staff lifecycle governance.
6. Display session broadcasting for station-linked screens and customer mirror view rendering.
7. Audit logging and analytics extensions with submission decryption tracking.
8. **Batch decryption optimization**: Applicants screen loads 5-10x faster using `decrypt-submission-batch` Edge Function.
9. **Mobile notification center**: Dedicated NotificationScreen for real-time form template change awareness.
10. **Enhanced dashboard analytics**: Worker drill-down, client search, configurable chart elevation, time-frame filtering, and streamlined chart types.
11. **Read-only field styling**: lock icons and distinct colors now identify immutable or computed fields in dynamic forms.

## 5. Detailed Documentation Map

The detailed breakdown is distributed as follows:

1. [docs/01_QR_Handshake_and_Cryptography.md](docs/01_QR_Handshake_and_Cryptography.md)
2. [docs/02_Database_Security_and_PII_Mapping.md](docs/02_Database_Security_and_PII_Mapping.md)
3. [docs/03_V2_Dynamic_Form_Architecture.md](docs/03_V2_Dynamic_Form_Architecture.md)
4. [docs/05_Mobile_Client_Core_Features.md](docs/05_Mobile_Client_Core_Features.md)
5. [docs/06_Web_CSWD_Staff_Core_Features.md](docs/06_Web_CSWD_Staff_Core_Features.md)
6. [docs/07_Mobile_Feature_Traceability_Matrix.md](docs/07_Mobile_Feature_Traceability_Matrix.md)
7. [docs/08_Web_Feature_Traceability_Matrix.md](docs/08_Web_Feature_Traceability_Matrix.md)
8. [docs/HYBRID_CRYPTO_TEST_DRIVE_GUIDE.md](docs/HYBRID_CRYPTO_TEST_DRIVE_GUIDE.md)

## 6. Evaluation Guidance

For panel defense or manuscript validation, use this summary as an index page, then cite 07 and 08 for evidence-grade feature mapping by target audience.


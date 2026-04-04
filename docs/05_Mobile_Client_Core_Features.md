# 05. Mobile Client Core Features

## 1. Audience and Operational Objective

The mobile application is designed for citizen or client users whose primary objective is to maintain personal profile data and securely transmit selected data to CSWD staff during intake sessions. The mobile tier is therefore user-data centric and privacy-first.

## 2. Core Functional Domains

### 2.1 Account Access and Verification

The mobile identity flow includes:

1. Username-password sign-in for returning users.
2. Multi-step signup with profile completion.
3. Email OTP verification through Supabase Auth pathways.
4. Phone OTP verification persisted in `phone_otp` with expiration windows.
5. Password reset services with email and phone-assisted recovery flows.

This layered entry process aligns user convenience with risk-reduction for account misuse.

### 2.2 PII Capture and Lifecycle Management

The mobile user manages profile fields through dynamic templates and form-state controllers. Data entry supports:

1. Manual profile editing.
2. Persistent storage via field-level save routines.
3. Canonical-field reuse across multiple templates.
4. Explicit field-selection controls for selective transmission.

Persistent PII values are mapped into `user_field_values` by `field_id`, supporting cross-template continuity and downstream autofill consistency.

### 2.3 Encrypted Data-at-Rest Semantics

For protected rows, user field values are persisted with encryption metadata (`iv`, `encryption_version`) and resolved during load workflows through decrypt paths. This provides an at-rest protection layer for sensitive user attributes.

### 2.4 InfoScanner OCR Workflow (Extended Feature)

The InfoScanner module operationalizes ID-assisted onboarding through:

1. Camera capture pipeline.
2. OCR extraction via `google_mlkit_text_recognition`.
3. Front/back ID parsing logic for key identity attributes.
4. User confirmation and save routing to field-value persistence.

This feature reduces manual encoding effort and improves intake throughput while keeping the user in control of final submitted values.

### 2.5 QR Session Transmission and Secure Autofill Trigger

The mobile app performs session-targeted data transmission by:

1. Scanning staff-generated session QR identifiers.
2. Building a filtered payload from user-selected fields.
3. Packaging encrypted envelope artifacts (`encrypted_payload`, `payload_iv`, `encrypted_aes_key`).
4. Updating `form_submission` with transport metadata and scanned status.
5. Triggering backend decryption for web-side autofill readiness.

This is the client-side entry point of the hybrid cryptosystem handshake.

### 2.6 User History and Profile Transparency

The mobile interface includes:

1. Submission history views linked to finalized records.
2. Profile dashboards for reviewing and updating stored identity fields.
3. Session-safe logout and account controls.

These functions improve user transparency regarding what has been submitted and what profile state remains active.

## 3. Security and Privacy Control Surface

The mobile tier contributes the following controls:

1. Selective field transmission rather than blanket payload sharing.
2. Hybrid cryptographic payload packaging before transit.
3. OTP-backed identity verification for sensitive account flows.
4. At-rest protected field persistence model.
5. Timestamped session handoff boundaries through `form_submission` lifecycle states.

## 4. Manuscript Alignment and Added Capabilities

### 4.1 Manuscript-Aligned Mobile Core

1. Mobile PII management for form-ready identity data.
2. Hybrid crypto payload generation for secure transit.
3. QR handshake participation as the mobile transmitter endpoint.

### 4.2 Added Mobile Enhancements Beyond Initial Prompt

1. InfoScanner OCR-assisted profile capture.
2. Extended OTP and password recovery workflows.
3. Cross-template semantic autofill continuity through canonical field handling.

## 5. Primary Data Touchpoints

Mobile workflows interact primarily with:

1. `user_accounts`
2. `user_field_values`
3. `form_submission`
4. `submission_field_values`
5. `phone_otp`

This table footprint reflects the mobile role as secure data producer and controlled transmitter, not final record adjudicator.

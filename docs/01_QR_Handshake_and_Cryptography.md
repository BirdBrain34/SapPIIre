# 01. QR Handshake and Cryptography

## 1. System Scope

The secured autofill channel is implemented as a hybrid cryptographic handshake between the mobile app and the web dashboard session layer. The cryptographic transport path is anchored on the `form_submission` session record and is designed to ensure that form payloads are not transmitted as plaintext while in transit.

### 1.1 Systems Architect View: Mobile -> QR -> Web -> Supabase

The operational data flow follows four bounded stages:

1. Mobile stage: the user curates and confirms PII fields from the mobile dynamic form state.
2. QR stage: the mobile application generates a session handoff artifact (QR-linked session context) for dashboard pairing.
3. Web stage: CSWD dashboard scans or resolves the QR-linked session and binds it to an active intake interface.
4. Supabase stage: encrypted envelope data is written to `form_submission`, decrypted in-memory by Edge Function during request lifecycle, and delivered ephemerally to the dashboard for secure autofill.

This architecture preserves a clean separation between pairing mechanics (QR/session handshake) and payload confidentiality controls (hybrid cryptography).

## 2. Cryptographic Construction

### 2.1 Symmetric Encryption Layer

- Primitive: AES-256-GCM
- Session key size: 32 bytes
- IV size: 12 bytes
- Protected object: JSON payload selected for transmission
- Serialized artifacts: Base64 ciphertext and Base64 IV

### 2.2 Asymmetric Key Encapsulation Layer

- Primitive: RSA-2048 OAEP
- Usage: encrypt the ephemeral AES payload key
- Public key source: database RPC (`get_active_rsa_public_key`)
- Private key source: Edge Function secret (`RSA_PRIVATE_KEY_PEM`), never persisted in user-facing tables

### 2.3 Key Registry Model

The public-key inventory is represented in `app_rsa_keypairs`:

1. `key_version` supports key lifecycle tracking.
2. `is_active` marks the currently consumable public key.
3. `rotated_at` and `created_at` provide cryptographic timeline metadata.
4. `public_key_pem` is distributed through RPC to mobile clients.

This table contains no private key column, enforcing separation between distribution material (public key) and decryption material (secret-managed private key).

### 2.4 Data-At-Rest Key Derivation Model

The data-at-rest path now uses server-side key derivation and ephemeral key delivery, removing the client-side hardcoded secret attack surface. The mobile app fetches AES keys on demand through `derive-field-key`, the Edge Function validates JWT identity and record ownership, and the derived key is kept only in volatile memory on the device. The web dashboard uses `resolve-applicant-names` for server-side decryption of `user_field_values`, so encryption keys never touch the browser.

| Aspect | v1 | v2 |
| --- | --- | --- |
| Key origin | Client-side hardcoded HMAC secret (`_appHmacSecret`) | Server-side derivation via `derive-field-key` Edge Function |
| Secret location | Embedded in mobile binary | Edge Secrets (`FIELD_KEY_HMAC_SECRET_V2`) |
| Identity check | App identity only | JWT validation per request |
| Ownership control | None | Edge Function verifies the requesting user owns the record |
| Key lifetime | Client-managed | Volatile memory only, cleared on logout |
| Browser exposure | Keys could be sent to the browser | Keys never touch the browser |
| Stored version marker | `encryption_version = 1` | `encryption_version = 2` |

This keeps the comparison in one security-focused location while the rest of the docs describe the current model.

## 3. Session-Centric Handshake Flow

### 3.1 Session Initialization

The web tier creates an active session row in `form_submission` with default lifecycle values:

1. `status = active`
2. `expires_at = now() + 30 minutes`
3. `transmission_version = 0` (default)

### 3.2 QR Content Structure

The QR code displayed on the web dashboard no longer contains a raw session UUID. Instead, it encodes a JSON object that binds the session to the currently selected form template:

```json
{
  "sessionId": "uuid-of-form-submission-row",
  "templateId": "uuid-of-selected-form-template"
}
```

This structure enables the mobile client to validate that the scanned QR corresponds to the same form template the mobile user has selected before any data transmission occurs. Legacy QR codes containing only a plain-text UUID continue to be accepted for backward compatibility.

### 3.3 Form Template Validation (Pre-Transmission Guard)

Before any data transmission occurs, the mobile client performs a template match check:

1. Parse the scanned QR content as JSON.
2. Extract the `sessionId` and `templateId` values.
3. Compare the scanned `templateId` against the mobile user's currently selected form template.
4. **If templates match**: proceed with payload encryption and transmission.
5. **If templates mismatch**:
   - Display a warning dialog: *"Form Template Mismatch — This QR code belongs to a different form template than what you currently have selected. Please inform the CSWD staff to switch to the correct form template, then scan again."*
   - Block all data transmission.
   - Re-activate the camera for re-scanning.
6. **Legacy fallback**: If the QR content is not valid JSON (plain-text UUID), the validation passes by default, preserving compatibility with pre-existing QR codes.

This guard prevents the scenario where a mobile user with Form Template A scans a QR generated for Form Template B, which would otherwise result in incorrect field mapping and data corruption in the autofill.

### 3.4 Mobile Payload Packaging

The mobile app assembles user-selected PII payload entries from dynamic form state and canonical mappings, then serializes into JSON.

### 3.5 Envelope Generation

For each transmission event:

1. Generate a fresh AES key.
2. Generate a fresh 12-byte IV.
3. Encrypt payload JSON with AES-GCM.
4. Encrypt AES key with RSA-OAEP public key.

The resulting QR transport envelope semantics are represented by:

1. `encrypted_payload`
2. `payload_iv`
3. `encrypted_aes_key`

### 3.6 Envelope Persistence in `form_submission`

The mobile client updates the targeted active session row with:

1. `encrypted_payload`
2. `payload_iv`
3. `encrypted_aes_key`
4. `transmission_version = 1`
5. `status = scanned`
6. `scanned_at` (UTC timestamp)
7. `user_id` (when available)

### 3.7 Zero-Knowledge Staging: On-Demand Edge Decryption

The system implements "Zero-Knowledge Staging" where decryption occurs strictly in-memory during the request lifecycle. The `serve-submission-for-review` Edge Function executes the following sequence:

1. Validate request method, `sessionId`, and `staffId`.
2. Verify staff authorization (role-based access control, blocking `viewer` role).
3. Fetch the encrypted envelope from `form_submission` where `transmission_version = 1`.
4. Decode private key PEM from Edge secrets (`RSA_PRIVATE_KEY_PEM`).
5. Unwrap AES key via RSA-OAEP (attempts SHA-1 then SHA-256 for compatibility).
6. Import AES key into WebCrypto as AES-GCM key material.
7. Decrypt `encrypted_payload` using `payload_iv` in-memory.
8. Parse decrypted JSON.
9. Return plaintext JSON ephemerally in HTTP response body.
10. Write audit log entry for decryption event.

Critical security guarantee: Plaintext is never written back to the database. The encrypted envelope remains the authoritative storage form.

### 3.8 Web Autofill Activation

The dashboard controller (`ManageFormsController`) invokes on-demand decryption when a session with `status='scanned'` and `transmission_version=1` is detected (indicating an encrypted envelope). The `serve-submission-for-review` Edge Function returns decrypted payload in-memory, which the dashboard hydrates directly into dynamic form controllers, enabling CSWD staff-assisted review and completion. This ephemeral delivery model ensures no plaintext persistence in the database.

## 4. `form_submission` Lifecycle and Security Semantics

The schema-level status domain is:

1. `active`
2. `scanned`
3. `completed`
4. `closed`
5. `expired`

Staff-session governance is handled through the authenticated staff account context that reviews and finalizes the encrypted session record.

`transmission_version` functions as protocol negotiation metadata:

1. `0` indicates non-hybrid/legacy path.
2. `1` indicates hybrid encrypted envelope path.

## 5. IV and Key Handling Controls

1. IVs are random per encryption event and persisted as metadata (`payload_iv` or field-level `iv`).
2. AES session keys are ephemeral and never persisted in plaintext columns.
3. RSA private key material remains confined to Edge secrets.
4. Public key retrieval is runtime-controlled via key registry activation.
5. Key rotation is supported through `app_rsa_keypairs.key_version` and `is_active` toggling.

## 6. Security and Operational Guarantees

1. Confidentiality in transit: only the backend with private key access can decrypt the payload.
2. Integrity-aware payload recovery: AES-GCM decryption failure blocks payload acceptance on modified ciphertext.
3. Bounded session lifetime: default `expires_at` reduces exposure window for abandoned active sessions.
4. Failure observability: reason-coded function responses (`missing_env_vars`, `rsa_decrypt_failed`, `aes_gcm_decrypt_failed`, and others) support diagnostic forensics.

## 7. Core Feature Mapping

The handshake implements manuscript core requirements:

1. Hybrid cryptosystem (AES payload encryption + RSA key encapsulation).
2. QR/session handshake for secure data-in-transit exchange.
3. Secured autofill decryption path through backend function logic.
4. Controlled transition from encrypted session envelope to dashboard-usable form data.
5. **Form template mismatch guard**: Pre-transmission validation on mobile prevents data from being sent to the wrong form template.
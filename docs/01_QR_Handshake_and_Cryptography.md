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

### 2.4 Data-At-Rest Key Derivation (v2 Architecture)

The original v1 architecture derived AES keys client-side using a hardcoded HMAC secret (`_appHmacSecret`), which was vulnerable to reverse-engineering of the mobile binary. The v2 architecture replaces this with a Server-Side Key Derivation model:

- The mobile app fetches AES keys on demand by invoking the `derive-field-key` Edge Function.
- The Edge Function validates the caller's identity via their JWT, derives the AES key using `FIELD_KEY_HMAC_SECRET_V2` (stored in Edge Secrets), and enforces IDOR prevention by verifying the requesting user owns the target record.
- The derived key is returned to the client, cached in volatile memory on the device, and cleared immediately upon logout.
- The web dashboard uses a separate Edge Function (`resolve-applicant-names`) which decrypts `user_field_values` server-side and returns only ephemeral plaintext names — encryption keys never touch the browser.

This eliminates the client-side hardcoded secret attack surface and ensures key material is scoped per-user and per-session.

## 3. Session-Centric Handshake Flow

### 3.1 Session Initialization

The web tier creates an active session row in `form_submission` with default lifecycle values:

1. `status = active`
2. `expires_at = now() + 30 minutes`
3. `transmission_version = 0` (default)

### 3.2 Mobile Payload Packaging

The mobile app assembles user-selected PII payload entries from dynamic form state and canonical mappings, then serializes into JSON.

### 3.3 Envelope Generation

For each transmission event:

1. Generate a fresh AES key.
2. Generate a fresh 12-byte IV.
3. Encrypt payload JSON with AES-GCM.
4. Encrypt AES key with RSA-OAEP public key.

The resulting QR transport envelope semantics are represented by:

1. `encrypted_payload`
2. `payload_iv`
3. `encrypted_aes_key`

### 3.4 Envelope Persistence in `form_submission`

The mobile client updates the targeted active session row with:

1. `encrypted_payload`
2. `payload_iv`
3. `encrypted_aes_key`
4. `transmission_version = 1`
5. `status = scanned`
6. `scanned_at` (UTC timestamp)
7. `user_id` (when available)

### 3.5 Zero-Knowledge Staging: On-Demand Edge Decryption

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

### 3.6 Web Autofill Activation

The dashboard controller (`ManageFormsController`) invokes on-demand decryption when a session with `status='scanned'` and `transmission_version=1` is detected (indicating an encrypted envelope). The `serve-submission-for-review` Edge Function returns decrypted payload in-memory, which the dashboard hydrates directly into dynamic form controllers, enabling CSWD staff-assisted review and completion. This ephemeral delivery model ensures no plaintext persistence in the database.

## 4. `form_submission` Lifecycle and Security Semantics

The schema-level status domain is:

1. `active`
2. `scanned`
3. `completed`
4. `closed`
5. `expired`

`cswd_id` is foreign-keyed to `staff_accounts(cswd_id)`, providing traceable staff-session linkage for operational governance.

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

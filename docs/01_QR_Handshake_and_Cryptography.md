# 01. QR Handshake and Cryptography

## 1. System Scope

The secured autofill channel is implemented as a hybrid cryptographic handshake between the mobile app and the web dashboard session layer. The cryptographic transport path is anchored on the `form_submission` session record and is designed to ensure that form payloads are not transmitted as plaintext while in transit.

### 1.1 Systems Architect View: Mobile -> QR -> Web -> Supabase

The operational data flow follows four bounded stages:

1. Mobile stage: the user curates and confirms PII fields from the mobile dynamic form state.
2. QR stage: the mobile application generates a session handoff artifact (QR-linked session context) for dashboard pairing.
3. Web stage: CSWD dashboard scans or resolves the QR-linked session and binds it to an active intake interface.
4. Supabase stage: encrypted envelope data is written to `form_submission`, decrypted by Edge Function, and materialized into `form_data` for secure autofill.

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

## 3. Session-Centric Handshake Flow

### 3.1 Session Initialization

The web tier creates an active session row in `form_submission` with initial JSON state (`form_data = {}`) and default lifecycle values:

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

### 3.5 Edge Decryption Sequence

The `decrypt-qr-payload` Edge Function executes the following sequence:

1. Validate request method and `sessionId`.
2. Resolve `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and `RSA_PRIVATE_KEY_PEM`.
3. Fetch the encrypted envelope from `form_submission` where `transmission_version = 1`.
4. Decode private key PEM and import key material.
5. Unwrap AES key via RSA-OAEP.
6. Import AES key into WebCrypto as AES-GCM key material.
7. Decrypt `encrypted_payload` using `payload_iv`.
8. Parse decrypted JSON.
9. Update `form_submission.form_data` with decrypted payload.

The implementation includes OAEP hash compatibility attempts to tolerate environment-level key import variance.

### 3.6 Web Autofill Activation

Upon successful decryption, the session record now contains usable `form_data`. The dashboard stream listener hydrates dynamic form controllers, enabling CSWD staff-assisted review and completion.

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

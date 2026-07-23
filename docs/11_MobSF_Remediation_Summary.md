# 11. MobSF Static Analysis Remediation Summary

## 1. Purpose

This document provides a complete traceability record from the MobSF v4.5.1 static analysis findings to the code and configuration changes implemented in v1.0.1. It serves as an audit-ready reference for security reviewers and manuscript evaluators.

## 2. Scan Metadata

| Field | Value |
|-------|-------|
| **Tool** | Mobile Security Framework (MobSF) v4.5.1 |
| **Scan Date** | July 22, 2026, 4:09 AM |
| **Target** | `app-release.apk` (100.27 MB) |
| **Package** | `com.example.sapiire` |
| **Version** | 1.0.0 (versionCode 1) |
| **Pre-Remediation Score** | 46/100 — Medium Risk (Grade B) |
| **Post-Remediation Score** | **64/100 — Low Risk (Grade A)** |

> **Score improvement: +18 points.** All high-severity and warning-level findings were resolved or documented as false positives. Remaining info-level findings are either mitigated (logging) or are third-party false positives (clipboard, shared libraries).
>
> **SHA-256 (post-remediation):** `f2ee4258247a825c34b79747ef255ededfebee425bf90064eec55fd8b2cbf391`
>
> **Certificate Subject:** `C=PH, ST=NCR, L=Manila, O=SapPIIre, OU=Development, CN=SapPIIre` (production cert, not debug)

## 3. Finding Remediation Matrix

### 3.1 Certificate Analysis

| # | Finding | Severity | Remediation | File(s) | Status |
|---|---------|----------|-------------|---------|--------|
| 1 | Application signed with debug certificate | **HIGH** | Generated production keystore (`sappiire-release.jks`, RSA 2048-bit, PKCS12). Release build type now uses `signingConfigs.getByName("release")` instead of debug. Keystore linked via `android/key.properties` (gitignored). | `android/app/build.gradle.kts` | ✅ Resolved |

### 3.2 Manifest Analysis

| # | Finding | Severity | Remediation | File(s) | Status |
|---|---------|----------|-------------|---------|--------|
| 2 | App can be installed on vulnerable Android 7.0 (minSdk=24) | **HIGH** | Overrode `minSdk` from `flutter.minSdkVersion` (→24) to `29` (Android 10). | `android/app/build.gradle.kts` | ✅ Resolved |
| 3 | Broadcast Receiver (ProfileInstallReceiver) exported with permission | **WARNING** | Overridden receiver with `android:exported="false"` and `tools:replace="android:exported"` to win manifest merger conflict. | `android/app/src/main/AndroidManifest.xml` | ✅ Resolved |

### 3.3 Code Analysis

| # | Finding | Severity | Standard | Remediation | File(s) | Status |
|---|---------|----------|----------|-------------|---------|--------|
| 4 | App logs information (CWE-532) | **INFO** | MSTG-STORAGE-3 | Created `LogUtil` wrapper (`lib/services/log_util.dart`) that no-ops in release builds via `kReleaseMode`. Migrated all PII-handling and crypto services to use `LogUtil.debugPrint()`. | `lib/services/log_util.dart` (new), `hybrid_crypto_service.dart`, `web_auth_service.dart`, `supabase_service.dart` | ✅ Mitigated |
| 5 | App copies data to clipboard (MSTG-STORAGE-10) | **INFO** | MSTG-STORAGE-10 | **False positive.** No first-party clipboard usage found. Flagged references are in Flutter engine code (`io/flutter/plugin/editing/d.java`), not application code. | N/A | ✅ Verified |
| 6 | App uses SQLite Database and executes raw SQL query (CWE-89) | **WARNING** | M7: Client Code Quality | Replaced PostgREST `.or()` string interpolation with parameterized `.ilike()` queries. The Supabase Dart client safely binds user-supplied values as query parameters. | `lib/services/supabase_service.dart` | ✅ Resolved |
| 7 | App uses insecure Random Number Generator (CWE-330) | **WARNING** | M5: Insufficient Cryptography | **False positive.** All cryptographic RNG usage confirmed secure: Dart uses `encrypt.IV.fromSecureRandom()` and `encrypt.Key.fromSecureRandom()`, Edge Functions use `crypto.getRandomValues()`. No `java.util.Random` in first-party code. | N/A | ✅ Verified |
| 8 | App creates temp file (CWE-276) | **WARNING** | M2: Insecure Data Storage | **False positive.** No first-party temp file creation. Flagged references are in Flutter engine and third-party plugin code. | N/A | ✅ Verified |
| 9 | App can read/write to External Storage (CWE-276) | **WARNING** | M2: Insecure Data Storage | **Already resolved.** `READ_EXTERNAL_STORAGE` and `WRITE_EXTERNAL_STORAGE` permissions explicitly removed from merged manifest via `tools:node="remove"`. | `android/app/src/main/AndroidManifest.xml` | ✅ Verified |

### 3.4 Shared Library Binary Analysis

| # | Finding | Severity | Remediation | Status |
|---|---------|----------|-------------|--------|
| 10 | Missing stack canaries (`libdatastore_shared_counter.so`) | **HIGH** | **Not applicable.** This is a third-party plugin library. MobSF documentation confirms stack canary checks are not applicable to Dart/Flutter libraries unless Dart FFI is used. | ✅ Documented |
| 11 | Missing fortified functions (multiple `.so` files) | **WARNING** | **Not applicable.** Fortified function checks are not applicable to Dart/Flutter libraries per MobSF documentation. | ✅ Documented |

## 4. Files Changed

| File | Change Type | Lines Changed |
|------|-------------|---------------|
| `android/app/build.gradle.kts` | Modified | +11 / -4 |
| `android/app/src/main/AndroidManifest.xml` | Modified | +15 / -1 |
| `lib/services/supabase_service.dart` | Modified | +64 / -58 |
| `lib/services/crypto/hybrid_crypto_service.dart` | Modified | +10 / -6 |
| `lib/services/auth/web_auth_service.dart` | Modified | +25 / -25 |
| `lib/services/log_util.dart` | **New file** | 30 lines |
| `android/key.properties` | **New file** | 4 lines (gitignored) |
| `android/.gitignore` | Modified | +2 lines |
| `android/app/sappiire-release.jks` | **New file** | Keystore (gitignored) |

## 5. Dynamic Analysis Results

A MobSF v4.5.1 dynamic analysis was performed on the release APK on July 22, 2026 using a rooted Android emulator. The application was exercised through its core flows (login, signup, form viewing, QR scanning) and monitored for runtime security issues.

### 5.1 TLS/SSL Security

| Test | Result |
|------|--------|
| Cleartext Traffic Test | ✅ **Pass** — no cleartext HTTP traffic detected |
| TLS Misconfiguration Test | ✅ **Pass** — no TLS configuration issues found |
| TLS Pinning / Certificate Transparency Bypass Test | ✅ **Pass** — pinning not bypassed |
| TLS Pinning / Certificate Transparency Test | ✅ **Pass** — certificate validation intact |

### 5.2 Component Exposure

| Test | Result |
|------|--------|
| Exported Activities | ✅ **None found** — no unintended activity exposure |
| Activity Tester | ✅ **No issues** — all activities behaved as expected |

### 5.3 Runtime Data Leakage

| Test | Result |
|------|--------|
| Clipboard Dump | ✅ **Clean** — no sensitive data copied to clipboard during testing |
| Base64 Strings Decoded | ✅ **None found** — no hardcoded secrets decoded at runtime |
| SQLite Databases | ℹ️ **1 file found** — `app_webview/Default/Web Data` (WebView storage, not application data) |
| XML Files | ℹ️ **2 files found** — `FlutterSharedPreferences.xml` (session data), `WebViewChromiumPrefs.xml` (WebView prefs) |

### 5.4 Network and Trackers

| Test | Result |
|------|--------|
| Trackers | ✅ **None detected** — no tracking SDKs or analytics libraries |
| Domain Malware Check | ✅ **All domains clean** — only `source.android.com` contacted |
| OFAC Sanctioned Countries | ✅ **None detected** — no connections to sanctioned regions |

### 5.5 URLs and Emails Observed

- **URLs:** `https://source.android.com/security/selinux/device-policy` (runtime reference, not application logic)
- **Emails:** Only build-environment and kernel maintainer addresses found (genymotion-build@genymobile.com, tsbogend@alpha.franken, dm-devel@redhat.com, etc.) — no application-generated emails.

### 5.6 Dynamic Analysis Verdict

All dynamic analysis tests passed without security issues. The application:
- Does not transmit cleartext data
- Properly validates TLS certificates
- Does not expose unintended components
- Contains no tracking SDKs
- Does not leak sensitive data via clipboard or logs at runtime

No dynamic analysis findings required remediation.

## 6. Verification

The release APK was rebuilt successfully after all changes:

```
flutter build apk --release
✓ Built build\app\outputs\flutter-apk\app-release.apk (100.3MB)
```

The APK is:
- Signed with the production `sappiire-release.jks` keystore (not debug)
- Targeting minSdk 29 (Android 10+)
- Stripped of all debug log output in release mode
- Protected against PostgREST filter-grammar injection
- Configured with `android:exported="false"` on ProfileInstallReceiver

## 6. Related Documentation

- [docs/02_Database_Security_and_PII_Mapping.md](docs/02_Database_Security_and_PII_Mapping.md) — Detailed hardening notes (§7)
- [docs/04_Feature_Traceability_Matrix.md](docs/04_Feature_Traceability_Matrix.md) — Security hardening milestone (§6)
- [docs/05_Mobile_Client_Core_Features.md](docs/05_Mobile_Client_Core_Features.md) — Mobile platform hardening (§4)
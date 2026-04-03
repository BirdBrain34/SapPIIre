import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EncryptedValue {
  const EncryptedValue({required this.ciphertext, required this.iv});

  final String ciphertext;
  final String iv;
}

class QRPayloadEnvelope {
  const QRPayloadEnvelope({
    required this.encryptedPayload,
    required this.payloadIv,
    required this.encryptedAesKey,
    required this.transmissionVersion,
  });

  final String encryptedPayload;
  final String payloadIv;
  final String encryptedAesKey;
  final int transmissionVersion;
}

class HybridCryptoService {
  static const String _appHmacSecret =
      'sappiire_aes_v1_cswd_santa_rosa_2025';

  static String? _cachedPublicKey;

  static Uint8List deriveUserAesKey(String userId) {
    final hmac = crypto.Hmac(
      crypto.sha256,
      utf8.encode(_appHmacSecret),
    );
    final digest = hmac.convert(utf8.encode(userId));
    return Uint8List.fromList(digest.bytes);
  }

  static Future<EncryptedValue> encryptField(
    String plaintext,
    Uint8List aesKey,
  ) async {
    final result = await compute(
      _encryptFieldWorker,
      <String, String>{
        'plaintext': plaintext,
        'aesKeyB64': base64Encode(aesKey),
      },
    );

    return EncryptedValue(
      ciphertext: result['ciphertext'] ?? '',
      iv: result['iv'] ?? '',
    );
  }

  static Future<String> decryptField(
    String ciphertext,
    String ivBase64,
    Uint8List aesKey,
  ) async {
    if (ciphertext.trim().isEmpty) {
      return '';
    }

    try {
      return await compute(
        _decryptFieldWorker,
        <String, String>{
          'ciphertextB64': ciphertext,
          'ivB64': ivBase64,
          'aesKeyB64': base64Encode(aesKey),
        },
      );
    } catch (_) {
      return '';
    }
  }

  static Future<List<EncryptedValue>> encryptFieldBatch(
    List<String> plaintexts,
    Uint8List aesKey,
  ) async {
    final result = await compute(
      _encryptFieldBatchWorker,
      <String, dynamic>{
        'plaintexts': plaintexts,
        'aesKeyB64': base64Encode(aesKey),
      },
    );

    return result
        .map(
          (item) => EncryptedValue(
            ciphertext: item['ciphertext'] ?? '',
            iv: item['iv'] ?? '',
          ),
        )
        .toList();
  }

  static Future<List<String>> decryptFieldBatch(
    List<({String ciphertext, String iv})> items,
    Uint8List aesKey,
  ) async {
    try {
      return await compute(
        _decryptFieldBatchWorker,
        <String, dynamic>{
          'ciphertexts': items.map((item) => item.ciphertext).toList(),
          'ivs': items.map((item) => item.iv).toList(),
          'aesKeyB64': base64Encode(aesKey),
        },
      );
    } catch (_) {
      return List<String>.filled(items.length, '');
    }
  }

  static Future<QRPayloadEnvelope> encryptForTransmission(
    Map<String, dynamic> payload,
    String rsaPublicKeyPem,
  ) async {
    final result = await compute(
      _encryptForTransmissionWorker,
      <String, String>{
        'payloadJson': jsonEncode(payload),
        'rsaPublicKeyPem': rsaPublicKeyPem,
      },
    );

    return QRPayloadEnvelope(
      encryptedPayload: result['encryptedPayload'] ?? '',
      payloadIv: result['payloadIv'] ?? '',
      encryptedAesKey: result['encryptedAesKey'] ?? '',
      transmissionVersion: 1,
    );
  }

  static Future<String> fetchAndCacheRsaPublicKey({
    bool forceRefresh = false,
  }) async {
    final cached = _cachedPublicKey;
    if (!forceRefresh && cached != null && cached.trim().isNotEmpty) {
      return cached;
    }

    try {
      final rpcResult = await Supabase.instance.client.rpc(
        'get_active_rsa_public_key',
      );
      final key = _extractPublicKeyFromRpc(rpcResult);
      if (key != null && key.trim().isNotEmpty) {
        _cachedPublicKey = key;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('fetchAndCacheRsaPublicKey error: $e');
      }
    }

    return _cachedPublicKey ?? '';
  }
}

String? _extractPublicKeyFromRpc(dynamic value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  if (value is Map) {
    final candidates = <dynamic>[
      value['get_active_rsa_public_key'],
      value['public_key_pem'],
      value['rsa_public_key_pem'],
      value['public_key'],
      value['key'],
      ...value.values,
    ];
    for (final candidate in candidates) {
      final parsed = _extractPublicKeyFromRpc(candidate);
      if (parsed != null && parsed.isNotEmpty) {
        return parsed;
      }
    }
  }

  if (value is List && value.isNotEmpty) {
    return _extractPublicKeyFromRpc(value.first);
  }

  return null;
}

Map<String, String> _encryptFieldWorker(Map<String, String> input) {
  final keyBytes = base64Decode(input['aesKeyB64'] ?? '');
  final key = encrypt.Key(Uint8List.fromList(keyBytes));
  final iv = encrypt.IV.fromSecureRandom(12);

  final encrypter = encrypt.Encrypter(
    encrypt.AES(key, mode: encrypt.AESMode.gcm),
  );

  final encryptedValue = encrypter.encrypt(
    input['plaintext'] ?? '',
    iv: iv,
  );

  return <String, String>{
    'ciphertext': encryptedValue.base64,
    'iv': iv.base64,
  };
}

String _decryptFieldWorker(Map<String, String> input) {
  final ciphertext = input['ciphertextB64'] ?? '';
  final ivBase64 = input['ivB64'] ?? '';
  if (ciphertext.trim().isEmpty || ivBase64.trim().isEmpty) {
    return '';
  }

  try {
    final keyBytes = base64Decode(input['aesKeyB64'] ?? '');
    final key = encrypt.Key(Uint8List.fromList(keyBytes));
    final iv = encrypt.IV.fromBase64(ivBase64);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.gcm),
    );

    return encrypter.decrypt64(ciphertext, iv: iv);
  } catch (_) {
    return '';
  }
}

List<Map<String, String>> _encryptFieldBatchWorker(Map<String, dynamic> input) {
  final keyBytes = base64Decode(input['aesKeyB64'] as String? ?? '');
  final key = encrypt.Key(Uint8List.fromList(keyBytes));
  final plaintexts = (input['plaintexts'] as List<dynamic>? ?? const [])
      .map((value) => value?.toString() ?? '')
      .toList();

  final encrypter = encrypt.Encrypter(
    encrypt.AES(key, mode: encrypt.AESMode.gcm),
  );

  final results = <Map<String, String>>[];
  for (final plaintext in plaintexts) {
    if (plaintext.isEmpty) {
      results.add(<String, String>{'ciphertext': '', 'iv': ''});
      continue;
    }

    final iv = encrypt.IV.fromSecureRandom(12);
    final encryptedValue = encrypter.encrypt(plaintext, iv: iv);
    results.add(<String, String>{
      'ciphertext': encryptedValue.base64,
      'iv': iv.base64,
    });
  }

  return results;
}

List<String> _decryptFieldBatchWorker(Map<String, dynamic> input) {
  final keyBytes = base64Decode(input['aesKeyB64'] as String? ?? '');
  final key = encrypt.Key(Uint8List.fromList(keyBytes));
  final ciphertexts = (input['ciphertexts'] as List<dynamic>? ?? const [])
      .map((value) => value?.toString() ?? '')
      .toList();
  final ivs = (input['ivs'] as List<dynamic>? ?? const [])
      .map((value) => value?.toString() ?? '')
      .toList();

  final encrypter = encrypt.Encrypter(
    encrypt.AES(key, mode: encrypt.AESMode.gcm),
  );

  final results = <String>[];
  for (var i = 0; i < ciphertexts.length; i++) {
    final ciphertext = ciphertexts[i];
    final ivBase64 = i < ivs.length ? ivs[i] : '';

    if (ciphertext.trim().isEmpty || ivBase64.trim().isEmpty) {
      results.add('');
      continue;
    }

    try {
      final iv = encrypt.IV.fromBase64(ivBase64);
      results.add(encrypter.decrypt64(ciphertext, iv: iv));
    } catch (_) {
      results.add('');
    }
  }

  return results;
}

Map<String, String> _encryptForTransmissionWorker(Map<String, String> input) {
  final payloadJson = input['payloadJson'] ?? '{}';
  final rsaPublicKeyPem = input['rsaPublicKeyPem'] ?? '';

  final ephemeralAesKey = encrypt.Key.fromSecureRandom(32);
  final payloadIv = encrypt.IV.fromSecureRandom(12);

  final payloadEncrypter = encrypt.Encrypter(
    encrypt.AES(ephemeralAesKey, mode: encrypt.AESMode.gcm),
  );
  final encryptedPayload = payloadEncrypter.encrypt(payloadJson, iv: payloadIv);

  final parser = encrypt.RSAKeyParser();
  final rsaPublicKey = parser.parse(rsaPublicKeyPem);
  final rsaEncrypter = encrypt.Encrypter(
    encrypt.RSA(
      publicKey: rsaPublicKey as dynamic,
      encoding: encrypt.RSAEncoding.OAEP,
    ),
  );
  final encryptedAesKey = rsaEncrypter.encryptBytes(ephemeralAesKey.bytes);

  return <String, String>{
    'encryptedPayload': encryptedPayload.base64,
    'payloadIv': payloadIv.base64,
    'encryptedAesKey': encryptedAesKey.base64,
  };
}

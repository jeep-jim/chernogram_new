import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'brand.dart';
import 'core_models.dart';

class CgIdentityBundle {
  final CgProfile profile;
  final List<CgTunnel> tunnels;
  final List<CgContact> contacts;

  const CgIdentityBundle({
    required this.profile,
    required this.tunnels,
    required this.contacts,
  });
}

class CgAccountVault {
  static const _pinSaltKey = 'cg_access_pin_salt_v1';
  static const _pinHashKey = 'cg_access_pin_hash_v1';
  static const _biometricKey = 'cg_access_biometric_v1';
  static const _version = 1;

  static final _random = Random.secure();
  static final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 120000,
    bits: 256,
  );
  static final _cipher = AesGcm.with256bits();

  static Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_pinHashKey) ?? '').isNotEmpty;
  }

  static Future<bool> biometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricKey) ?? false;
  }

  static Future<bool> biometricsAvailable() async {
    try {
      final auth = LocalAuthentication();
      final supported = await auth.isDeviceSupported();
      final enrolled = await auth.getAvailableBiometrics();
      return supported && enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setPin(String pin) async {
    if (pin.length < 4) {
      throw ArgumentError('PIN must contain at least four characters');
    }
    final prefs = await SharedPreferences.getInstance();
    final salt = _randomBytes(16);
    final hash = await _derive(pin, salt);
    await prefs.setString(_pinSaltKey, base64UrlEncode(salt));
    await prefs.setString(_pinHashKey, base64UrlEncode(hash));
  }

  static Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final saltRaw = prefs.getString(_pinSaltKey);
    final hashRaw = prefs.getString(_pinHashKey);
    if (saltRaw == null || hashRaw == null) return true;
    try {
      final salt = base64Url.decode(base64Url.normalize(saltRaw));
      final expected = base64Url.decode(base64Url.normalize(hashRaw));
      final actual = await _derive(pin, salt);
      return _constantTimeEquals(actual, expected);
    } catch (_) {
      return false;
    }
  }

  static Future<void> setBiometricEnabled(bool enabled) async {
    if (enabled && !await biometricsAvailable()) {
      throw StateError('Biometrics are not available');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricKey, enabled);
  }

  static Future<bool> authenticateBiometric({required bool ru}) async {
    try {
      return await LocalAuthentication().authenticate(
        localizedReason: ru
            ? 'Разблокируйте свой Chernogram ID'
            : 'Unlock your Chernogram ID',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clearLocalLock() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pinSaltKey);
    await prefs.remove(_pinHashKey);
    await prefs.remove(_biometricKey);
  }

  static Future<String> exportIdentity({
    required CgProfile profile,
    required List<CgTunnel> tunnels,
    required List<CgContact> contacts,
    required String password,
  }) async {
    if (password.length < 6) {
      throw ArgumentError('Recovery password is too short');
    }
    final payload = utf8.encode(
      jsonEncode({
        'v': _version,
        'profile': profile.toJson(),
        'tunnels': tunnels.map((item) => item.toJson()).toList(),
        'contacts': contacts.map((item) => item.toJson()).toList(),
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final key = await _deriveSecret(password, salt);
    final box = await _cipher.encrypt(
      payload,
      secretKey: key,
      nonce: nonce,
    );
    final envelope = BytesBuilder(copy: false)
      ..addByte(_version)
      ..add(salt)
      ..add(nonce)
      ..add(box.mac.bytes)
      ..add(box.cipherText);
    return 'CG1-${base64UrlEncode(envelope.takeBytes()).replaceAll('=', '')}';
  }

  static Future<CgIdentityBundle> importIdentity({
    required String code,
    required String password,
  }) async {
    final normalized = code.trim().replaceAll(RegExp(r'\s+'), '');
    if (!normalized.startsWith('CG1-')) {
      throw const FormatException('Unsupported Chernogram ID format');
    }
    final raw = base64Url.decode(
      base64Url.normalize(normalized.substring(4)),
    );
    if (raw.length < 46 || raw.first != _version) {
      throw const FormatException('Damaged Chernogram ID');
    }
    final salt = raw.sublist(1, 17);
    final nonce = raw.sublist(17, 29);
    final mac = raw.sublist(29, 45);
    final cipherText = raw.sublist(45);
    final key = await _deriveSecret(password, salt);
    final clear = await _cipher.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: key,
    );
    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! Map) throw const FormatException('Invalid identity data');
    final map = Map<String, dynamic>.from(decoded);
    final profileRaw = map['profile'];
    if (profileRaw is! Map) {
      throw const FormatException('Profile is missing');
    }
    return CgIdentityBundle(
      profile: CgProfile.fromJson(Map<String, dynamic>.from(profileRaw)),
      tunnels: ((map['tunnels'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => CgTunnel.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      contacts: ((map['contacts'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => CgContact.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }

  static Future<List<int>> _derive(String password, List<int> salt) async {
    final key = await _deriveSecret(password, salt);
    return key.extractBytes();
  }

  static Future<SecretKey> _deriveSecret(
    String password,
    List<int> salt,
  ) =>
      _kdf.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      );

  static Uint8List _randomBytes(int length) => Uint8List.fromList(
        List<int>.generate(length, (_) => _random.nextInt(256)),
      );

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var index = 0; index < a.length; index++) {
      difference |= a[index] ^ b[index];
    }
    return difference == 0;
  }
}

class CgAccessGate extends StatefulWidget {
  final bool ru;
  final Widget child;

  const CgAccessGate({
    super.key,
    required this.ru,
    required this.child,
  });

  @override
  State<CgAccessGate> createState() => _CgAccessGateState();
}

class _CgAccessGateState extends State<CgAccessGate> {
  final _pin = TextEditingController();
  bool _checking = true;
  bool _unlocked = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final hasPin = await CgAccountVault.hasPin();
    final biometric = await CgAccountVault.biometricEnabled();
    if (!hasPin && !biometric) {
      if (mounted) setState(() => _unlocked = true);
      return;
    }
    if (mounted) setState(() => _checking = false);
    if (biometric) await _useBiometric();
  }

  Future<void> _useBiometric() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await CgAccountVault.authenticateBiometric(ru: widget.ru);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _unlocked = ok;
      if (!ok) {
        _error = widget.ru
            ? 'Используйте PIN или повторите проверку.'
            : 'Use PIN or retry authentication.';
      }
    });
  }

  Future<void> _unlockWithPin() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await CgAccountVault.verifyPin(_pin.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _unlocked = ok;
      if (!ok) {
        _error = widget.ru ? 'Неверный PIN.' : 'Incorrect PIN.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    if (_checking) {
      return const Scaffold(
        body: Center(child: ChernogramLogo(size: 132)),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: GlassPanel(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ChernogramLogo(size: 104),
                    const SizedBox(height: 18),
                    Text(
                      widget.ru ? 'Ваш Chernogram ID' : 'Your Chernogram ID',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      widget.ru
                          ? 'Локальная защита не передаёт отпечаток, лицо или PIN в сеть.'
                          : 'Local protection never sends your fingerprint, face, or PIN online.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: .56),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _pin,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _unlockWithPin(),
                      decoration: InputDecoration(
                        labelText: 'PIN',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        errorText: _error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _unlockWithPin,
                        icon: const Icon(Icons.login_rounded),
                        label: Text(widget.ru ? 'Открыть' : 'Unlock'),
                      ),
                    ),
                    const SizedBox(height: 9),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _useBiometric,
                        icon: const Icon(Icons.fingerprint_rounded),
                        label: Text(
                          widget.ru
                              ? 'Отпечаток, лицо или код устройства'
                              : 'Fingerprint, face, or device passcode',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }
}

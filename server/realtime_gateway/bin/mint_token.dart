import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) {
    stderr.writeln(
      'Usage: dart run bin/mint_token.dart <profileId> <deviceId> [ttlMinutes]',
    );
    exitCode = 64;
    return;
  }
  final secret = Platform.environment['CG_TOKEN_SECRET']?.trim() ?? '';
  if (secret.length < 32) {
    stderr.writeln('CG_TOKEN_SECRET must contain at least 32 characters.');
    exitCode = 78;
    return;
  }

  final ttlMinutes = int.tryParse(arguments.length > 2 ? arguments[2] : '') ?? 60;
  final expiresAt = DateTime.now().toUtc().add(
        Duration(minutes: ttlMinutes.clamp(1, 10080)),
      );
  final payload = utf8.encode(jsonEncode(<String, dynamic>{
    'profileId': arguments[0],
    'deviceId': arguments[1],
    'exp': expiresAt.millisecondsSinceEpoch ~/ 1000,
  }));
  final mac = await Hmac.sha256().calculateMac(
    payload,
    secretKey: SecretKey(utf8.encode(secret)),
  );
  stdout.writeln(
    '${base64Url.encode(payload).replaceAll('=', '')}.'
    '${base64Url.encode(mac.bytes).replaceAll('=', '')}',
  );
}

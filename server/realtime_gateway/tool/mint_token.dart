import 'dart:io';

import 'package:cernogram_realtime_gateway/src/token.dart';

void main(List<String> arguments) {
  if (arguments.length < 3) {
    stderr.writeln(
      'Usage: dart run tool/mint_token.dart <profileId> <deviceId> '
      '<roomId[,roomId...]> [hours]',
    );
    exitCode = 64;
    return;
  }
  final secret = Platform.environment['CG_GATEWAY_SIGNING_SECRET'] ?? '';
  if (secret.length < 32) {
    stderr.writeln('Set CG_GATEWAY_SIGNING_SECRET to at least 32 characters.');
    exitCode = 64;
    return;
  }
  final rooms = arguments[2]
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet();
  if (rooms.isEmpty) {
    stderr.writeln('At least one room is required.');
    exitCode = 64;
    return;
  }
  final requestedHours =
      int.tryParse(arguments.length > 3 ? arguments[3] : '') ?? 12;
  final hours = requestedHours.clamp(1, 168).toInt();
  final token = GatewayTokenCodec(secret).issue(
    profileId: arguments[0].trim(),
    deviceId: arguments[1].trim(),
    rooms: rooms,
    lifetime: Duration(hours: hours),
  );
  stdout.writeln(token);
}

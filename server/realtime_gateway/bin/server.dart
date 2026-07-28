import 'dart:async';
import 'dart:io';

import 'package:cernogram_realtime_gateway/src/gateway.dart';

Future<void> main() async {
  final environment = Platform.environment;
  final host = environment['CG_HOST']?.trim().isNotEmpty == true
      ? environment['CG_HOST']!.trim()
      : '0.0.0.0';
  final port = int.tryParse(environment['CG_PORT'] ?? '') ?? 8080;
  final dataDirectory = environment['CG_DATA_DIR']?.trim().isNotEmpty == true
      ? environment['CG_DATA_DIR']!.trim()
      : 'data';
  final signingSecret = environment['CG_GATEWAY_SIGNING_SECRET'] ?? '';
  final allowAnonymous =
      (environment['CG_DEV_ALLOW_ANONYMOUS'] ?? '').toLowerCase() == 'true';

  if (signingSecret.length < 32 && !allowAnonymous) {
    stderr.writeln(
      'CG_GATEWAY_SIGNING_SECRET must contain at least 32 characters. '
      'Anonymous development mode is disabled by default.',
    );
    exitCode = 64;
    return;
  }

  final gateway = CernogramGateway(
    GatewayConfig(
      address: InternetAddress(host),
      port: port,
      dataDirectory: Directory(dataDirectory),
      signingSecret: signingSecret,
      allowAnonymousDevelopment: allowAnonymous,
    ),
  );
  await gateway.start();
  stdout.writeln(
    'Cernogram Realtime Gateway listening on $host:$port; '
    'data=$dataDirectory; anonymousDev=$allowAnonymous',
  );

  final shutdown = Completer<void>();
  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  for (final signal in <ProcessSignal>[
    ProcessSignal.sigint,
    ProcessSignal.sigterm,
  ]) {
    if (!signal.isSupported) continue;
    subscriptions.add(
      signal.watch().listen((_) {
        if (!shutdown.isCompleted) shutdown.complete();
      }),
    );
  }

  await shutdown.future;
  stdout.writeln('Stopping Cernogram Realtime Gateway...');
  await gateway.stop();
  for (final subscription in subscriptions) {
    await subscription.cancel();
  }
}

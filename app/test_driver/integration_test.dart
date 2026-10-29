import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Host-side driver: writes screenshots taken in integration tests to
/// $SMOKE_OUT (default ../smoke-out).
Future<void> main() => integrationDriver(
      onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
        final dir = Platform.environment['SMOKE_OUT'] ?? '../smoke-out';
        final f = File('$dir/$name.png');
        f.createSync(recursive: true);
        f.writeAsBytesSync(bytes);
        return true;
      },
    );

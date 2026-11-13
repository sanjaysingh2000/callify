import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class CallAudioPermissions {
  const CallAudioPermissions._();

  static Future<void> requestBluetoothConnect() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    final status = await Permission.bluetoothConnect.request();
    if (!status.isGranted) {
      debugPrint(
        '[CallAudio] Bluetooth connect permission was not granted; '
        'Bluetooth call audio routing may be unavailable.',
      );
    }
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vapi/vapi.dart';

class AiCallProvider extends ChangeNotifier {
  final VapiClient _client = VapiClient('57b0bcf1-b257-4cc0-a83d-c4d457fee3e2');
  VapiCall? _call;
  StreamSubscription? _sub;
  Timer? _timer;

  bool isConnecting = false;
  bool isCalling = false;
  bool isMuted = false;
  int secondsLeft = 120;
  String? errorMessage;

  Future<void> startCall() async {
    if (isCalling || isConnecting) return;

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      errorMessage = 'Microphone permission is required.';
      notifyListeners();
      return;
    }

    try {
      secondsLeft = 120;
      isMuted = false;
      errorMessage = null;
      isConnecting = true;
      notifyListeners();

      _call = await _client.start(
        assistantId: 'f8ff75d7-7347-4eff-a6cc-293008af1502',
        assistantOverrides: {
          'maxDurationSeconds': 120, // server-side hard limit
          'endCallMessage': 'Time is up, thank you. Goodbye!',
        },
      );

      _sub = _call!.onEvent.listen((event) {
        switch (event.label) {
          case 'call-start':
            _onStarted();
            break;
          case 'call-end':
            _cleanup();
            break;
          case 'message':
            debugPrint('${event.value}');
            break;
        }
      });

      // agar listener lagne se pehle hi call active ho chuki ho
      if (_call!.status == VapiCallStatus.active) _onStarted();
    } catch (e) {
      debugPrint('Vapi start error: $e');
      errorMessage = 'Could not connect. Please try again.';
      _cleanup();
    }
  }

  void _onStarted() {
    if (isCalling) return;
    isConnecting = false;
    isCalling = true;
    _startCountdown();
    notifyListeners();
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      secondsLeft--;
      notifyListeners();
      if (secondsLeft <= 0) {
        t.cancel();
        stopCall(); // backup
      }
    });
  }

  Future<void> stopCall() async {
    try {
      await _call?.stop();
    } catch (e) {
      debugPrint('Vapi stop error: $e');
    }
    _cleanup();
  }

  void toggleMute() {
    isMuted = !isMuted;
    _call?.setMuted(isMuted);
    notifyListeners();
  }

  void _cleanup() {
    _timer?.cancel();
    _sub?.cancel();
    _call?.dispose();
    _call = null;
    isConnecting = false;
    isCalling = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    _call?.stop();
    _call?.dispose();
    _client.dispose();
    super.dispose();
  }
}
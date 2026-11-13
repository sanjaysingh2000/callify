import 'package:flutter_test/flutter_test.dart';
import 'package:quick_call/features/call/data/services/livekit_service.dart';

void main() {
  test('LiveKit audio defaults to receiver/headset routing', () {
    final service = LiveKitService();

    expect(service.isSpeakerOn, isFalse);
  });
}

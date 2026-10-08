import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quick_call/features/call/data/datasources/last_call_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LastCallStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = LastCallStore();
  });

  test('returns no last call before a successful call is saved', () async {
    expect(await store.load(), isNull);
  });

  test('persists the last partner and shared room', () async {
    await store.save(partnerId: 'partner-1', roomId: 'room-1');

    final lastCall = await store.load();
    expect(lastCall?.partnerId, 'partner-1');
    expect(lastCall?.roomId, 'room-1');
  });
}

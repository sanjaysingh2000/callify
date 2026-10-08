import 'package:shared_preferences/shared_preferences.dart';

class LastCall {
  const LastCall({required this.partnerId, required this.roomId});

  final String partnerId;
  final String roomId;
}

class LastCallStore {
  static const _partnerIdKey = 'last_call_partner_id';
  static const _roomIdKey = 'last_call_room_id';

  Future<LastCall?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final partnerId = preferences.getString(_partnerIdKey);
    final roomId = preferences.getString(_roomIdKey);
    if (partnerId == null ||
        partnerId.isEmpty ||
        roomId == null ||
        roomId.isEmpty) {
      return null;
    }
    return LastCall(partnerId: partnerId, roomId: roomId);
  }

  Future<void> save({required String partnerId, required String roomId}) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_partnerIdKey, partnerId);
    await preferences.setString(_roomIdKey, roomId);
  }
}

class CallInvitation {
  const CallInvitation({
    required this.id,
    required this.callerId,
    required this.callerName,
    required this.roomId,
    required this.createdAt,
    this.status = 'ringing',
  });

  final String id;
  final String callerId;
  final String callerName;
  final String roomId;
  final DateTime createdAt;
  final String status; // 'ringing' | 'accepted' | 'declined' | 'expired'

  bool get isRinging => status == 'ringing';
  bool get isAccepted => status == 'accepted';
  bool get isDeclined => status == 'declined';
  bool get isExpired =>
      status == 'expired' ||
      DateTime.now().difference(createdAt).inSeconds > 30;
}

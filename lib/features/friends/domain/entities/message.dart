class Message {
  const Message({
    required this.id,
    required this.senderId,
    required this.text,
    required this.createdAt,
    this.read = false,
  });

  final String id;
  final String senderId;
  final String text;
  final DateTime createdAt;
  final bool read;
}

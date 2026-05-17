class ChatMessage {
  final String user;
  final String text;
  final String ts;
  final String? to;

  ChatMessage({
    required this.user,
    required this.text,
    required this.ts,
    this.to,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        user: json['user'] ?? '',
        text: json['text'] ?? '',
        ts: json['ts'] ?? '',
        to: json['to'],
      );

  Map<String, dynamic> toJson() => {
        'user': user,
        'text': text,
        'ts': ts,
        'to': to,
      };

  bool get isSystem => user == '·';
}

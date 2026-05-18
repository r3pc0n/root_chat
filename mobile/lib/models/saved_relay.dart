class SavedRelay {
  final String name;
  final String url;
  final String room;
  final String relayKey;
  final String messageKey;

  const SavedRelay({
    required this.name,
    required this.url,
    required this.room,
    this.relayKey = '',
    this.messageKey = '',
  });

  factory SavedRelay.fromJson(Map<String, dynamic> j) => SavedRelay(
        name: j['name'] as String,
        url: j['url'] as String,
        room: j['room'] as String,
        relayKey: j['relayKey'] as String? ?? '',
        messageKey: j['messageKey'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'room': room,
        'relayKey': relayKey,
        'messageKey': messageKey,
      };
}

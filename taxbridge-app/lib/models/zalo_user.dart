class ZaloUser {
  ZaloUser({required this.zaloId, this.displayName, this.lastSeenAt});

  final String zaloId;
  final String? displayName;
  final DateTime? lastSeenAt;

  factory ZaloUser.fromJson(Map<String, dynamic> j) => ZaloUser(
    zaloId: j['zaloId'] as String,
    displayName: j['displayName'] as String?,
    lastSeenAt: DateTime.tryParse(j['lastSeenAt'] as String? ?? ''),
  );

  String get label => '${displayName ?? 'Zalo user'} - $zaloId';
}

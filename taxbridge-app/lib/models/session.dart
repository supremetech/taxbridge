class AppSession {
  AppSession({
    required this.token,
    required this.accountId,
    required this.businessId,
    required this.username,
    this.zaloId,
  });

  final String token;
  final String accountId;
  final String businessId;
  final String username;
  final String? zaloId;

  factory AppSession.fromJson(Map<String, dynamic> j) => AppSession(
    token: j['token'] as String,
    accountId: j['accountId'] as String,
    businessId: j['businessId'] as String,
    username: j['username'] as String,
    zaloId: j['zaloId'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'token': token,
    'accountId': accountId,
    'businessId': businessId,
    'username': username,
    'zaloId': zaloId,
  };
}

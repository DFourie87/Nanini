class AppUser {
  AppUser({required this.id, required this.username, required this.displayName, required this.role, this.modules = const []});

  final String id;
  final String username;
  final String displayName;
  final String role; // 'admin' | 'staff'

  /// Hub tile keys this account can see -- only meaningful for 'staff';
  /// an admin can see everything regardless of what's in here.
  final List<String> modules;

  bool get isAdmin => role == 'admin';
  bool hasModule(String key) => isAdmin || modules.contains(key);

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        username: j['username'] as String,
        displayName: j['display_name'] as String,
        role: j['role'] as String,
        modules: ((j['modules'] as List?) ?? const []).map((e) => e as String).toList(),
      );

  Map<String, dynamic> toJson() => {'id': id, 'username': username, 'display_name': displayName, 'role': role, 'modules': modules};
}

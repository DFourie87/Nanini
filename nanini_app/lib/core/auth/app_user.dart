class AppUser {
  AppUser({required this.id, required this.username, required this.displayName, required this.role});

  final String id;
  final String username;
  final String displayName;
  final String role; // 'admin' | 'staff'

  bool get isAdmin => role == 'admin';

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        username: j['username'] as String,
        displayName: j['display_name'] as String,
        role: j['role'] as String,
      );

  Map<String, dynamic> toJson() => {'id': id, 'username': username, 'display_name': displayName, 'role': role};
}

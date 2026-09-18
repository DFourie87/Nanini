import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/auth/session.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../core/widgets/toast.dart';

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});
  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  final repo = AuthRepository();
  List<ManagedUser> users = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = context.read<Session>();
    if (session.adminPin == null) {
      setState(() => loading = false);
      return;
    }
    try {
      final list = await repo.listUsers(adminUsername: session.currentUser!.username, adminPin: session.adminPin!);
      if (!mounted) return;
      setState(() { users = list; loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showToast(context, 'Could not load users', isError: true);
    }
  }

  Future<void> _addUser() async {
    final session = context.read<Session>();
    final usernameCtrl = TextEditingController();
    final displayNameCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    String role = 'staff';

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add user'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: displayNameCtrl, decoration: const InputDecoration(labelText: 'Display name')),
              const SizedBox(height: 10),
              TextField(controller: usernameCtrl, decoration: const InputDecoration(labelText: 'Username')),
              const SizedBox(height: 10),
              TextField(controller: pinCtrl, keyboardType: TextInputType.number, obscureText: true, decoration: const InputDecoration(labelText: 'PIN')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'staff', child: Text('Staff')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: (v) => setState(() => role = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (usernameCtrl.text.trim().isEmpty || displayNameCtrl.text.trim().isEmpty || pinCtrl.text.trim().isEmpty) return;
                try {
                  await repo.createUser(
                    adminUsername: session.currentUser!.username,
                    adminPin: session.adminPin!,
                    newUsername: usernameCtrl.text.trim(),
                    displayName: displayNameCtrl.text.trim(),
                    newPin: pinCtrl.text.trim(),
                    role: role,
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Could not create user: username may already be taken')));
                  }
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (created == true) {
      if (mounted) showToast(context, 'User added');
      _load();
    }
  }

  Future<void> _toggleActive(ManagedUser u) async {
    final session = context.read<Session>();
    await repo.setActive(adminUsername: session.currentUser!.username, adminPin: session.adminPin!, targetId: u.id, active: !u.active);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const NaniniAppBar(title: 'Manage users', showManagerButton: false),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                users.isEmpty
                    ? const Center(child: Text('No users yet.'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                        itemCount: users.length,
                        itemBuilder: (context, i) {
                          final u = users[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              title: Text(u.displayName),
                              subtitle: Text('@${u.username} · ${u.role}${u.active ? '' : ' · disabled'}'),
                              trailing: Switch(value: u.active, onChanged: (_) => _toggleActive(u)),
                            ),
                          );
                        },
                      ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.extended(onPressed: _addUser, icon: const Icon(Icons.person_add_alt), label: const Text('Add user')),
                ),
              ],
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../models/zalo_user.dart';
import 'session_notifier.dart';

final _zaloUsersProvider = FutureProvider.autoDispose<List<ZaloUser>>(
  (ref) => ref.watch(apiProvider).unlinkedZaloUsers(),
);

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  String? _zaloId;
  bool _busy = false;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final u = _user.text.trim();
    if (u.isEmpty || _pass.text.isEmpty) {
      showInfo(context, 'Nhập username và password');
      return;
    }
    if (_pass.text != _confirm.text) {
      showInfo(context, 'Mật khẩu nhập lại không khớp');
      return;
    }
    setState(() => _busy = true);
    try {
      final s = await ref.read(apiProvider).register(u, _pass.text, _zaloId);
      await ref.read(sessionProvider.notifier).signIn(s);
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zalo = ref.watch(_zaloUsersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tạo tài khoản'),
        leading: BackButton(onPressed: () => context.go('/login')),
      ),
      body: BusyOverlay(
        busy: _busy,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _user,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            zalo.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('Không tải được danh sách Zalo.'),
              data: (users) => DropdownButtonFormField<String?>(
                initialValue: _zaloId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Zalo account (optional)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Không liên kết Zalo'),
                  ),
                  for (final u in users)
                    DropdownMenuItem<String?>(
                      value: u.zaloId,
                      child: Text(u.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _zaloId = v),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _register,
              child: const Text('Đăng ký'),
            ),
          ],
        ),
      ),
    );
  }
}

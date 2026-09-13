import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/router/app_router.dart';
import 'core/supabase/supabase_client.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(const IYSAppRoot());
}

class IYSAppRoot extends StatefulWidget {
  const IYSAppRoot({super.key});

  @override
  State<IYSAppRoot> createState() => _IYSAppRootState();
}

class _IYSAppRootState extends State<IYSAppRoot> {
  /// Identity of the signed-in user. It keys the [ProviderScope] below, so
  /// when it changes the whole scope — and every cached provider in it — is
  /// thrown away. Without this, one admin's members, sessions and dashboard
  /// data stay in memory and are shown to whoever logs in next.
  String? _userId;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _userId = supabase.auth.currentUser?.id;
    _authSub = supabase.auth.onAuthStateChange.listen((state) {
      final id = state.session?.user.id;
      if (id != _userId && mounted) {
        setState(() => _userId = id);
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-keying on the user id rebuilds the scope from scratch on every
    // login/logout, so no cached data crosses between accounts.
    return ProviderScope(
      key: ValueKey(_userId ?? 'signed-out'),
      child: const IYSApp(),
    );
  }
}

class IYSApp extends StatelessWidget {
  const IYSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'IYS Attendance',
      theme: buildAppTheme(),
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}

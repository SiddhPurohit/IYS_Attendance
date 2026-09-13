import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import '../supabase/supabase_client.dart';

/// Streams Supabase auth state changes.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return supabase.auth.onAuthStateChange;
});

/// The currently authenticated Supabase user (null if logged out).
final currentUserProvider = Provider<User?>((ref) {
  return supabase.auth.currentUser;
});

/// Fetches the profile row for the current user from the `profiles` table.
final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;

  final response = await supabase
      .from('profiles')
      .select()
      .eq('id', user.id)
      .maybeSingle();

  if (response == null) return null;
  return Profile.fromJson(response);
});

/// Sign in with email and password. Returns null on success, or an error message.
Future<String?> signIn(String email, String password) async {
  try {
    await supabase.auth.signInWithPassword(email: email, password: password);
    return null;
  } on AuthException catch (e) {
    return e.message;
  } catch (e) {
    return 'An unexpected error occurred. Please try again.';
  }
}

/// Sign out the current user.
Future<void> signOut() async {
  await supabase.auth.signOut();
}

/// Notifier that listens to Supabase auth changes and can be used as
/// a [Listenable] for go_router's refreshListenable.
class AuthChangeNotifier extends ChangeNotifier {
  StreamSubscription<AuthState>? _subscription;

  AuthChangeNotifier() {
    startListening();
  }

  void startListening() {
    _subscription?.cancel();
    if (isSupabaseInitialized) {
      try {
        _subscription = supabase.auth.onAuthStateChange.listen((_) {
          notifyListeners();
        });
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = "https://bofkbsterhjsypwevelp.supabase.co";
const _supabaseAnonKey = "sb_publishable__MUJJI6yKrwXuxjE-JjSRw_veqT70oz";

/// Checks if Supabase client instance has been initialized.
bool get isSupabaseInitialized {
  try {
    return Supabase.instance.isInitialized;
  } catch (_) {
    return false;
  }
}

/// Global accessor for the Supabase client.
SupabaseClient get supabase => Supabase.instance.client;

/// Initializes the Supabase client with this project's credentials.
Future<void> initSupabase() async {
  if (isSupabaseInitialized) return;
  await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseAnonKey);
}

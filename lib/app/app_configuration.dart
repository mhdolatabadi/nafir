import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class AppConfiguration {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static Future<void> initializeSupabase() async {
    if (!isSupabaseConfigured) return;
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }
}

class AppConfig {
  AppConfig._();

  static const supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  static const authRedirect = String.fromEnvironment('AUTH_REDIRECT',
      defaultValue: 'io.supabase.uniclub://login-callback');
  static bool get isConfigured =>
      supabaseUrl.startsWith('https://') && supabaseAnonKey.isNotEmpty;
}

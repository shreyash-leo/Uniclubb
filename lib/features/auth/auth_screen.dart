import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/validators.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  bool signup = false;
  bool loading = false;
  bool obscure = true;

  SupabaseClient get client => Supabase.instance.client;

  Future<void> submit() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    setState(() => loading = true);
    try {
      if (signup) {
        final result = await client.auth.signUp(
          email: email.text.trim().toLowerCase(),
          password: password.text,
          data: {'full_name': name.text.trim()},
          emailRedirectTo: AppConfig.authRedirect,
        );
        if (result.session == null && mounted) {
          _message('Check your inbox to verify your email, then sign in.');
          setState(() => signup = false);
        }
      } else {
        await client.auth.signInWithPassword(
          email: email.text.trim().toLowerCase(),
          password: password.text,
        );
      }
    } on AuthException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('Authentication failed. Check your connection.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> oauth(OAuthProvider provider) async {
    try {
      await client.auth.signInWithOAuth(
        provider,
        redirectTo: AppConfig.authRedirect,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
    } on AuthException catch (error) {
      if (mounted) _message(error.message);
    }
  }

  Future<void> forgotPassword() async {
    final value = email.text.trim().toLowerCase();
    if (Validators.email(value) != null) {
      _message('Enter your account email first.');
      return;
    }
    try {
      await client.auth.resetPasswordForEmail(
        value,
        redirectTo: AppConfig.authRedirect,
      );
      if (mounted) _message('Password recovery link sent.');
    } on AuthException catch (error) {
      if (mounted) _message(error.message);
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const Icon(Icons.hub_outlined, size: 36),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(signup ? 'Join UniClub' : 'Welcome back',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    Text(signup
                        ? 'Build your campus identity and find your community.'
                        : 'Events, clubs, people and opportunities in one place.'),
                    const SizedBox(height: 28),
                    if (signup) ...[
                      TextFormField(
                        controller: name,
                        validator: (value) =>
                            Validators.requiredField(value, label: 'Name'),
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: email,
                      validator: Validators.email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: password,
                      validator: signup
                          ? Validators.strongPassword
                          : Validators.password,
                      obscureText: obscure,
                      autofillHints: [
                        signup
                            ? AutofillHints.newPassword
                            : AutofillHints.password
                      ],
                      onFieldSubmitted: (_) => loading ? null : submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => obscure = !obscure),
                          icon: Icon(obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                        ),
                      ),
                    ),
                    if (!signup)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: loading ? null : forgotPassword,
                          child: const Text('Forgot password?'),
                        ),
                      ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: loading ? null : submit,
                      child: loading
                          ? const SizedBox.square(
                              dimension: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.5))
                          : Text(signup ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed:
                          loading ? null : () => oauth(OAuthProvider.google),
                      icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                      label: const Text('Continue with Google'),
                    ),
                    if (defaultTargetPlatform == TargetPlatform.iOS ||
                        defaultTargetPlatform == TargetPlatform.macOS) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed:
                            loading ? null : () => oauth(OAuthProvider.apple),
                        icon: const Icon(Icons.apple),
                        label: const Text('Continue with Apple'),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: loading
                          ? null
                          : () => setState(() => signup = !signup),
                      child: Text(signup
                          ? 'Already have an account? Sign in'
                          : 'New here? Create an account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }
}

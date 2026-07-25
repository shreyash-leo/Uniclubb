import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_gate.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

class UniClubApp extends ConsumerWidget {
  const UniClubApp({super.key, this.startupError});

  final Object? startupError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'UniClub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      home: !AppConfig.isConfigured
          ? const _ConfigurationScreen()
          : startupError != null
              ? _StartupErrorScreen(error: startupError!)
              : const AuthGate(),
    );
  }
}

class _ConfigurationScreen extends StatelessWidget {
  const _ConfigurationScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.dns_outlined,
                      size: 64, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 20),
                  Text('Connect Supabase',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 12),
                  const Text(
                    'UniClub v2 is ready. Start it with your public Supabase '
                    'project URL and publishable/anon key. Never place a service-role key in the app.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  const SelectableText(
                    'flutter run '
                    '--dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co '
                    '--dart-define=SUPABASE_ANON_KEY=YOUR_PUBLIC_KEY',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 56),
              const SizedBox(height: 16),
              Text('UniClub could not connect',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('$error', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

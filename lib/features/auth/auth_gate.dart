import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase/uniclub_repository.dart';
import '../main/main_shell.dart';
import 'auth_screen.dart';
import 'account_security_screen.dart';
import 'profile_onboarding_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  int profileRevision = 0;

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      initialData:
          AuthState(AuthChangeEvent.initialSession, auth.currentSession),
      builder: (context, authSnapshot) {
        final session = authSnapshot.data?.session;
        if (session == null) return const AuthScreen();
        if (authSnapshot.data?.event == AuthChangeEvent.passwordRecovery) {
          return const ChangePasswordScreen(recovery: true);
        }
        return FutureBuilder<Map<String, dynamic>?>(
          future: UniClubRepository().profile(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }
            if (profileSnapshot.hasError) {
              return _ProfileLoadError(error: profileSnapshot.error!);
            }
            final profile = profileSnapshot.data;
            final state = profile?['account_state'] as String? ?? 'active';
            final suspendedUntil =
                DateTime.tryParse('${profile?['suspended_until'] ?? ''}');
            final currentlySuspended = state == 'suspended' &&
                (suspendedUntil == null ||
                    suspendedUntil.isAfter(DateTime.now()));
            if (currentlySuspended) {
              return SuspendedAccountScreen(
                reason: profile?['suspension_reason'] as String?,
                until: suspendedUntil,
              );
            }
            if (profile?['onboarding_complete'] != true) {
              return ProfileOnboardingScreen(
                key: ValueKey(profileRevision),
                profile: profile ?? const <String, dynamic>{},
                onComplete: () {
                  if (mounted) setState(() => profileRevision++);
                },
              );
            }
            return const _AppVersionGate();
          },
        );
      },
    );
  }
}

class _AppVersionGate extends StatelessWidget {
  const _AppVersionGate();

  Future<Map<String, dynamic>?> check() async {
    final package = await PackageInfo.fromPlatform();
    final platform = defaultTargetPlatform.name;
    final row = await Supabase.instance.client
        .from('app_versions')
        .select()
        .eq('platform', platform)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return _compare(package.version, '${row['minimum_version']}') < 0
        ? row
        : null;
  }

  static int _compare(String left, String right) {
    final a = left.split('.').map((value) => int.tryParse(value) ?? 0).toList();
    final b =
        right.split('.').map((value) => int.tryParse(value) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final difference = (i < a.length ? a[i] : 0) - (i < b.length ? b[i] : 0);
      if (difference != 0) return difference;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: check(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return _ProfileLoadError(error: snapshot.error!);
        }
        final update = snapshot.data;
        if (update == null) return const MainShell();
        return Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.system_update, size: 64),
                    const SizedBox(height: 16),
                    Text('Update UniClub',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text(
                        '${update['release_notes'] ?? 'A required security and reliability update is available.'}',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: update['store_url'] == null
                          ? null
                          : () => launchUrl(Uri.parse('${update['store_url']}'),
                              mode: LaunchMode.externalApplication),
                      child: const Text('Update now'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProfileLoadError extends StatelessWidget {
  const _ProfileLoadError({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sync_problem_outlined, size: 48),
              const SizedBox(height: 12),
              const Text('Unable to load your account'),
              const SizedBox(height: 8),
              Text('$error', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Supabase.instance.client.auth.signOut(),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SuspendedAccountScreen extends StatelessWidget {
  const SuspendedAccountScreen({super.key, this.reason, this.until});
  final String? reason;
  final DateTime? until;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.gpp_bad_outlined,
                    size: 64, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text('Account suspended',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(reason?.isNotEmpty == true
                    ? reason!
                    : 'Your account is temporarily unavailable. Contact support if you believe this is an error.'),
                if (until != null) ...[
                  const SizedBox(height: 8),
                  Text('Access may resume after ${until!.toLocal()}'),
                ],
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () => Supabase.instance.client.auth.signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

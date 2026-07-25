import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/uniclub_repository.dart';
import '../../core/utils/validators.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, this.recovery = false});
  final bool recovery;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final formKey = GlobalKey<FormState>();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool loading = false;

  Future<void> save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    setState(() => loading = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password.text),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password updated securely.')));
        if (Navigator.canPop(context)) Navigator.pop(context);
      }
    } on AuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.recovery ? 'Reset password' : 'Change password')),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: password,
              obscureText: true,
              validator: Validators.strongPassword,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: confirmation,
              obscureText: true,
              validator: (value) =>
                  value == password.text ? null : 'Passwords do not match',
              decoration: const InputDecoration(labelText: 'Confirm password'),
            ),
            const SizedBox(height: 22),
            ElevatedButton(
              onPressed: loading ? null : save,
              child: Text(loading ? 'Saving…' : 'Update password'),
            ),
          ],
        ),
      ),
    );
  }
}

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final confirmation = TextEditingController();
  bool loading = false;

  Future<void> remove() async {
    if (confirmation.text.trim() != 'DELETE') return;
    setState(() => loading = true);
    try {
      await UniClubRepository().invokeDeleteAccount();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('This permanently deletes your account and personal data.',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
              'Club records required for financial or audit purposes may be anonymized instead of erased. This cannot be undone.'),
          const SizedBox(height: 20),
          TextField(
            controller: confirmation,
            decoration:
                const InputDecoration(labelText: 'Type DELETE to confirm'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: confirmation.text.trim() == 'DELETE' && !loading
                ? remove
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(loading ? 'Deleting…' : 'Delete permanently'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    confirmation.dispose();
    super.dispose();
  }
}

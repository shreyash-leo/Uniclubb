import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/uniclub_repository.dart';
import '../../core/utils/validators.dart';
import '../../shared/widgets.dart';

class ProfileOnboardingScreen extends StatefulWidget {
  const ProfileOnboardingScreen({
    super.key,
    required this.profile,
    required this.onComplete,
  });

  final Map<String, dynamic> profile;
  final VoidCallback onComplete;

  @override
  State<ProfileOnboardingScreen> createState() =>
      _ProfileOnboardingScreenState();
}

class _ProfileOnboardingScreenState extends State<ProfileOnboardingScreen> {
  final repo = UniClubRepository();
  final identityKey = GlobalKey<FormState>();
  final aboutKey = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController username;
  late final TextEditingController department;
  late final TextEditingController year;
  late final TextEditingController bio;
  late final TextEditingController skills;
  late final TextEditingController interests;
  int step = 0;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    name = TextEditingController(text: '${profile['full_name'] ?? ''}');
    username = TextEditingController(text: '${profile['username'] ?? ''}');
    department = TextEditingController(text: '${profile['department'] ?? ''}');
    year = TextEditingController(text: '${profile['academic_year'] ?? ''}');
    bio = TextEditingController(text: '${profile['bio'] ?? ''}');
    skills = TextEditingController(
      text:
          List<String>.from(profile['skills'] as List? ?? const []).join(', '),
    );
    interests = TextEditingController(
      text: List<String>.from(profile['interests'] as List? ?? const [])
          .join(', '),
    );
  }

  List<String> _list(TextEditingController controller) => controller.text
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .take(20)
      .toList(growable: false);

  void next() {
    final valid = switch (step) {
      0 => identityKey.currentState?.validate() ?? false,
      1 => aboutKey.currentState?.validate() ?? false,
      _ => true,
    };
    if (!valid) return;
    if (step < 2) setState(() => step++);
  }

  Future<void> complete() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final fullName = name.text.trim();
      await repo.client.from('profiles').update({
        'full_name': fullName,
        'username': username.text.trim().toLowerCase(),
        'department': department.text.trim(),
        'academic_year': year.text.trim(),
        'bio': bio.text.trim(),
        'skills': _list(skills),
        'interests': _list(interests),
        'onboarding_complete': true,
      }).eq('id', repo.userId);
      await repo.client.auth.updateUser(
        UserAttributes(data: {'full_name': fullName}),
      );
      widget.onComplete();
    } on PostgrestException catch (error) {
      if (!mounted) return;
      final message = error.code == '23505'
          ? 'That username is already taken. Choose another one.'
          : error.message;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      if (error.code == '23505') setState(() => step = 0);
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Set up your profile'),
        actions: [
          TextButton(
            onPressed:
                saving ? null : () => Supabase.instance.client.auth.signOut(),
            child: const Text('Sign out'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: List.generate(
                          3,
                          (index) => Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              height: 4,
                              margin: EdgeInsets.only(
                                right: index == 2 ? 0 : 8,
                              ),
                              decoration: BoxDecoration(
                                color: index <= step
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outlineVariant,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Step ${step + 1} of 3',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: SingleChildScrollView(
                      key: ValueKey(step),
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                      child: switch (step) {
                        0 => _identity(theme),
                        1 => _about(theme),
                        _ => _preview(theme),
                      },
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(
                      top: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (step > 0)
                        OutlinedButton(
                          onPressed:
                              saving ? null : () => setState(() => step--),
                          child: const Text('Back'),
                        ),
                      if (step > 0) const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: saving
                              ? null
                              : step == 2
                                  ? complete
                                  : next,
                          child: saving
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(step == 2 ? 'Finish setup' : 'Continue'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _identity(ThemeData theme) => Form(
        key: identityKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your campus identity', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Help clubs and classmates recognize you.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: name,
              validator: (value) =>
                  Validators.requiredField(value, label: 'Full name'),
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: username,
              validator: Validators.username,
              autocorrect: false,
              textCapitalization: TextCapitalization.none,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixText: '@',
                helperText: 'Letters, numbers and underscores',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: department,
              validator: (value) =>
                  Validators.requiredField(value, label: 'Department'),
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Department or course',
                prefixIcon: Icon(Icons.school_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: year,
              validator: (value) =>
                  Validators.requiredField(value, label: 'Academic year'),
              decoration: const InputDecoration(
                labelText: 'Academic year',
                hintText: 'For example: 2nd year',
                prefixIcon: Icon(Icons.calendar_today_outlined),
              ),
            ),
          ],
        ),
      );

  Widget _about(ThemeData theme) => Form(
        key: aboutKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tell us about you', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'This helps personalize clubs, events and connections.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: bio,
              minLines: 3,
              maxLines: 5,
              maxLength: 240,
              decoration: const InputDecoration(
                labelText: 'Short bio',
                hintText: 'What are you building, learning or exploring?',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: skills,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Skills',
                hintText: 'Flutter, design, public speaking',
                helperText: 'Separate each skill with a comma',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: interests,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Interests',
                hintText: 'Hackathons, robotics, photography',
                helperText: 'Separate each interest with a comma',
              ),
            ),
          ],
        ),
      );

  Widget _preview(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ready to join campus', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'You can change these details later from Settings.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text(
                          name.text.trim().isEmpty
                              ? '?'
                              : name.text.trim()[0].toUpperCase(),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name.text.trim(),
                                style: theme.textTheme.titleLarge),
                            const SizedBox(height: 3),
                            Text(
                              '@${username.text.trim().toLowerCase()}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            Text(
                              '${department.text.trim()} · ${year.text.trim()}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (bio.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(bio.text.trim()),
                  ],
                  if (_list(skills).isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _list(skills)
                          .map((skill) => Chip(label: Text(skill)))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );

  @override
  void dispose() {
    for (final controller in [
      name,
      username,
      department,
      year,
      bio,
      skills,
      interests,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }
}

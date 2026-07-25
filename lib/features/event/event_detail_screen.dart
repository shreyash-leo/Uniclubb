import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase/uniclub_repository.dart';
import '../../shared/notification_action.dart';
import '../../shared/widgets.dart';

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({super.key, required this.event});
  final Map<String, dynamic> event;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  final repo = UniClubRepository();
  Map<String, dynamic>? registration;
  bool loadingRegistration = true;
  Object? registrationError;

  @override
  void initState() {
    super.initState();
    loadRegistration();
  }

  Future<void> loadRegistration() async {
    try {
      final row = await repo.client
          .from('event_registrations')
          .select('*, payments(*)')
          .eq('event_id', widget.event['id'])
          .eq('user_id', repo.userId)
          .maybeSingle();
      if (mounted) {
        setState(() {
          registration = row;
          registrationError = null;
          loadingRegistration = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          registrationError = error;
          loadingRegistration = false;
        });
      }
    }
  }

  Future<void> feedback() async {
    var rating = 5;
    final comment = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Event feedback'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: rating,
                decoration: const InputDecoration(labelText: 'Rating'),
                items: List.generate(
                    5,
                    (index) => DropdownMenuItem(
                        value: index + 1,
                        child: Text('${index + 1} / 5 stars'))),
                onChanged: (value) =>
                    setModalState(() => rating = value ?? rating),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: comment,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Comments'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Submit')),
          ],
        ),
      ),
    );
    if (save == true) {
      await repo.client.from('event_feedback').upsert({
        'event_id': widget.event['id'],
        'user_id': repo.userId,
        'rating': rating,
        'comment': comment.text.trim(),
      }, onConflict: 'event_id,user_id');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Feedback submitted')));
      }
    }
    await disposeTextControllersAfterRoute([comment]);
  }

  Future<void> openCertificate() async {
    final certificate = await repo.client
        .from('certificates')
        .select()
        .eq('event_id', widget.event['id'])
        .eq('user_id', repo.userId)
        .maybeSingle();
    if (certificate == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Certificate is not issued yet.')));
      }
      return;
    }
    final value = '${certificate['certificate_url']}';
    final url = value.startsWith('http')
        ? value
        : await repo.privateFileUrl('certificates', value);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final deadline = DateTime.tryParse('${event['registration_deadline']}');
    final registrationOpen = event['registration_enabled'] != false &&
        (deadline == null || deadline.isAfter(DateTime.now()));
    return Scaffold(
      appBar: AppBar(
        title: Text('${event['title']}'),
        actions: const [NotificationAction()],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          NetworkPicture(
            url: event['flyer_url'] as String?,
            width: double.infinity,
            height: 280,
            borderRadius: 0,
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    Chip(label: Text('${event['event_type']}')),
                    Chip(label: Text('${event['category']}')),
                    if (event['is_paid'] == true)
                      Chip(label: Text('${event['currency']} paid')),
                  ],
                ),
                const SizedBox(height: 10),
                Text('${event['title']}',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 14),
                _Info(Icons.schedule, formatDate(event['starts_at'])),
                _Info(Icons.timelapse, 'Ends ${formatDate(event['ends_at'])}'),
                _Info(Icons.location_on_outlined,
                    '${event['venue_name'] ?? 'TBA'}\n${event['venue_address'] ?? ''}'),
                if (event['capacity'] != null)
                  _Info(Icons.groups_outlined,
                      '${event['capacity']} seats · waitlist ${event['waitlist_enabled'] == true ? 'enabled' : 'disabled'}'),
                if (deadline != null)
                  _Info(Icons.event_busy_outlined,
                      'Register by ${formatDate(deadline)}'),
                const SizedBox(height: 20),
                const SectionHeader('About'),
                const SizedBox(height: 8),
                Text('${event['description'] ?? ''}'),
                const SizedBox(height: 20),
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: repo.client
                      .from('announcements')
                      .stream(primaryKey: ['id'])
                      .eq('event_id', '${event['id']}')
                      .order('published_at', ascending: false),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader('Event announcements'),
                        const SizedBox(height: 8),
                        ...snapshot.data!.map((announcement) => Card(
                              child: ListTile(
                                leading: const Icon(Icons.campaign_outlined),
                                title: Text('${announcement['title']}'),
                                subtitle: Text('${announcement['body']}'),
                              ),
                            )),
                      ],
                    );
                  },
                ),
                _JsonSection(title: 'Agenda', value: event['agenda']),
                _JsonSection(title: 'Speakers', value: event['speakers']),
                _JsonSection(title: 'Guests', value: event['guests']),
                _JsonSection(title: 'Sponsors', value: event['sponsors']),
                const SizedBox(height: 24),
                if (loadingRegistration)
                  const Center(child: CircularProgressIndicator())
                else if (registrationError != null)
                  AsyncErrorState(
                    error: registrationError,
                    onRetry: () {
                      setState(() => loadingRegistration = true);
                      loadRegistration();
                    },
                  )
                else if (registration != null) ...[
                  Row(
                    children: [
                      const Text('Your registration'),
                      const Spacer(),
                      StatusChip('${registration!['status']}'),
                    ],
                  ),
                  if (registration!['status'] == 'approved' ||
                      registration!['status'] == 'checked_in' ||
                      registration!['status'] == 'completed') ...[
                    const SizedBox(height: 16),
                    Center(
                      child: QrImageView(
                        data: '${registration!['qr_token']}',
                        size: 190,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const Center(
                        child: Text('Present this code at event check-in')),
                  ],
                  if (registration!['payments'] is List &&
                      (registration!['payments'] as List).isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Builder(builder: (context) {
                      final payment = Map<String, dynamic>.from(
                          (registration!['payments'] as List).first as Map);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: Text(
                            'Invoice ${payment['invoice_number'] ?? 'pending'}'),
                        subtitle: Text(
                            '${payment['currency']} ${payment['amount']} · ${payment['status']}'),
                        onTap: payment['invoice_url'] == null
                            ? null
                            : () => launchUrl(
                                Uri.parse('${payment['invoice_url']}'),
                                mode: LaunchMode.externalApplication),
                      );
                    }),
                  ],
                  if (registration!['status'] == 'completed') ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                            onPressed: feedback,
                            icon: const Icon(Icons.rate_review_outlined),
                            label: const Text('Feedback')),
                        OutlinedButton.icon(
                            onPressed: openCertificate,
                            icon: const Icon(Icons.workspace_premium_outlined),
                            label: const Text('Certificate')),
                      ],
                    ),
                  ],
                ] else if (registrationOpen)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                EventRegistrationScreen(event: event),
                          ),
                        );
                        await loadRegistration();
                      },
                      icon: const Icon(Icons.how_to_reg_outlined),
                      label: const Text('Register'),
                    ),
                  )
                else
                  const StatusChip('Registration closed'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _JsonSection extends StatelessWidget {
  const _JsonSection({required this.title, required this.value});
  final String title;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    if (value is! List || (value as List).isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title),
          const SizedBox(height: 6),
          ...(value as List).map((item) => Card(
                child: ListTile(
                  leading: const Icon(Icons.circle, size: 10),
                  title: Text(item is Map
                      ? '${item['title'] ?? item['name'] ?? item.values.first}'
                      : '$item'),
                  subtitle: item is Map &&
                          (item['description'] ?? item['time']) != null
                      ? Text('${item['description'] ?? item['time']}')
                      : null,
                ),
              )),
        ],
      ),
    );
  }
}

class EventRegistrationScreen extends StatefulWidget {
  const EventRegistrationScreen({super.key, required this.event});
  final Map<String, dynamic> event;

  @override
  State<EventRegistrationScreen> createState() =>
      _EventRegistrationScreenState();
}

class _EventRegistrationScreenState extends State<EventRegistrationScreen> {
  final repo = UniClubRepository();
  final formKey = GlobalKey<FormState>();
  final answers = <String, dynamic>{};
  final teamName = TextEditingController();
  final teamSize = TextEditingController();
  final teamMembers = <_TeamMemberInput>[];
  List<Map<String, dynamic>> tickets = [];
  String? ticketId;
  bool loading = true;
  bool submitting = false;
  Object? loadError;

  List<dynamic> get schema => widget.event['registration_schema'] is List
      ? widget.event['registration_schema'] as List
      : const [];

  @override
  void initState() {
    super.initState();
    loadTickets();
  }

  Future<void> loadTickets() async {
    try {
      tickets = List<Map<String, dynamic>>.from(await repo.client
          .from('event_ticket_types')
          .select()
          .eq('event_id', widget.event['id'])
          .eq('active', true));
      if (tickets.isNotEmpty) ticketId = '${tickets.first['id']}';
      if (mounted) {
        setState(() {
          loadError = null;
          loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          loadError = error;
          loading = false;
        });
      }
    }
  }

  Future<void> submit() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    setState(() => submitting = true);
    try {
      final matchingTickets =
          tickets.where((item) => '${item['id']}' == ticketId);
      final ticket = matchingTickets.isEmpty ? null : matchingTickets.first;
      final price = num.tryParse('${ticket?['price'] ?? 0}') ?? 0;
      final row = await repo.client
          .from('event_registrations')
          .insert({
            'event_id': widget.event['id'],
            'user_id': repo.userId,
            'ticket_type_id': ticketId,
            'answers': answers,
            'team_name':
                teamName.text.trim().isEmpty ? null : teamName.text.trim(),
            'amount_due': price,
            'payment_status': price > 0 ? 'pending' : 'paid',
          })
          .select()
          .single();
      if (widget.event['registration_type'] == 'team' &&
          teamMembers.isNotEmpty) {
        await repo.client.from('registration_members').insert(
              teamMembers
                  .map((member) => {
                        'registration_id': row['id'],
                        'name': member.name.text.trim(),
                        'email': member.email.text.trim().toLowerCase(),
                        'role': 'member',
                      })
                  .toList(),
            );
      }
      if (price > 0) {
        final response = await repo.client.functions.invoke(
          'create-checkout',
          body: {'registration_id': row['id']},
        );
        final checkoutUrl =
            (response.data as Map<String, dynamic>?)?['checkout_url'];
        if (checkoutUrl is String) {
          await launchUrl(Uri.parse(checkoutUrl),
              mode: LaunchMode.externalApplication);
        }
      }
      if (mounted) Navigator.pop(context);
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Event registration')),
      body: loadError != null
          ? AsyncErrorState(
              error: loadError,
              onRetry: () {
                setState(() => loading = true);
                loadTickets();
              },
            )
          : loading
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (tickets.isNotEmpty)
                        DropdownButtonFormField<String>(
                          initialValue: ticketId,
                          decoration:
                              const InputDecoration(labelText: 'Ticket type'),
                          items: tickets
                              .map((ticket) => DropdownMenuItem(
                                    value: '${ticket['id']}',
                                    child: Text(
                                        '${ticket['name']} · ${widget.event['currency']} ${ticket['price']}'),
                                  ))
                              .toList(),
                          onChanged: (value) => ticketId = value,
                        ),
                      if (tickets.isNotEmpty) const SizedBox(height: 14),
                      if (widget.event['registration_type'] == 'team') ...[
                        TextFormField(
                          controller: teamName,
                          decoration:
                              const InputDecoration(labelText: 'Team name'),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Team name is required'
                                  : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: teamSize,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Number of team members',
                            helperText:
                                '${widget.event['team_size_min'] ?? 2}–${widget.event['team_size_max'] ?? 4} members',
                          ),
                          validator: (value) {
                            final parsed = int.tryParse(value ?? '');
                            final minimum =
                                (widget.event['team_size_min'] as num?)
                                        ?.toInt() ??
                                    2;
                            final maximum =
                                (widget.event['team_size_max'] as num?)
                                        ?.toInt() ??
                                    4;
                            return parsed == null ||
                                    parsed < minimum ||
                                    parsed > maximum
                                ? 'Enter a team size from $minimum to $maximum'
                                : null;
                          },
                          onChanged: (value) {
                            answers['team_size'] = value;
                            final size = int.tryParse(value) ?? 1;
                            final needed = size > 1 ? size - 1 : 0;
                            setState(() {
                              while (teamMembers.length < needed) {
                                teamMembers.add(_TeamMemberInput());
                              }
                              while (teamMembers.length > needed) {
                                teamMembers.removeLast().dispose();
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                        ...teamMembers.asMap().entries.map((entry) => Card(
                              margin: const EdgeInsets.only(bottom: 14),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Team member ${entry.key + 2}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      controller: entry.value.name,
                                      decoration: const InputDecoration(
                                          labelText: 'Full name'),
                                      validator: (value) =>
                                          value == null || value.trim().isEmpty
                                              ? 'Name is required'
                                              : null,
                                    ),
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      controller: entry.value.email,
                                      keyboardType: TextInputType.emailAddress,
                                      decoration: const InputDecoration(
                                          labelText: 'Email'),
                                      validator: (value) =>
                                          value == null || !value.contains('@')
                                              ? 'Valid email is required'
                                              : null,
                                    ),
                                  ],
                                ),
                              ),
                            )),
                      ],
                      ...schema.map((raw) {
                        final field = Map<String, dynamic>.from(raw as Map);
                        final key = '${field['key'] ?? field['label']}';
                        final label = '${field['label'] ?? key}';
                        final type = '${field['type'] ?? 'text'}';
                        final required = field['required'] == true;
                        if (type == 'select' && field['options'] is List) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: DropdownButtonFormField<String>(
                              decoration: InputDecoration(labelText: label),
                              validator: (value) => required && value == null
                                  ? '$label is required'
                                  : null,
                              items: (field['options'] as List)
                                  .map((option) => DropdownMenuItem(
                                      value: '$option', child: Text('$option')))
                                  .toList(),
                              onChanged: (value) => answers[key] = value,
                            ),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: TextFormField(
                            keyboardType: type == 'number'
                                ? TextInputType.number
                                : type == 'phone'
                                    ? TextInputType.phone
                                    : TextInputType.text,
                            decoration: InputDecoration(labelText: label),
                            validator: (value) => required &&
                                    (value == null || value.trim().isEmpty)
                                ? '$label is required'
                                : null,
                            onChanged: (value) => answers[key] = value,
                          ),
                        );
                      }),
                      ElevatedButton(
                        onPressed: submitting ? null : submit,
                        child: Text(
                            submitting ? 'Submitting…' : 'Submit registration'),
                      ),
                    ],
                  ),
                ),
    );
  }

  @override
  void dispose() {
    teamName.dispose();
    teamSize.dispose();
    for (final member in teamMembers) {
      member.dispose();
    }
    super.dispose();
  }
}

class _TeamMemberInput {
  final name = TextEditingController();
  final email = TextEditingController();

  void dispose() {
    name.dispose();
    email.dispose();
  }
}

import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/uniclub_repository.dart';
import '../../shared/event_post_card.dart';
import '../../shared/widgets.dart';
import 'event_detail_screen.dart';

class EventManagementScreen extends StatefulWidget {
  const EventManagementScreen(
      {super.key, required this.club, required this.canManage});
  final Map<String, dynamic> club;
  final bool canManage;

  @override
  State<EventManagementScreen> createState() => _EventManagementScreenState();
}

class _EventManagementScreenState extends State<EventManagementScreen> {
  final repo = UniClubRepository();

  Future<void> deleteEvent(Map<String, dynamic> event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete event?'),
        content: Text(
            '${event['title']} and its registrations and attendance will be permanently deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await repo.client.from('events').delete().eq('id', event['id']);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  Future<void> toggleRegistration(Map<String, dynamic> event) async {
    try {
      final enabled = event['registration_enabled'] != false;
      await repo.client
          .from('events')
          .update({'registration_enabled': !enabled}).eq('id', event['id']);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  Future<void> announceEvent(Map<String, dynamic> event) async {
    final title = TextEditingController();
    final body = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Event announcement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 12),
            TextField(
                controller: body,
                minLines: 3,
                maxLines: 7,
                decoration: const InputDecoration(labelText: 'Message')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Publish')),
        ],
      ),
    );
    try {
      if (accepted == true &&
          title.text.trim().isNotEmpty &&
          body.text.trim().isNotEmpty) {
        await repo.client.from('announcements').insert({
          'club_id': widget.club['id'],
          'event_id': event['id'],
          'author_id': repo.userId,
          'title': title.text.trim(),
          'body': body.text.trim(),
          'published_at': DateTime.now().toIso8601String(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Event announcement published')));
        }
      }
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
    await disposeTextControllersAfterRoute([title, body]);
  }

  Future<List<Map<String, dynamic>>> load() async =>
      List<Map<String, dynamic>>.from(await repo.client
          .from('events')
          .select()
          .eq('club_id', widget.club['id'])
          .order('starts_at', ascending: false));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: widget.canManage
          ? FloatingActionButton.extended(
              heroTag: 'event-management-create',
              onPressed: () async {
                await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) =>
                            CreateAdvancedEventScreen(club: widget.club)));
                setState(() {});
              },
              icon: const Icon(Icons.add),
              label: const Text('Event'),
            )
          : null,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: load(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AsyncErrorState(error: snapshot.error);
          }
          if (!snapshot.hasData) {
            return const SkeletonList();
          }
          if (snapshot.data!.isEmpty) {
            return const EmptyState(
                icon: Icons.event_outlined, title: 'No events yet');
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final event = snapshot.data![index];
              final eventWithClub = {...event, 'clubs': widget.club};
              return EventPostCard(
                event: eventWithClub,
                status: '${event['status']}',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => EventDetailScreen(event: eventWithClub),
                  ),
                ),
                headerTrailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'details') {
                      Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => EventDetailScreen(event: event)));
                    } else if (value == 'registrations') {
                      Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) =>
                                  RegistrationAdminScreen(event: event)));
                    } else if (value == 'attendance') {
                      Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) =>
                                  AttendanceAdminScreen(event: event)));
                    } else if (value == 'announcement') {
                      await announceEvent(event);
                    } else if (value == 'registration_toggle') {
                      await toggleRegistration(event);
                    } else if (value == 'delete') {
                      await deleteEvent(event);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'details', child: Text('Details')),
                    if (widget.canManage)
                      PopupMenuItem(
                          value: 'registration_toggle',
                          child: Text(event['registration_enabled'] == false
                              ? 'Turn registration on'
                              : 'Turn registration off')),
                    if (widget.canManage)
                      const PopupMenuItem(
                          value: 'registrations', child: Text('Registrations')),
                    if (widget.canManage)
                      const PopupMenuItem(
                          value: 'attendance', child: Text('Attendance')),
                    if (widget.canManage)
                      const PopupMenuItem(
                          value: 'announcement',
                          child: Text('Event announcement')),
                    if (widget.canManage)
                      const PopupMenuItem(
                          value: 'delete', child: Text('Delete event')),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class CreateAdvancedEventScreen extends StatefulWidget {
  const CreateAdvancedEventScreen({super.key, required this.club});
  final Map<String, dynamic> club;

  @override
  State<CreateAdvancedEventScreen> createState() =>
      _CreateAdvancedEventScreenState();
}

class _CreateAdvancedEventScreenState extends State<CreateAdvancedEventScreen> {
  final repo = UniClubRepository();
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController();
  final description = TextEditingController();
  final venue = TextEditingController();
  final address = TextEditingController();
  final capacity = TextEditingController();
  final ticketPrice = TextEditingController(text: '0');
  final paymentNote = TextEditingController();
  final speakers = TextEditingController();
  final guests = TextEditingController();
  final sponsors = TextEditingController();
  final agenda = TextEditingController();
  final customQuestions = TextEditingController();
  DateTime starts = DateTime.now().add(const Duration(days: 7));
  DateTime ends = DateTime.now().add(const Duration(days: 7, hours: 3));
  DateTime deadline = DateTime.now().add(const Duration(days: 6));
  String eventType = 'event';
  String category = 'Tech';
  String approval = 'manual';
  bool waitlist = true;
  bool paid = false;
  bool registrationEnabled = false;
  String registrationType = 'none';
  int teamMin = 2;
  int teamMax = 4;
  XFile? flyer;
  bool loading = false;

  Future<DateTime?> pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  List<Map<String, String>> lines(TextEditingController controller) =>
      controller.text
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .map((line) => {'title': line})
          .toList();

  Future<void> create() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    if (!ends.isAfter(starts) ||
        (registrationEnabled && deadline.isAfter(starts))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Check the start, end and registration dates.')));
      return;
    }
    setState(() => loading = true);
    try {
      String? flyerUrl;
      if (flyer != null) {
        flyerUrl = await repo.upload(
          bucket: 'event-media',
          bytes: await flyer!.readAsBytes(),
          extension: flyer!.name.split('.').last,
          folder: '${widget.club['id']}/flyers',
        );
      }
      final slug = title.text
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      final event = await repo.client
          .from('events')
          .insert({
            'club_id': widget.club['id'],
            'title': title.text.trim(),
            'slug': '$slug-${DateTime.now().millisecondsSinceEpoch}',
            'description': description.text.trim(),
            'category': category,
            'event_type': eventType,
            'venue_name': venue.text.trim(),
            'venue_address': address.text.trim(),
            'flyer_url': flyerUrl,
            'starts_at': starts.toUtc().toIso8601String(),
            'ends_at': ends.toUtc().toIso8601String(),
            'registration_deadline': deadline.toUtc().toIso8601String(),
            'registration_enabled': registrationEnabled,
            'registration_type': registrationType,
            'team_size_min': registrationType == 'team' ? teamMin : 1,
            'team_size_max': registrationType == 'team' ? teamMax : 1,
            'capacity': int.tryParse(capacity.text),
            'waitlist_enabled': waitlist,
            'approval_mode': approval,
            'is_paid': paid,
            'payment_note': paymentNote.text.trim(),
            'agenda': lines(agenda),
            'speakers': lines(speakers),
            'guests': lines(guests),
            'sponsors': lines(sponsors),
            'feedback_schema': [
              {
                'key': 'rating',
                'label': 'Overall rating',
                'type': 'rating',
                'required': true
              },
              {
                'key': 'comments',
                'label': 'Comments',
                'type': 'long_text',
                'required': false
              }
            ],
            'registration_schema': [
              {
                'key': 'phone',
                'label': 'Contact number',
                'type': 'phone',
                'required': true
              },
              {
                'key': 'department',
                'label': 'Department / year',
                'type': 'text',
                'required': true
              },
              ...customQuestions.text
                  .split('\n')
                  .map((value) => value.trim())
                  .where((value) => value.isNotEmpty)
                  .toList()
                  .asMap()
                  .entries
                  .map((entry) => {
                        'key': 'custom_${entry.key + 1}',
                        'label': entry.value,
                        'type': 'text',
                        'required': true,
                      }),
            ],
            'status': 'published',
            'created_by': repo.userId,
          })
          .select()
          .single();
      if (registrationEnabled) {
        await repo.client.from('event_ticket_types').insert({
          'event_id': event['id'],
          'name': 'General',
          'description': paymentNote.text.trim(),
          'price': paid ? double.tryParse(ticketPrice.text) ?? 0 : 0,
          'capacity': int.tryParse(capacity.text),
        });
      }
      if (mounted) Navigator.pop(context);
    } on PostgrestException catch (error) {
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
      appBar: AppBar(title: const Text('Create event')),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: title,
              validator: _required,
              decoration: const InputDecoration(labelText: 'Event title'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: eventType,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      'event',
                      'hackathon',
                      'competition',
                      'workshop',
                      'meetup'
                    ]
                        .map((item) => DropdownMenuItem(
                            value: item,
                            child: Text(item, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (value) => eventType = value ?? eventType,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: const [
                      'Tech',
                      'Cultural',
                      'Sports',
                      'Academic',
                      'Social',
                      'Entrepreneurship'
                    ]
                        .map((item) => DropdownMenuItem(
                            value: item,
                            child: Text(item, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (value) => category = value ?? category,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: description,
              minLines: 4,
              maxLines: 8,
              validator: _required,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 12),
            TextFormField(
                controller: venue,
                validator: _required,
                decoration: const InputDecoration(labelText: 'Venue')),
            const SizedBox(height: 12),
            TextFormField(
                controller: address,
                decoration: const InputDecoration(
                    labelText: 'Venue address / map reference')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final value = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                    imageQuality: 82,
                    maxWidth: 2200);
                if (value != null) setState(() => flyer = value);
              },
              icon: const Icon(Icons.image_outlined),
              label: Text(flyer?.name ?? 'Choose event flyer'),
            ),
            const SizedBox(height: 12),
            _DateTile(
              label: 'Starts',
              value: starts,
              onTap: () async {
                final value = await pickDateTime(starts);
                if (value != null) setState(() => starts = value);
              },
            ),
            _DateTile(
              label: 'Ends',
              value: ends,
              onTap: () async {
                final value = await pickDateTime(ends);
                if (value != null) setState(() => ends = value);
              },
            ),
            _DateTile(
              label: 'Registration deadline',
              value: deadline,
              onTap: () async {
                final value = await pickDateTime(deadline);
                if (value != null) setState(() => deadline = value);
              },
            ),
            TextFormField(
              controller: capacity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Capacity'),
            ),
            const SizedBox(height: 12),
            const SectionHeader('Registration mode'),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                    value: 'none',
                    icon: Icon(Icons.block_outlined),
                    label: Text('None')),
                ButtonSegment(
                    value: 'solo',
                    icon: Icon(Icons.person_outline),
                    label: Text('Solo')),
                ButtonSegment(
                    value: 'team',
                    icon: Icon(Icons.groups_outlined),
                    label: Text('Team')),
              ],
              selected: {registrationType},
              onSelectionChanged: (value) => setState(() {
                registrationType = value.first;
                registrationEnabled = registrationType != 'none';
                if (!registrationEnabled) paid = false;
              }),
            ),
            if (registrationEnabled) ...[
              if (registrationType == 'team') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: teamMin,
                        decoration:
                            const InputDecoration(labelText: 'Minimum team'),
                        items: List.generate(
                            9,
                            (index) => DropdownMenuItem(
                                value: index + 2, child: Text('${index + 2}'))),
                        onChanged: (value) => setState(() {
                          teamMin = value ?? 2;
                          if (teamMax < teamMin) teamMax = teamMin;
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: teamMax,
                        decoration:
                            const InputDecoration(labelText: 'Maximum team'),
                        items: List.generate(
                            19,
                            (index) => DropdownMenuItem(
                                value: index + 2, child: Text('${index + 2}'))),
                        onChanged: (value) =>
                            setState(() => teamMax = value ?? teamMax),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: approval,
                decoration:
                    const InputDecoration(labelText: 'Approval workflow'),
                items: const [
                  DropdownMenuItem(
                      value: 'manual', child: Text('Manual approval')),
                  DropdownMenuItem(
                      value: 'automatic', child: Text('Auto approval')),
                ],
                onChanged: (value) => approval = value ?? approval,
              ),
              SwitchListTile(
                  title: const Text('Waiting list'),
                  value: waitlist,
                  onChanged: (value) => setState(() => waitlist = value)),
              SwitchListTile(
                  title: const Text('Paid event'),
                  value: paid,
                  onChanged: (value) => setState(() => paid = value)),
              if (paid) ...[
                TextFormField(
                  controller: ticketPrice,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Price',
                    prefixText: '₹ ',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: paymentNote,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Payment note',
                    hintText: 'Payment instructions or important information',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: customQuestions,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Registration form questions',
                  helperText: 'One required question per line',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
                controller: agenda,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                    labelText: 'Agenda (one item per line)')),
            const SizedBox(height: 12),
            TextFormField(
                controller: speakers,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                    labelText: 'Speakers (one per line)')),
            const SizedBox(height: 12),
            TextFormField(
                controller: guests,
                minLines: 2,
                maxLines: 5,
                decoration:
                    const InputDecoration(labelText: 'Guests (one per line)')),
            const SizedBox(height: 12),
            TextFormField(
                controller: sponsors,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                    labelText: 'Sponsors (one per line)')),
            const SizedBox(height: 20),
            ElevatedButton(
                onPressed: loading ? null : create,
                child: Text(loading ? 'Publishing…' : 'Publish event')),
          ],
        ),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  @override
  void dispose() {
    for (final controller in [
      title,
      description,
      venue,
      address,
      capacity,
      ticketPrice,
      paymentNote,
      speakers,
      guests,
      sponsors,
      agenda,
      customQuestions
    ]) {
      controller.dispose();
    }
    super.dispose();
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile(
      {required this.label, required this.value, required this.onTap});
  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event),
        title: Text(label),
        subtitle: Text(formatDate(value)),
        onTap: onTap,
      );
}

class RegistrationAdminScreen extends StatefulWidget {
  const RegistrationAdminScreen({super.key, required this.event});
  final Map<String, dynamic> event;

  @override
  State<RegistrationAdminScreen> createState() =>
      _RegistrationAdminScreenState();
}

class _RegistrationAdminScreenState extends State<RegistrationAdminScreen> {
  final repo = UniClubRepository();

  Future<void> status(String id, String value) async {
    try {
      await repo.client
          .from('event_registrations')
          .update({'status': value}).eq('id', id);
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  Future<void> export(List<Map<String, dynamic>> rows) async {
    final answerKeys = rows
        .expand((row) =>
            (row['answers'] as Map? ?? const {}).keys.map((key) => '$key'))
        .toSet()
        .toList()
      ..sort();
    final data = <List<dynamic>>[
      [
        'registration_id',
        'user_id',
        'status',
        'payment_status',
        'amount_due',
        'registered_at',
        ...answerKeys,
      ],
      ...rows.map((row) {
        final answers =
            Map<String, dynamic>.from(row['answers'] as Map? ?? const {});
        return [
          row['id'],
          row['user_id'],
          row['status'],
          row['payment_status'],
          row['amount_due'],
          row['registered_at'],
          ...answerKeys.map((key) => answers[key]),
        ];
      }),
    ];
    final csv = const ListToCsvConverter().convert(data);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            utf8.encode(csv),
            mimeType: 'text/csv',
            name: 'event-registrations.csv',
          ),
        ],
        text: '${widget.event['title']} registrations',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrations')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: repo.client
            .from('event_registrations')
            .stream(primaryKey: ['id'])
            .eq('event_id', '${widget.event['id']}')
            .order('registered_at', ascending: false),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AsyncErrorState(error: snapshot.error);
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const EmptyState(
                icon: Icons.person_search_outlined,
                title: 'No registrations yet');
          }
          final rows = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length + 1,
            itemBuilder: (_, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: FilledButton.icon(
                    onPressed: () => export(rows),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Export registrations'),
                  ),
                );
              }
              final row = rows[index - 1];
              final answers =
                  Map<String, dynamic>.from(row['answers'] as Map? ?? {});
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ExpansionTile(
                  title: Text('${answers['name'] ?? row['user_id']}'),
                  subtitle: StatusChip('${row['status']}'),
                  childrenPadding: const EdgeInsets.all(14),
                  children: [
                    ...answers.entries.map((entry) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text('${entry.key}: ${entry.value}'))),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: ['approved', 'rejected', 'waitlisted']
                          .map((value) => OutlinedButton(
                                onPressed: () => status('${row['id']}', value),
                                child: Text(value),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AttendanceAdminScreen extends StatefulWidget {
  const AttendanceAdminScreen({super.key, required this.event});
  final Map<String, dynamic> event;

  @override
  State<AttendanceAdminScreen> createState() => _AttendanceAdminScreenState();
}

class _AttendanceAdminScreenState extends State<AttendanceAdminScreen> {
  final repo = UniClubRepository();
  final scannerController = MobileScannerController();
  bool processing = false;
  bool checkoutMode = false;

  Future<void> checkIn(String token) async {
    if (processing) return;
    setState(() => processing = true);
    await scannerController.stop();
    try {
      final registration = await repo.client
          .from('event_registrations')
          .select()
          .eq('event_id', widget.event['id'])
          .eq('qr_token', token)
          .single();
      await repo.client.rpc('record_event_attendance', params: {
        'target_event': widget.event['id'],
        'qr_value': token,
        'checkout': checkoutMode,
      });
      if (!mounted) return;
      final answers =
          Map<String, dynamic>.from(registration['answers'] as Map? ?? {});
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title:
              Text(checkoutMode ? 'Check-out complete' : 'Check-in complete'),
          content: Text(
              '${answers['name'] ?? 'Participant'} was recorded successfully.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Scan next QR'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) {
        setState(() => processing = false);
        await scannerController.start();
      }
    }
  }

  Future<void> record(Map<String, dynamic> registration,
      {required String method, bool checkout = false}) async {
    final now = DateTime.now();
    if (checkout) {
      await repo.client
          .from('attendance')
          .update({
            'checked_out_at': now.toIso8601String(),
            'marked_by': repo.userId
          })
          .eq('event_id', widget.event['id'])
          .eq('user_id', registration['user_id']);
      await repo.client
          .from('event_registrations')
          .update({'status': 'completed'}).eq('id', registration['id']);
      return;
    }
    final start = DateTime.parse('${widget.event['starts_at']}');
    await repo.client.from('attendance').upsert({
      'registration_id': registration['id'],
      'event_id': widget.event['id'],
      'user_id': registration['user_id'],
      'checked_in_at': now.toIso8601String(),
      'method': method,
      'late': now.isAfter(start.add(const Duration(minutes: 15))),
      'marked_by': repo.userId,
    }, onConflict: 'event_id,user_id');
    await repo.client
        .from('event_registrations')
        .update({'status': 'checked_in'}).eq('id', registration['id']);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Attendance'),
          bottom: const TabBar(
            tabs: [
              Tab(height: 40, text: 'QR scanner'),
              Tab(height: 40, text: 'Manual'),
              Tab(height: 40, text: 'Analytics'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            Stack(
              children: [
                MobileScanner(
                  controller: scannerController,
                  onDetect: (capture) {
                    final value = capture.barcodes.isEmpty
                        ? null
                        : capture.barcodes.first.rawValue;
                    if (value != null) checkIn(value);
                  },
                ),
                if (processing)
                  const Center(child: CircularProgressIndicator()),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 24,
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                          value: false,
                          icon: Icon(Icons.login),
                          label: Text('Check-in')),
                      ButtonSegment(
                          value: true,
                          icon: Icon(Icons.logout),
                          label: Text('Check-out')),
                    ],
                    selected: {checkoutMode},
                    onSelectionChanged: (value) =>
                        setState(() => checkoutMode = value.first),
                  ),
                ),
              ],
            ),
            _ManualAttendance(
                event: widget.event,
                checkoutMode: checkoutMode,
                record: record),
            FutureBuilder<List<dynamic>>(
              future: Future.wait([
                repo.client
                    .from('attendance')
                    .select()
                    .eq('event_id', widget.event['id']),
                repo.client
                    .from('event_registrations')
                    .select('id')
                    .eq('event_id', widget.event['id'])
                    .inFilter(
                        'status', ['approved', 'checked_in', 'completed']),
              ]),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return AsyncErrorState(error: snapshot.error);
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final attendance =
                    List<Map<String, dynamic>>.from(snapshot.data![0] as List);
                final registered =
                    List<Map<String, dynamic>>.from(snapshot.data![1] as List);
                final attended = attendance.length;
                final late =
                    attendance.where((row) => row['late'] == true).length;
                final checkedOut = attendance
                    .where((row) => row['checked_out_at'] != null)
                    .length;
                final noShows = registered.length > attended
                    ? registered.length - attended
                    : 0;
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _Metric(label: 'Checked in', value: attended),
                    _Metric(label: 'Late arrivals', value: late),
                    _Metric(label: 'Checked out', value: checkedOut),
                    _Metric(label: 'No-shows', value: noShows),
                    _Metric(label: 'On time', value: attended - late),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    scannerController.dispose();
    super.dispose();
  }
}

class _ManualAttendance extends StatelessWidget {
  const _ManualAttendance(
      {required this.event, required this.checkoutMode, required this.record});
  final Map<String, dynamic> event;
  final bool checkoutMode;
  final Future<void> Function(Map<String, dynamic>,
      {required String method, bool checkout}) record;

  @override
  Widget build(BuildContext context) {
    final repo = UniClubRepository();
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: repo.client
          .from('event_registrations')
          .stream(primaryKey: ['id'])
          .eq('event_id', '${event['id']}')
          .order('registered_at'),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AsyncErrorState(error: snapshot.error);
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!
            .where((row) => checkoutMode
                ? row['status'] == 'checked_in'
                : row['status'] == 'approved')
            .toList();
        if (rows.isEmpty) {
          return EmptyState(
              icon: Icons.how_to_reg_outlined,
              title: checkoutMode
                  ? 'No participants awaiting check-out'
                  : 'No participants awaiting check-in');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final answers =
                Map<String, dynamic>.from(row['answers'] as Map? ?? {});
            return Card(
              child: ListTile(
                title: Text('${answers['name'] ?? row['user_id']}'),
                subtitle: Text('${row['status']}'),
                trailing: IconButton(
                  tooltip:
                      checkoutMode ? 'Manual check-out' : 'Manual check-in',
                  onPressed: () =>
                      record(row, method: 'manual', checkout: checkoutMode),
                  icon: Icon(checkoutMode ? Icons.logout : Icons.login),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          title: Text(label),
          trailing:
              Text('$value', style: Theme.of(context).textTheme.headlineSmall),
        ),
      );
}

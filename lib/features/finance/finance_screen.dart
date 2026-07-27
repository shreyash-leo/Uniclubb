import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase/uniclub_repository.dart';
import '../../shared/widgets.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({
    super.key,
    required this.club,
    required this.canManage,
    required this.canApprove,
    required this.canViewDashboard,
  });
  final Map<String, dynamic> club;
  final bool canManage;
  final bool canApprove;
  final bool canViewDashboard;

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  final repo = UniClubRepository();

  Future<List<Map<String, dynamic>>> expenses() async =>
      List<Map<String, dynamic>>.from(await repo.client
          .from('expenses')
          .select('*, events(id,title,flyer_url,event_type)')
          .eq('club_id', widget.club['id'])
          .order('created_at', ascending: false));

  Future<List<Map<String, dynamic>>> budgets() async =>
      List<Map<String, dynamic>>.from(await repo.client
          .from('club_budgets')
          .select()
          .eq('club_id', widget.club['id'])
          .order('fiscal_year', ascending: false));

  Future<void> createBudget() async {
    final name = TextEditingController();
    final year = TextEditingController(text: '${DateTime.now().year}');
    final amount = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create budget'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Budget name')),
            const SizedBox(height: 10),
            TextField(
                controller: year,
                decoration: const InputDecoration(labelText: 'Fiscal year')),
            const SizedBox(height: 10),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Allocated amount', prefixText: '₹ '),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create')),
        ],
      ),
    );
    final allocated = double.tryParse(amount.text);
    if (accepted == true &&
        name.text.trim().isNotEmpty &&
        year.text.trim().isNotEmpty &&
        allocated != null) {
      await repo.client.from('club_budgets').insert({
        'club_id': widget.club['id'],
        'name': name.text.trim(),
        'fiscal_year': year.text.trim(),
        'allocated': allocated,
        'created_by': repo.userId,
      });
      if (mounted) setState(() {});
    }
    await disposeTextControllersAfterRoute([name, year, amount]);
  }

  Future<void> submitExpense() async {
    final availableBudgets =
        widget.canViewDashboard ? await budgets() : <Map<String, dynamic>>[];
    final clubEvents = List<Map<String, dynamic>>.from(await repo.client
        .from('events')
        .select('id,title,starts_at')
        .eq('club_id', widget.club['id'])
        .order('starts_at', ascending: false)
        .limit(100));
    if (!mounted) return;
    final title = TextEditingController();
    final amount = TextEditingController();
    final description = TextEditingController();
    PlatformFile? receipt;
    String? budgetId;
    String? eventId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, modalSetState) => AlertDialog(
          title: const Text('Submit expense'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                      controller: title,
                      decoration: const InputDecoration(labelText: 'Title')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Related event'),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('General club expense')),
                      ...clubEvents.map((event) => DropdownMenuItem(
                            value: '${event['id']}',
                            child: Text(
                              '${event['title']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
                    ],
                    onChanged: (value) => eventId = value,
                  ),
                  const SizedBox(height: 10),
                  if (availableBudgets.isNotEmpty) ...[
                    DropdownButtonFormField<String?>(
                      decoration: const InputDecoration(labelText: 'Budget'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Unallocated')),
                        ...availableBudgets.map((budget) => DropdownMenuItem(
                              value: '${budget['id']}',
                              child: Text('${budget['name']}'),
                            )),
                      ],
                      onChanged: (value) => budgetId = value,
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Amount', prefixText: '₹ '),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: description,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final result = await FilePicker.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
                        withData: true,
                      );
                      modalSetState(() => receipt = result?.files.single);
                    },
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: Text(receipt?.name ?? 'Attach receipt'),
                  ),
                ],
              ),
            ),
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
    if (confirmed == true && receipt?.bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A receipt attachment is required.')),
        );
      }
      await disposeTextControllersAfterRoute([title, amount, description]);
      return;
    }
    if (confirmed == true &&
        title.text.trim().isNotEmpty &&
        (double.tryParse(amount.text) ?? 0) > 0) {
      final urls = <String>[];
      if (receipt?.bytes != null) {
        urls.add(await repo.upload(
          bucket: 'receipts',
          bytes: receipt!.bytes!,
          extension: receipt!.extension ?? 'bin',
          folder: '${widget.club['id']}/${repo.userId}',
        ));
      }
      await repo.client.from('expenses').insert({
        'club_id': widget.club['id'],
        'submitted_by': repo.userId,
        'title': title.text.trim(),
        'description': description.text.trim(),
        'amount': double.parse(amount.text),
        'budget_id': budgetId,
        'event_id': eventId,
        'receipt_urls': urls,
      });
      setState(() {});
    }
    await disposeTextControllersAfterRoute([title, amount, description]);
  }

  Future<void> decide(String id, String value) async {
    try {
      await repo.client
          .rpc('decide_expense', params: {'expense_id': id, 'decision': value});
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  Future<void> export(List<Map<String, dynamic>> rows) async {
    final csv = const ListToCsvConverter().convert([
      ['Title', 'Amount', 'Status', 'Submitted', 'Description'],
      ...rows.map((row) => [
            row['title'],
            row['amount'],
            row['status'],
            row['created_at'],
            row['description'],
          ])
    ]);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(utf8.encode(csv),
              mimeType: 'text/csv', name: 'finance-report.csv')
        ],
        text: '${widget.club['name']} financial report',
      ),
    );
  }

  Future<void> showExpense(Map<String, dynamic> row) async {
    final paths = List<String>.from(row['receipt_urls'] as List? ?? const []);
    final receiptUrls = <String>[];
    for (final path in paths) {
      if (path.startsWith('http')) {
        receiptUrls.add(path);
      } else {
        receiptUrls.add(await repo.privateFileUrl('receipts', path));
      }
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .72,
        maxChildSize: .94,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${row['title']}',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                StatusChip('${row['status']}'),
              ],
            ),
            const SizedBox(height: 18),
            Text('₹${(row['amount'] as num).toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text('Submitted ${formatDate(row['created_at'])}'),
            if ('${row['description'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 18),
              const SectionHeader('Description'),
              const SizedBox(height: 6),
              Text('${row['description']}'),
            ],
            const SizedBox(height: 18),
            const SectionHeader('Receipt attachment'),
            const SizedBox(height: 8),
            if (receiptUrls.isEmpty)
              const Text('No attachment was supplied.')
            else
              ...receiptUrls.map((url) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: const Text('Open receipt'),
                      subtitle: const Text('Private, time-limited access'),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () => launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  )),
            if (widget.canApprove && row['status'] == 'pending') ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await decide('${row['id']}', 'rejected');
                      },
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await decide('${row['id']}', 'approved');
                      },
                      child: const Text('Approve'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void openMenu(List<Map<String, dynamic>> rows) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_card_outlined),
              title: const Text('Add expense'),
              onTap: () {
                Navigator.pop(context);
                submitExpense();
              },
            ),
            if (rows.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Export report'),
                onTap: () {
                  Navigator.pop(context);
                  export(rows);
                },
              ),
            if (widget.canManage)
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text('Create budget'),
                onTap: () {
                  Navigator.pop(context);
                  createBudget();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: expenses(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AsyncErrorState(error: snapshot.error);
        }
        if (!snapshot.hasData) {
          return const SkeletonList();
        }
        final rows = snapshot.data!;
        final total = rows.fold<double>(
            0, (sum, row) => sum + (row['amount'] as num? ?? 0).toDouble());
        final approved = rows
            .where(
                (row) => row['status'] == 'approved' || row['status'] == 'paid')
            .fold<double>(
                0, (sum, row) => sum + (row['amount'] as num).toDouble());
        final pending = rows
            .where((row) => row['status'] == 'pending')
            .fold<double>(
                0, (sum, row) => sum + (row['amount'] as num).toDouble());
        final eventGroups = <String, List<Map<String, dynamic>>>{};
        for (final row in rows) {
          final event = row['events'] as Map? ?? const {};
          final key = '${event['title'] ?? 'General club expenses'}';
          eventGroups.putIfAbsent(key, () => []).add(row);
        }
        if (!widget.canViewDashboard) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('My expenses',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  FilledButton.icon(
                    onPressed: submitExpense,
                    icon: const Icon(Icons.add),
                    label: const Text('Add expense'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (rows.isEmpty)
                const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No expenses submitted',
                  message: 'Your submitted expenses will appear here.',
                )
              else
                ...rows.map((row) => Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        onTap: () => showExpense(row),
                        title: Text('${row['title']}'),
                        subtitle: Text(
                            '₹${row['amount']} · ${(row['events'] as Map?)?['title'] ?? 'General'}\n${formatDate(row['created_at'])}'),
                        isThreeLine: true,
                        trailing: StatusChip('${row['status']}'),
                      ),
                    )),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Finance dashboard',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton.filledTonal(
                  tooltip: 'Finance menu',
                  onPressed: () => openMenu(rows),
                  icon: const Icon(Icons.more_horiz),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Submitted expenses'),
                    const SizedBox(height: 8),
                    Text('₹${total.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.headlineMedium),
                    Text(
                        'Approved ₹${approved.toStringAsFixed(2)} · Pending ₹${pending.toStringAsFixed(2)}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            const SectionHeader('Budgets'),
            const SizedBox(height: 8),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: budgets(),
              builder: (context, budgetSnapshot) {
                if (budgetSnapshot.hasError) {
                  return AsyncErrorState(error: budgetSnapshot.error);
                }
                if (!budgetSnapshot.hasData) {
                  return const SizedBox(
                      height: 100, child: SkeletonList(count: 1));
                }
                if (budgetSnapshot.data!.isEmpty) {
                  return const Text('No budgets created.');
                }
                return Column(
                  children: budgetSnapshot.data!.map((budget) {
                    final allocated =
                        (budget['allocated'] as num? ?? 0).toDouble();
                    final spent = (budget['spent'] as num? ?? 0).toDouble();
                    final progress = allocated <= 0
                        ? 0.0
                        : (spent / allocated).clamp(0.0, 1.0);
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                    child: Text('${budget['name']}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium)),
                                Text('${budget['fiscal_year']}'),
                              ],
                            ),
                            const SizedBox(height: 10),
                            LinearProgressIndicator(value: progress),
                            const SizedBox(height: 8),
                            Text(
                                'Spent ₹${spent.toStringAsFixed(2)} · Remaining ₹${(allocated - spent).clamp(0, double.infinity).toStringAsFixed(2)}'),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 18),
            const SectionHeader('Event finance'),
            const SizedBox(height: 8),
            if (eventGroups.isEmpty)
              const Text('Event-wise spending will appear here.')
            else
              ...eventGroups.entries.map((entry) {
                final eventApproved = entry.value
                    .where((row) =>
                        row['status'] == 'approved' || row['status'] == 'paid')
                    .fold<double>(0,
                        (sum, row) => sum + (row['amount'] as num).toDouble());
                final eventPending = entry.value
                    .where((row) => row['status'] == 'pending')
                    .fold<double>(0,
                        (sum, row) => sum + (row['amount'] as num).toDouble());
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.key,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 5),
                        Text(
                          'Approved ₹${eventApproved.toStringAsFixed(2)} · '
                          'Pending ₹${eventPending.toStringAsFixed(2)} · '
                          '${entry.value.length} expense${entry.value.length == 1 ? '' : 's'}',
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 18),
            const SectionHeader('Expenses'),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Text('No expenses recorded.')
            else
              ...rows.map((row) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      onTap: () => showExpense(row),
                      title: Text('${row['title']}'),
                      subtitle: Text(
                          '₹${row['amount']} · ${(row['events'] as Map?)?['title'] ?? 'General'}\n${formatDate(row['created_at'])}'),
                      isThreeLine: true,
                      trailing: widget.canApprove && row['status'] == 'pending'
                          ? PopupMenuButton<String>(
                              onSelected: (value) =>
                                  decide('${row['id']}', value),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                    value: 'approved', child: Text('Approve')),
                                PopupMenuItem(
                                    value: 'rejected', child: Text('Reject')),
                              ],
                            )
                          : StatusChip('${row['status']}'),
                    ),
                  )),
          ],
        );
      },
    );
  }
}

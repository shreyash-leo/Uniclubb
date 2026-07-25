import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/supabase/uniclub_repository.dart';
import '../../shared/widgets.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({
    super.key,
    required this.club,
    required this.canManage,
    required this.canApprove,
  });
  final Map<String, dynamic> club;
  final bool canManage;
  final bool canApprove;

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  final repo = UniClubRepository();

  Future<List<Map<String, dynamic>>> expenses() async =>
      List<Map<String, dynamic>>.from(await repo.client
          .from('expenses')
          .select()
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
    final availableBudgets = await budgets();
    if (!mounted) return;
    final title = TextEditingController();
    final amount = TextEditingController();
    final description = TextEditingController();
    PlatformFile? receipt;
    String? budgetId;
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
                  if (availableBudgets.isNotEmpty) ...[
                    DropdownButtonFormField<String?>(
                      decoration:
                          const InputDecoration(labelText: 'Budget (optional)'),
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
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
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
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                    onPressed: submitExpense,
                    icon: const Icon(Icons.add),
                    label: const Text('Expense')),
                OutlinedButton.icon(
                    onPressed: rows.isEmpty ? null : () => export(rows),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Report')),
                if (widget.canManage)
                  OutlinedButton.icon(
                    onPressed: createBudget,
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: const Text('Budget'),
                  ),
              ],
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
                  children: budgetSnapshot.data!
                      .map((budget) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                                Icons.account_balance_wallet_outlined),
                            title: Text('${budget['name']}'),
                            subtitle: Text(
                                '${budget['fiscal_year']} · Spent ₹${budget['spent']}'),
                            trailing: Text('₹${budget['allocated']}'),
                          ))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 18),
            const SectionHeader('Expenses'),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Text('No expenses recorded.')
            else
              ...rows.map((row) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      title: Text('${row['title']}'),
                      subtitle: Text(
                          '₹${row['amount']} · ${formatDate(row['created_at'])}'),
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

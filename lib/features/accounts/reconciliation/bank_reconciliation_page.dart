import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'package:emville_pms/ui/emville_widgets.dart';
import '../data/finance_access.dart';
import 'reconciliation_repository.dart';
import 'statement_upload_page.dart';
import 'statement_review_page.dart';

class BankReconciliationPage extends StatefulWidget {
  const BankReconciliationPage({super.key});
  @override
  State<BankReconciliationPage> createState() => _BankReconciliationPageState();
}

class _BankReconciliationPageState extends State<BankReconciliationPage> {
  final _repo = BankReconciliationRepository(Supabase.instance.client);
  late Future<(bool, List<Map<String, dynamic>>)> _data;
  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<(bool, List<Map<String, dynamic>>)> _load() async {
    final allowed = await FinanceAccess.isOwnerOrAdmin(_repo.client);
    return (allowed, allowed ? await _repo.months() : <Map<String, dynamic>>[]);
  }

  Future<void> _refresh() async {
    setState(() {
      _data = _load();
    });
    try {
      await _data;
    } catch (_) {}
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => EmvillePage(
      section: 2,
      child: EmvilleBody(
          child: FutureBuilder(
              future: _data,
              builder: (context, s) {
                if (s.hasError) {
                  return EmvilleError(
                      message: 'Could not load bank reconciliation.',
                      onRetry: _refresh);
                }
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final (allowed, months) = s.data!;
                if (!allowed) {
                  return const Center(
                      child: Text(
                          'Bank statements are available only to admins and owners.'));
                }
                final now = DateTime.now();
                final previous = DateTime(now.year, now.month - 1);
                final due = now.day >= 2 &&
                    !months.any((r) =>
                        r['month'] ==
                        DateFormat('yyyy-MM-dd').format(previous));
                return RefreshIndicator(
                    onRefresh: _refresh,
                    child:
                        ListView(padding: const EdgeInsets.all(22), children: [
                      const EmvilleHeading('Bank reconciliation',
                          eyebrow: 'Accounts / Federal Bank',
                          subtitle:
                              'Compare the monthly bank statement with your main ledger.'),
                      const SizedBox(height: 20),
                      EmvilleCallout(
                          leading: const Icon(Icons.account_balance_outlined),
                          trailing: EmvilleTag(due ? 'Upload due' : 'Monthly',
                              warning: due),
                          child: Text(due
                              ? '${DateFormat('MMMM yyyy').format(previous)} statement is due. Admin reminders arrive on the 2nd of each month.'
                              : 'Monthly statement reminders are sent to admins on the 2nd.')),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                          onPressed: () => _open(const StatementUploadPage()),
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Upload bank statement PDF')),
                      const SizedBox(height: 12),
                      const Text(
                          'Statement transactions are reviewed before comparison. Proposed ledger entries need explicit admin approval before posting.',
                          style: TextStyle(
                              fontSize: 12, color: Emville.muted, height: 1.5)),
                      const EmvilleSectionTitle('Monthly reviews'),
                      if (months.isEmpty)
                        const Text('No bank statements uploaded yet.'),
                      for (final r in months)
                        EmvilleTile(
                            icon: Icons.fact_check_outlined,
                            title: DateFormat('MMMM yyyy')
                                .format(DateTime.parse(r['month'])),
                            subtitle:
                                'Federal Bank · Opening ${rupees(r['opening_balance'])} · Closing ${rupees(r['closing_balance'])}',
                            trailing: EmvilleTag(
                                r['status'] == 'completed'
                                    ? 'Reviewed'
                                    : 'In review',
                                warning: r['status'] != 'completed'),
                            onTap: () =>
                                _open(StatementReviewPage(id: r['id']))),
                    ]));
              })));
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'package:emville_pms/ui/emville_widgets.dart';
import '../data/finance_access.dart';
import 'account_balance_box.dart';
import 'petty_cash_page.dart';
import 'petty_cash_bill_form_page.dart';
import 'main_accounts_page.dart';
import 'approvals_page.dart';
import 'main_income_receipt_form_page.dart';
import 'main_expenses_form_page.dart';

class AccountsHubPage extends StatefulWidget {
  const AccountsHubPage({super.key, this.role});
  final String?
      role; // Display context only; privileges are verified against user_roles.
  @override
  State<AccountsHubPage> createState() => _AccountsHubPageState();
}

class _AccountsHubPageState extends State<AccountsHubPage> {
  late Future<AccountsOverview> _overview;
  Future<AccountsOverview> _load() =>
      AccountsRepository(Supabase.instance.client).load();
  @override
  void initState() {
    super.initState();
    _overview = _load();
  }

  Future<void> _refresh() async {
    setState(() {
      _overview = _load();
    });
    try {
      await _overview;
    } catch (_) {}
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => EmvilleBody(
      child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
              children: [
                const EmvilleHeading('Accounts',
                    eyebrow: 'The business at a glance',
                    subtitle: 'Every rupee. Every receipt. In order.'),
                FutureBuilder<AccountsOverview>(
                    future: _overview,
                    builder: (context, snapshot) {
                      final data = snapshot.data;
                      if (snapshot.hasError) {
                        return EmvilleError(onRetry: _refresh);
                      }
                      if (data == null) {
                        return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()));
                      }
                      return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 20),
                            if (data.privileged) ...[
                              AccountBalanceBox(
                                  key: const ValueKey('main-approved-balance'),
                                  label: 'MAIN LEDGER · APPROVED BALANCE',
                                  balance: data.main!,
                                  photo: true,
                                  showUnapproved: true),
                              const SizedBox(height: 13)
                            ],
                            AccountBalanceBox(
                                key: const ValueKey('petty-approved-balance'),
                                label: 'Petty cash · Approved balance',
                                balance: data.petty,
                                compact: true,
                                showUnapproved: data.privileged),
                            const SizedBox(height: 15),
                            EmvilleCallout(
                                leading: Text('${data.pending}',
                                    style: Emville.heading(20)),
                                trailing:
                                    const Icon(Icons.chevron_right, size: 17),
                                onTap: () => _open(const ApprovalsPage()),
                                child: Text(data.privileged
                                    ? 'Entries awaiting approval\nAcross main ledger and petty cash'
                                    : 'Your entries awaiting approval')),
                          ]);
                    }),
                const EmvilleSectionTitle('Add an entry'),
                GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 9,
                    mainAxisSpacing: 9,
                    mainAxisExtent: 60,
                    children: [
                      _action(Icons.add, 'Add income',
                          () => _open(const MainIncomeReceiptFormPage())),
                      _action(Icons.payments_outlined, 'Add expense',
                          () => _open(const MainExpensesFormPage())),
                      _action(Icons.receipt_long_outlined, 'Petty cash receipt',
                          () => _open(const PettyCashBillFormPage())),
                      _action(
                          Icons.chevron_right,
                          'Fund petty cash',
                          () => _open(const MainExpensesFormPage(
                              receiver: 'Petty cash'))),
                    ]),
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 13),
                    child: Text(
                        'Every income, expense and petty cash entry is submitted for approval.',
                        style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 10,
                            color: Emville.muted,
                            height: 1.6))),
                const Divider(),
                Row(children: [
                  Expanded(
                      child: TextButton(
                          onPressed: () => _open(const MainAccountsPage()),
                          child: const Text('Main ledger',
                              style: TextStyle(fontSize: 11)))),
                  Expanded(
                      child: TextButton(
                          onPressed: () => _open(const PettyCashPage()),
                          child: const Text('Petty cash ledger',
                              style: TextStyle(fontSize: 11))))
                ]),
              ])));
  Widget _action(IconData icon, String title, VoidCallback action) => Material(
      color: Emville.paper,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: const BorderSide(color: Emville.line)),
      child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: action,
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
              child: Row(children: [
                Icon(icon, size: 17, color: Emville.forest),
                const SizedBox(width: 9),
                Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontFamily: 'Roboto', fontSize: 11)))
              ]))));
}

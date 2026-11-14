import 'package:flutter/material.dart';
import 'emville_theme.dart';
import 'emville_widgets.dart';

class LedgerEntry {
  const LedgerEntry(
      {required this.title,
      required this.date,
      required this.amount,
      required this.income,
      required this.status,
      required this.onTap,
      this.description});
  final String title, date, status;
  final String? description;
  final double amount;
  final bool income;
  final VoidCallback onTap;
}

/// Presentation follows the ledger and petty-cash concepts; writes stay in the existing forms.
class LedgerPanel extends StatefulWidget {
  const LedgerPanel(
      {super.key,
      required this.title,
      required this.period,
      required this.entries,
      required this.balance,
      required this.actions,
      required this.onRefresh});
  final String title, period;
  final Future<List<LedgerEntry>> entries;
  final Widget balance;
  final List<Widget> actions;
  final Future<void> Function() onRefresh;
  @override
  State<LedgerPanel> createState() => _LedgerPanelState();
}

class _LedgerPanelState extends State<LedgerPanel> {
  String _filter = 'All', _search = '';
  bool get _petty => widget.title == 'Petty cash';
  void _addEntry() => showModalBottomSheet<void>(
      context: context,
      backgroundColor: Emville.ivory,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
          child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Add entry', style: Emville.heading(26)),
                    const SizedBox(height: 18),
                    ...widget.actions.map((action) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: action is OutlinedButton
                            ? OutlinedButton(
                                style: action.style,
                                onPressed: action.onPressed == null
                                    ? null
                                    : () {
                                        Navigator.of(sheetContext).pop();
                                        action.onPressed!();
                                      },
                                child: action.child ?? const Text('Open'))
                            : action))
                  ]))));
  @override
  Widget build(BuildContext context) => EmvillePage(
      child: EmvilleBody(
          child: RefreshIndicator(
              onRefresh: widget.onRefresh,
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
                  children: [
                    EmvilleHeading(widget.title,
                        eyebrow: _petty
                            ? 'Accounts / Daily spending'
                            : 'Accounts / Main ledger',
                        subtitle: _petty
                            ? 'Small expenses. Everything accounted for.'
                            : 'Receipts, payments and a balanced day.'),
                    const SizedBox(height: 23),
                    widget.balance,
                    const SizedBox(height: 19),
                    if (_petty) ...[
                      Row(children: [
                        for (final action in widget.actions.take(2))
                          Expanded(
                              child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  child: action))
                      ]),
                      const SizedBox(height: 20)
                    ],
                    EmvilleTabs(
                        labels: _petty
                            ? const ['All', 'Bills', 'Funding']
                            : const ['All', 'Income', 'Expenses'],
                        selected: _filter,
                        onSelected: (value) => setState(() => _filter = value)),
                    if (!_petty) ...[
                      const SizedBox(height: 18),
                      SizedBox(
                          height: 40,
                          child: TextField(
                              style: const TextStyle(
                                  fontFamily: 'Roboto', fontSize: 11),
                              onChanged: (value) =>
                                  setState(() => _search = value.toLowerCase()),
                              decoration: const InputDecoration(
                                  hintText:
                                      'Search payee, reference or category',
                                  prefixIcon: Icon(Icons.search, size: 17),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 11, vertical: 10))))
                    ],
                    if (_petty)
                      EmvilleSectionTitle('Recent activity',
                          trailing: Text(widget.period,
                              style: const TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 10,
                                  color: Emville.muted))),
                    FutureBuilder<List<LedgerEntry>>(
                        future: widget.entries,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return EmvilleError(onRetry: widget.onRefresh);
                          }
                          if (!snapshot.hasData) {
                            return const Padding(
                                padding: EdgeInsets.all(30),
                                child:
                                    Center(child: CircularProgressIndicator()));
                          }
                          final entries = snapshot.data!
                              .where((e) =>
                                  (_filter == 'All' ||
                                      (_filter == 'Income' ||
                                              _filter == 'Funding') &&
                                          e.income ||
                                      (_filter == 'Expenses' ||
                                              _filter == 'Bills') &&
                                          !e.income) &&
                                  '${e.title} ${e.description ?? ''} ${e.date} ${e.status}'
                                      .toLowerCase()
                                      .contains(_search))
                              .toList();
                          return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (entries.isEmpty)
                                  const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 28),
                                      child: Text('No matching transactions.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              fontFamily: 'Roboto',
                                              fontSize: 12,
                                              color: Emville.muted))),
                                for (final entry in entries)
                                  EmvilleTile(
                                      icon: entry.income
                                          ? Icons.south_west
                                          : Icons.north_east,
                                      title: entry.title,
                                      subtitle: entry.description ??
                                          shortDate(entry.date),
                                      onTap: entry.onTap,
                                      trailing: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                                '${entry.income ? '+' : '−'}${rupees(entry.amount)}',
                                                style: const TextStyle(
                                                    fontFamily: 'Roboto',
                                                    fontSize: 12)),
                                            const SizedBox(height: 5),
                                            EmvilleTag(
                                                entry.status == 'approved'
                                                    ? 'Approved'
                                                    : entry.status == 'pending'
                                                        ? 'Pending'
                                                        : entry.status,
                                                warning:
                                                    entry.status == 'pending')
                                          ])),
                                if (!_petty)
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      child: Text(
                                          '${entries.length} entries · ${widget.period}',
                                          style: const TextStyle(
                                              fontFamily: 'Roboto',
                                              fontSize: 10,
                                              color: Emville.muted))),
                              ]);
                        }),
                    if (!_petty)
                      FilledButton(
                          onPressed: _addEntry,
                          child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add, size: 16),
                                SizedBox(width: 8),
                                Text('Add entry')
                              ])),
                    if (_petty) ...[
                      const SizedBox(height: 18),
                      const EmvilleCallout(
                          child: Text(
                              'Ledger balance includes pending bills.\nApproved balance reflects approved entries.')),
                      if (widget.actions.length > 2) ...[
                        const SizedBox(height: 10),
                        ...widget.actions.skip(2)
                      ]
                    ],
                  ]))));
}

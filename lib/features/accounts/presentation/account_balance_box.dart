import 'package:flutter/material.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'package:emville_pms/ui/emville_widgets.dart';
import '../data/finance_access.dart';

class AccountBalanceBox extends StatelessWidget {
  const AccountBalanceBox(
      {super.key,
      required this.label,
      required this.balance,
      this.photo = false,
      this.compact = false,
      this.showLedgerBalance = false});
  final String label;
  final AccountBalance balance;
  final bool photo, compact, showLedgerBalance;
  String amount(num? value) => value == null ? 'Unavailable' : rupees(value);
  @override
  Widget build(BuildContext context) {
    final color = photo ? Emville.paper : Emville.ink;
    return ClipRRect(
        borderRadius: BorderRadius.circular(compact ? 12 : 15),
        child: Container(
          decoration: BoxDecoration(
              color: compact ? Emville.paper : Emville.forest,
              image: photo
                  ? const DecorationImage(
                      image: AssetImage(Emville.pool), fit: BoxFit.cover)
                  : null,
              border: compact ? Border.all(color: Emville.line) : null,
              borderRadius: BorderRadius.circular(compact ? 12 : 15)),
          child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: compact ? 16 : 22, vertical: compact ? 15 : 20),
              decoration: photo
                  ? const BoxDecoration(
                      gradient: LinearGradient(
                          colors: [Color(0xEB113D32), Color(0xAA113D32)]))
                  : null,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: compact ? 12 : 9,
                            letterSpacing: compact ? 0 : 1.7,
                            fontWeight:
                                compact ? FontWeight.w600 : FontWeight.w400,
                            color: compact ? color : Emville.paper)),
                    const SizedBox(height: 10),
                    Text(amount(balance.approved),
                        style: Emville.heading(compact ? 26 : 34).copyWith(
                            color: compact ? Emville.ink : Emville.paper)),
                    if (showLedgerBalance) ...[
                      const SizedBox(height: 12),
                      Align(
                          alignment: Alignment.bottomRight,
                          child: Semantics(
                              label: 'Ledger balance for $label',
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('Ledger balance',
                                        style: TextStyle(
                                            fontFamily: 'Roboto',
                                            fontSize: 9,
                                            color: compact
                                                ? Emville.muted
                                                : const Color(0xFFD7DFCB))),
                                    const SizedBox(height: 4),
                                    Text(amount(balance.ledger),
                                        style: TextStyle(
                                            fontFamily: 'Roboto',
                                            fontSize: 12,
                                            color: compact
                                                ? Emville.ink
                                                : Emville.paper))
                                  ])))
                    ],
                  ])),
        ));
  }
}

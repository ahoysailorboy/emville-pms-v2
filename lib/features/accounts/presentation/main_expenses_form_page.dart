import 'package:flutter/material.dart';
import 'account_entry_page.dart';

class MainExpensesFormPage extends StatelessWidget {
  const MainExpensesFormPage({super.key, this.receiver = ''});
  final String receiver;
  @override
  Widget build(BuildContext context) =>
      AccountEntryPage(kind: AccountEntryKind.expense, receiver: receiver);
}

import 'package:flutter/material.dart';
import 'account_entry_page.dart';

class MainIncomeReceiptFormPage extends StatelessWidget {
  const MainIncomeReceiptFormPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const AccountEntryPage(kind: AccountEntryKind.income);
}

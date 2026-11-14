import 'package:flutter/material.dart';
import 'account_entry_page.dart';

class PettyCashBillFormPage extends StatelessWidget {
  const PettyCashBillFormPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const AccountEntryPage(kind: AccountEntryKind.pettyReceipt);
}

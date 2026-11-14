import 'package:flutter/material.dart';
import 'approvals_page.dart';

class PettyCashPendingApprovalsPage extends StatelessWidget {
  const PettyCashPendingApprovalsPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const ApprovalsPage(initialFilter: 'Petty cash');
}

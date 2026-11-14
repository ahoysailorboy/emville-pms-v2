import 'package:flutter/material.dart';
import 'approvals_page.dart';

class MainAccountPendingApprovalsPage extends StatelessWidget {
  const MainAccountPendingApprovalsPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const ApprovalsPage(initialFilter: 'Main');
}

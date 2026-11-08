// lib/features/reports/generate_reports_page.dart
import 'package:flutter/material.dart';
import 'report_ledger_page.dart';
import 'report_income_page.dart';
import 'report_expenses_page.dart';
import 'report_pl_page.dart';
import 'report_petty_cash_page.dart';
import 'advanced_filter_page.dart';

// ✅ Responsive barrel
import 'package:emville_pms/responsive/responsive.dart';

class GenerateReportsPage extends StatelessWidget {
  const GenerateReportsPage({super.key});

  // Emville theme (exactly like AccountsHubPage)
  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  Widget _buildTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Builder(
      builder: (ctx) {
        final rs = ResponsiveSize.of(ctx);
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rs.radius(16)),
          ),
          elevation: 3,
          margin: EdgeInsets.symmetric(vertical: rs.space(8)),
          child: InkWell(
            borderRadius: BorderRadius.circular(rs.radius(16)),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.all(rs.space(16)),
              child: Row(
                children: [
                  Container(
                    height: rs.icon(46),
                    width: rs.icon(46),
                    decoration: BoxDecoration(
                      color: _green,
                      borderRadius: BorderRadius.circular(rs.radius(12)),
                    ),
                    child: Icon(icon, color: _gold, size: rs.icon(22)),
                  ),
                  SizedBox(width: rs.space(16)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: rs.font(16),
                            fontWeight: FontWeight.bold,
                            color: _green,
                          ),
                        ),
                        SizedBox(height: rs.space(4)),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: rs.font(13),
                            color: _green.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: _green, size: rs.icon(22)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Coming soon')));
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);

    return Scaffold(
      // AppBar styling in Emville colors (kept consistent)
      appBar: AppBar(
        backgroundColor: _green,
        title: Text(
          'Generate Reports',
          style: TextStyle(
            color: _gold,
            fontWeight: FontWeight.bold,
            fontSize: rs.font(18),
          ),
        ),
        iconTheme: const IconThemeData(color: _gold),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(rs.space(16)),
          child: ListView(
            children: [
              // Main Ledger Report
              _buildTile(
                icon: Icons.menu_book_outlined,
                title: 'Main Ledger Report',
                subtitle: 'Transactions with opening/closing balances',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ReportLedgerPage()),
                  );
                },
              ),

              // Income Report
              _buildTile(
                icon: Icons.attach_money_outlined,
                title: 'Income Report',
                subtitle: 'All income entries in the selected period',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ReportIncomePage()),
                  );
                },
              ),

              // Expenses Report
              _buildTile(
                icon: Icons.payments_outlined,
                title: 'Expenses Report',
                subtitle: 'All expense entries in the selected period',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ReportExpensesPage(),
                    ),
                  );
                },
              ),

              // Profit & Loss
              _buildTile(
                icon: Icons.receipt_long_outlined,
                title: 'P/L Statement',
                subtitle: 'Monthly / Quarterly / Annual profit & loss',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ReportPlPage()),
                  );
                },
              ),

              // Petty Cash Account Report
              _buildTile(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Petty Cash Account Report',
                subtitle: 'Opening balance, bills, top-ups & closing balance',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ReportPettyCashPage(),
                    ),
                  );
                },
              ),

              // Advanced Filter
              _buildTile(
                icon: Icons.filter_alt_outlined,
                title: 'Advanced Filter',
                subtitle: 'Search by dates, text, status across ledgers',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdvancedFilterPage(),
                    ),
                  );
                },
              ),

              // Monthly Analysis (placeholder)
              _buildTile(
                icon: Icons.bar_chart_outlined,
                title: 'Monthly Analysis',
                subtitle: 'Visual trends & breakdowns (coming soon)',
                onTap: () => _comingSoon(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

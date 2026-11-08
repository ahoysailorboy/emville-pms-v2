// lib/features/accounts/presentation/accounts_hub_page.dart
import 'package:flutter/material.dart';
import 'petty_cash_page.dart';
import 'main_accounts_page.dart';
import 'generate_reports_page.dart';

// ✅ Responsive barrel
import 'package:emville_pms/responsive/responsive.dart';

class AccountsHubPage extends StatelessWidget {
  const AccountsHubPage({super.key, this.role});

  final String? role;
  bool get _isAdmin => role == 'owner' || role == 'admin';

  // Theme colors from logo
  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  Widget _buildTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final rs = ResponsiveSize.of(context);
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
                child: Icon(icon, color: _gold, size: rs.icon(24)),
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
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);

    return Padding(
      padding: EdgeInsets.all(rs.space(16)),
      child: ListView(
        children: [
          Text(
            'Accounts',
            style: TextStyle(
              fontSize: rs.font(22),
              fontWeight: FontWeight.w800,
              color: _green,
            ),
          ),
          SizedBox(height: rs.space(16)),

          // Main Accounts
          _buildTile(
            context: context,
            icon: Icons.call_received,
            title: 'Main Accounts',
            subtitle: 'Record income and payment receipts',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MainAccountsPage()),
              );
            },
          ),

          // Petty Cash
          _buildTile(
            context: context,
            icon: Icons.payments_outlined,
            title: 'Petty Cash Account',
            subtitle: 'Daily cash payments and receipts',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PettyCashPage()),
              );
            },
          ),

          // Generate Reports
          _buildTile(
            context: context,
            icon: Icons.assessment_outlined,
            title: 'Generate Reports',
            subtitle: 'Generate Various Reports',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GenerateReportsPage()),
              );
            },
          ),

          if (_isAdmin) ...[
            SizedBox(height: rs.space(12)),
            _buildTile(
              context: context,
              icon: Icons.pending_actions_outlined,
              title: 'Pending Approvals',
              subtitle: 'Receipts & payments needing approval',
              onTap: () {}, // to be wired later
            ),
          ],
        ],
      ),
    );
  }
}

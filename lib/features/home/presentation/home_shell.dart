// lib/features/home/presentation/home_shell.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/features/home/presentation/first_page.dart';
import 'package:emville_pms/features/accounts/presentation/accounts_hub_page.dart';
import 'package:emville_pms/features/pms/add_pms_task.dart';
import 'package:emville_pms/features/pms/edit_pms_page.dart';
import 'package:emville_pms/features/pms/generate_pms_report.dart';
import 'package:emville_pms/features/user_records/user_management.dart';
import 'package:emville_pms/features/user_records/my_profile.dart';
import 'package:emville_pms/features/pms/pms_advanced_search.dart';
import 'package:emville_pms/features/bookings/bookings_hub.dart';
// ✅ responsive barrel
import 'package:emville_pms/responsive/responsive.dart';
import 'package:emville_pms/services/onesignal_sync.dart';

enum _Menu {
  home,
  pmsTasks, // admins only
  pmsReports,
  advancedSearch,
  editPmsTasks, // admins only
  accountsHub, // opens Accounts hub
  myProfile,
  userManagement, // admins only
  bookingsHub,
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.role});

  /// Supplied by AuthGate after bootstrap. e.g. 'owner', 'admin', 'caretaker'
  final String? role;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _sb = Supabase.instance.client;

  _Menu _selected = _Menu.home;
  bool get _isAdmin => (widget.role == 'owner') || (widget.role == 'admin');

  void _select(_Menu m) {
    setState(() => _selected = m);
    Navigator.of(context).pop(); // close the drawer
  }

  @override
  Widget build(BuildContext context) {
    // Emville brand colors
    const Color emvilleGreen = Color(0xFF103329);
    const Color emvilleGold = Color(0xFFD9A633);

    // ✅ responsive helper
    final rs = ResponsiveSize.of(context);

    final body = switch (_selected) {
      _Menu.home => FirstPage(role: widget.role),
      _Menu.pmsTasks => const AddPmsTaskPage(),
      _Menu.pmsReports => const GeneratePmsReportPage(),
      _Menu.editPmsTasks => const EditPmsPage(),
      _Menu.accountsHub => const AccountsHubPage(),
      _Menu.myProfile => const MyProfilePage(),
      _Menu.userManagement => const UserManagementPage(),
      _Menu.advancedSearch => const PmsAdvancedSearchPage(),
      _Menu.bookingsHub => const BookingsHubPage(),
    };

    return Scaffold(
      appBar: AppBar(
        backgroundColor: emvilleGreen,
        iconTheme: const IconThemeData(color: emvilleGold), // hamburger color
        title: Text(
          'Emville PMS',
          style: TextStyle(
            color: emvilleGold,
            fontWeight: FontWeight.bold,
            fontSize: rs.font(18),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: Icon(Icons.logout, color: emvilleGold, size: rs.icon(22)),
            onPressed: () async {
              await _sb.auth.signOut(scope: SignOutScope.local);
              // ✅ Immediately clear OneSignal tags and logout the device
              await syncOneSignalIdentityAndRoleFromUsersV();
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.symmetric(vertical: rs.space(8)),
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(color: emvilleGreen),
                child: Padding(
                  padding: EdgeInsets.only(bottom: rs.space(4)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Emville PMS',
                        style: TextStyle(
                          color: emvilleGold,
                          fontSize: rs.font(18),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.role != null)
                        Text(
                          'Role: ${widget.role}',
                          style: TextStyle(
                            color: emvilleGold.withValues(alpha: 0.8),
                            fontSize: rs.font(12),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Home
              ListTile(
                leading: Icon(Icons.home, size: rs.icon(22)),
                title: Text('Home', style: TextStyle(fontSize: rs.font(14))),
                selected: _selected == _Menu.home,
                onTap: () => _select(_Menu.home),
              ),

              // Add PMS tasks (admins only)

              ListTile(
                leading: Icon(Icons.playlist_add_check, size: rs.icon(22)),
                title: Text('Add PMS tasks',
                    style: TextStyle(fontSize: rs.font(14))),
                selected: _selected == _Menu.pmsTasks,
                onTap: () => _select(_Menu.pmsTasks),
              ),

              // Generate PMS reports
              ListTile(
                leading: Icon(Icons.assessment, size: rs.icon(22)),
                title: Text('Generate PMS reports',
                    style: TextStyle(fontSize: rs.font(14))),
                selected: _selected == _Menu.pmsReports,
                onTap: () => _select(_Menu.pmsReports),
              ),

              ListTile(
                leading: Icon(Icons.assessment, size: rs.icon(22)),
                title: Text('PMS Advanced Search',
                    style: TextStyle(fontSize: rs.font(14))),
                selected: _selected == _Menu.advancedSearch,
                onTap: () => _select(_Menu.advancedSearch),
              ),

              Divider(height: rs.space(24)),

              // Accounts hub
              ListTile(
                leading: Icon(Icons.account_balance_wallet, size: rs.icon(22)),
                title:
                    Text('Accounts', style: TextStyle(fontSize: rs.font(14))),
                selected: _selected == _Menu.accountsHub,
                onTap: () => _select(_Menu.accountsHub),
              ),

              Divider(height: rs.space(24)),

              ListTile(
                leading: Icon(Icons.calendar_month, size: rs.icon(22)),
                title:
                    Text('Bookings', style: TextStyle(fontSize: rs.font(14))),
                selected: _selected == _Menu.bookingsHub,
                onTap: () => _select(_Menu.bookingsHub),
              ),

              Divider(height: rs.space(24)),

              ListTile(
                leading: Icon(Icons.settings, size: rs.icon(22)),
                title: Text('Profile', style: TextStyle(fontSize: rs.font(14))),
                selected: _selected == _Menu.myProfile,
                onTap: () => _select(_Menu.myProfile),
              ),

              if (_isAdmin) Divider(height: rs.space(24)),

              // Admin section
              if (_isAdmin)
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: rs.space(16),
                    vertical: rs.space(8),
                  ),
                  child: Text(
                    'Admin',
                    style: TextStyle(
                      fontSize: rs.font(12),
                      color: Colors.black54,
                    ),
                  ),
                ),

              if (_isAdmin)
                ListTile(
                  leading:
                      Icon(Icons.edit_calendar_outlined, size: rs.icon(22)),
                  title:
                      Text('Edit PMS', style: TextStyle(fontSize: rs.font(14))),
                  selected: _selected == _Menu.editPmsTasks,
                  onTap: () => _select(_Menu.editPmsTasks),
                ),

              if (_isAdmin)
                ListTile(
                  leading: Icon(Icons.account_tree, size: rs.icon(22)),
                  title: Text('User Management',
                      style: TextStyle(fontSize: rs.font(14))),
                  selected: _selected == _Menu.userManagement,
                  onTap: () => _select(_Menu.userManagement),
                ),
            ],
          ),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(rs.space(16)),
        child: body,
      ),
    );
  }
}

// ignore: unused_element
class _SectionPlaceholder extends StatelessWidget {
  const _SectionPlaceholder({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    return Card(
      elevation: 0.5,
      child: SizedBox.expand(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(rs.space(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: rs.font(20),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: rs.space(8)),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: rs.font(14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

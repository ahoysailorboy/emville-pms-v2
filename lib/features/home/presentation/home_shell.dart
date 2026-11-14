import 'package:emville_pms/features/bookings/existing_booking.dart';
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
import 'package:emville_pms/ui/emville_theme.dart';
import 'package:emville_pms/ui/emville_widgets.dart';
import 'package:emville_pms/features/accounts/presentation/generate_reports_page.dart';
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
  maintenance,
  reports,
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
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  _Menu _selected = _Menu.home;
  bool get _isAdmin => (widget.role == 'owner') || (widget.role == 'admin');

  static const _destinations = [
    _Menu.home,
    _Menu.bookingsHub,
    _Menu.accountsHub,
    _Menu.maintenance
  ];
  @override
  void initState() {
    super.initState();
    EmvilleNavigation.section.value = 0;
    EmvilleNavigation.section.addListener(_sectionChanged);
    EmvilleNavigation.drawerOpener = _openDrawer;
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  void _sectionChanged() {
    final index = EmvilleNavigation.section.value;
    if (mounted && index >= 0 && index < _destinations.length) {
      setState(() => _selected = _destinations[index]);
    }
  }

  @override
  void dispose() {
    EmvilleNavigation.section.removeListener(_sectionChanged);
    if (EmvilleNavigation.drawerOpener == _openDrawer) {
      EmvilleNavigation.drawerOpener = null;
    }
    super.dispose();
  }

  void _select(_Menu m) {
    setState(() => _selected = m);
    EmvilleNavigation.section.value = _destinations.indexOf(m);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_selected) {
      _Menu.home => const BookingsHubPage(embedded: true),
      _Menu.maintenance => FirstPage(role: widget.role),
      _Menu.reports => const GenerateReportsPage(embedded: true),
      _Menu.pmsTasks => const AddPmsTaskPage(),
      _Menu.pmsReports => const GeneratePmsReportPage(),
      _Menu.editPmsTasks => const EditPmsPage(),
      _Menu.accountsHub => AccountsHubPage(role: widget.role),
      _Menu.myProfile => const MyProfilePage(),
      _Menu.userManagement => const UserManagementPage(),
      _Menu.advancedSearch => const PmsAdvancedSearchPage(),
      _Menu.bookingsHub => const ExistingBookingPage(embedded: true),
    };

    final selectedIndex = _destinations.indexOf(_selected);
    final name = (_sb.auth.currentUser?.userMetadata?['full_name'] ??
            _sb.auth.currentUser?.userMetadata?['name'] ??
            'Emville')
        .toString();
    final initials = name
        .split(' ')
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0])
        .join()
        .toUpperCase();
    EmvilleNavigation.initials = initials;
    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
          child: SafeArea(
              child: ListView(children: [
        Padding(
            padding: const EdgeInsets.all(30),
            child: Image.asset(Emville.logo, height: 90)),
        if (widget.role != null)
          Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Signed in as ${widget.role}')),
        for (final item in <(_Menu, IconData, String)>[
          (_Menu.home, Icons.home_outlined, 'Home'),
          (_Menu.bookingsHub, Icons.event_available_outlined, 'Bookings'),
          (
            _Menu.accountsHub,
            Icons.account_balance_wallet_outlined,
            'Accounts'
          ),
          (_Menu.maintenance, Icons.handyman_outlined, 'Planned maintenance'),
          (_Menu.reports, Icons.insights_outlined, 'Reports'),
          (_Menu.pmsTasks, Icons.playlist_add, 'Add maintenance task'),
          (_Menu.pmsReports, Icons.assessment_outlined, 'Maintenance reports'),
          (_Menu.advancedSearch, Icons.search, 'Search maintenance'),
          (_Menu.myProfile, Icons.person_outline, 'My profile'),
          if (_isAdmin)
            (
              _Menu.editPmsTasks,
              Icons.edit_calendar_outlined,
              'Edit maintenance tasks'
            ),
          if (_isAdmin)
            (
              _Menu.userManagement,
              Icons.manage_accounts_outlined,
              'User management'
            ),
        ])
          ListTile(
              leading: Icon(item.$2),
              title: Text(item.$3),
              selected: _selected == item.$1,
              onTap: () => _select(item.$1)),
        const Divider(),
        ListTile(
            leading: const Icon(Icons.logout, size: 20),
            title: const Text('Sign out'),
            onTap: () async {
              Navigator.of(context).pop();
              await _sb.auth.signOut(scope: SignOutScope.local);
              await syncOneSignalIdentityAndRoleFromUsersV();
            }),
      ]))),
      body: SafeArea(
          bottom: false,
          child: Column(children: [
            RepaintBoundary(
                child: Builder(
                    builder: (context) => EmvilleHeader(
                        initials: initials,
                        onMenu: () => Scaffold.of(context).openDrawer()))),
            Expanded(child: body),
          ])),
      bottomNavigationBar: EmvilleBottomNav(
          selectedIndex: selectedIndex,
          onSelected: (i) {
            EmvilleNavigation.section.value = i;
            setState(() => _selected = _destinations[i]);
          }),
    );
  }
}

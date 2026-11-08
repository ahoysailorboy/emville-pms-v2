// lib/features/home/presentation/first_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/features/pms/upcoming_tasks_page.dart';
import 'package:emville_pms/features/pms/pending_tasks_page.dart';
import 'package:emville_pms/features/pms/postponed_tasks_page.dart';
import 'package:emville_pms/supabase_call.dart';
// ✅ Responsive barrel
import 'package:emville_pms/responsive/responsive.dart';

class FirstPage extends StatefulWidget {
  const FirstPage({super.key, this.role});
  final String? role; // "owner", "admin", "caretaker" etc.

  @override
  State<FirstPage> createState() => _FirstPageState();
}

class _FirstPageState extends State<FirstPage> {
  // Emville brand
  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  final _sb = Supabase.instance.client;

  String _fullName = 'User';
  int _upcoming = 0; // next 7 days incl. today
  int _pending = 0; // overdue (strictly before today), NOT postponed
  int _postponed = 0; // postponed == 'yes'
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUserAndCounts();
  }

  Future<void> _loadUserAndCounts() async {
    setState(() => _loading = true);

    // Resolve full name
    String name = 'User';
    final user = _sb.auth.currentUser;
    if (user != null) {
      try {
        final row = await supabaseCall(() async {
          return await _sb
              .from('users')
              .select('full_name')
              .eq('uid', user.id)
              .maybeSingle();
        });
        final n = row?['full_name'] as String?;
        if (n != null && n.trim().isNotEmpty) {
          name = n.trim();
        } else {
          final metaFull = user.userMetadata?['full_name'] as String?;
          final metaName = user.userMetadata?['name'] as String?;
          name =
              (metaFull ?? metaName ?? user.email?.split('@').first ?? 'User')
                  .toString()
                  .trim();
        }
      } catch (_) {
        final metaFull = user.userMetadata?['full_name'] as String?;
        final metaName = user.userMetadata?['name'] as String?;
        name = (metaFull ?? metaName ?? user.email?.split('@').first ?? 'User')
            .toString()
            .trim();
      }
    }

    // Date boundaries (DATE columns)
    final df = DateFormat('yyyy-MM-dd');
    final today = DateTime.now();
    final sevenDays = today.add(const Duration(days: 7));
    final todayStr = df.format(DateTime(today.year, today.month, today.day));
    final sevenStr = df.format(
      DateTime(sevenDays.year, sevenDays.month, sevenDays.day),
    );

    try {
      // Upcoming: next_due_date BETWEEN today..today+7 (inclusive)
      final upcomingRows = await supabaseCall(() async {
        return await _sb
            .from('main_pms_db')
            .select('id')
            .gte('next_due_date', todayStr)
            .lte('next_due_date', sevenStr)
            .eq('postponed', 'no');
      });
      final upcomingCount = (upcomingRows as List).length;

      // Pending: overdue (next_due_date < today) AND postponed='no'
      final pendingRows = await supabaseCall(() async {
        return await _sb
            .from('main_pms_db')
            .select('id')
            .lt('next_due_date', todayStr)
            .eq('postponed', 'no');
      });
      final pendingCount = (pendingRows as List).length;

      // Postponed: postponed='yes'
      final postponedRows = await supabaseCall(() async {
        return await _sb
            .from('main_pms_db')
            .select('id')
            .eq('postponed', 'yes');
      });
      final postponedCount = (postponedRows as List).length;

      if (!mounted) return;
      setState(() {
        _fullName = name;
        _upcoming = upcomingCount;
        _pending = pendingCount;
        _postponed = postponedCount;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // Re-usable tile (matches AccountsHubPage style)
  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
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
        onTap: onTap ??
            () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Coming soon')),
              );
            },
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

  String get _roleLabel {
    final r = widget.role ?? '';
    if (r == 'owner') return 'Owner';
    if (r == 'admin') return 'Admin';
    return 'User';
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    const emvilleGreen = _green;
    const emvilleGold = _gold;

    return _loading
        ? const Center(child: CircularProgressIndicator())
        : LayoutBuilder(
            builder: (context, constraints) {
              // Top welcome row (left: welcome+name constrained to 3/4 width)
              final maxWelcomeWidth = constraints.maxWidth * 0.75;

              return ListView(
                padding: EdgeInsets.all(rs.space(16)),
                children: [
                  // Greeting row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWelcomeWidth),
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: rs.font(20),
                              color: emvilleGreen,
                              fontWeight: FontWeight.w700,
                            ),
                            children: [
                              const TextSpan(text: 'Welcome '),
                              TextSpan(
                                text: _fullName,
                                style: const TextStyle(
                                  color: emvilleGreen,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: rs.space(10),
                          vertical: rs.space(6),
                        ),
                        decoration: BoxDecoration(
                          color: emvilleGreen,
                          borderRadius: BorderRadius.circular(rs.radius(12)),
                        ),
                        child: Text(
                          _roleLabel,
                          style: TextStyle(
                            color: emvilleGold,
                            fontWeight: FontWeight.bold,
                            fontSize: rs.font(12),
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: rs.space(16)),

                  // Tiles
                  _tile(
                    icon: Icons.upcoming,
                    title: 'Upcoming Tasks',
                    subtitle:
                        '$_upcoming job${_upcoming == 1 ? '' : 's'} due in next 7 days',
                    onTap: () {
                      Navigator.of(context)
                          .push(
                            MaterialPageRoute(
                              builder: (_) => const UpcomingTasksPage(),
                            ),
                          )
                          .then(
                              (_) => _loadUserAndCounts()); // refresh on return
                    },
                  ),
                  _tile(
                    icon: Icons.pending_actions_outlined,
                    title: 'Pending Tasks',
                    subtitle:
                        '$_pending overdue job${_pending == 1 ? '' : 's'}',
                    onTap: () {
                      Navigator.of(context)
                          .push(
                            MaterialPageRoute(
                              builder: (_) => const PendingTasksPage(),
                            ),
                          )
                          .then((_) => _loadUserAndCounts());
                    },
                  ),
                  _tile(
                    icon: Icons.schedule_outlined,
                    title: 'Postponed Tasks',
                    subtitle:
                        '$_postponed postponed job${_postponed == 1 ? '' : 's'}',
                    onTap: () {
                      Navigator.of(context)
                          .push(
                            MaterialPageRoute(
                              builder: (_) => const PostponedTasksPage(),
                            ),
                          )
                          .then((_) => _loadUserAndCounts());
                    },
                  ),
                ],
              );
            },
          );
  }
}

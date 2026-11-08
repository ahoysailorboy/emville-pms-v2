import 'package:flutter/material.dart';
import 'package:emville_pms/features/pms/work_done_report_page.dart';
import 'package:emville_pms/features/pms/work_planning_page.dart';
//import 'pms_advanced_search.dart';

// ✅ Shared responsive helper
import 'package:emville_pms/responsive/responsive.dart';

class GeneratePmsReportPage extends StatefulWidget {
  const GeneratePmsReportPage({super.key});

  @override
  State<GeneratePmsReportPage> createState() => _GeneratePmsReportPageState();
}

class _GeneratePmsReportPageState extends State<GeneratePmsReportPage> {
  // Emville brand
  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  Widget _tile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final rs = ResponsiveSize.of(context);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      margin: EdgeInsets.symmetric(vertical: rs.space(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(rs.space(16)),
          child: Row(
            children: [
              Container(
                height: rs.space(46),
                width: rs.space(46),
                decoration: BoxDecoration(
                  color: _green,
                  borderRadius: BorderRadius.circular(12),
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
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    const emvilleGreen = _green;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Generate PMS Report',
          style: TextStyle(
            fontSize: rs.font(22),
            fontWeight: FontWeight.w800,
            color: emvilleGreen,
          ),
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: EdgeInsets.all(rs.space(16)),
              children: [
                _tile(
                  context: context,
                  icon: Icons.task_alt_outlined,
                  title: 'Work Done Report',
                  subtitle: 'Create a PDF of all completed jobs in a period',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const WorkDoneReportPage()),
                    );
                  },
                ),
                _tile(
                  context: context,
                  icon: Icons.calendar_view_month_outlined,
                  title: 'Work Planner',
                  subtitle: 'Plan upcoming jobs (weekly • monthly • custom)',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const WorkPlanningPage()),
                    );
                  },
                ),
                /*  _tile(
                  context: context,
                  icon: Icons.manage_search_outlined,
                  title: 'Advanced Search',
                  subtitle: 'Filter & export PMS activity (coming soon)',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PmsAdvancedSearchPage(),
                      ),
                    );
                  },
                ), */
              ],
            ),
          ),
        ),
      ),
    );
  }
}

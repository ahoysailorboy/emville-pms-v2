import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/supabase_call.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'package:emville_pms/ui/emville_widgets.dart';
import 'maintenance_task_page.dart';

class PendingTasksPage extends StatefulWidget {
  const PendingTasksPage({super.key});
  @override
  State<PendingTasksPage> createState() => _PendingTasksPageState();
}

class _PendingTasksPageState extends State<PendingTasksPage> {
  late Future<List<Map<String, dynamic>>> _tasks;

  @override
  void initState() {
    super.initState();
    _tasks = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final rows = await supabaseCall(() => Supabase.instance.client
        .from('main_pms_db')
        .select('id,job_seq,task_name,job_description,next_due_date')
        .lt('next_due_date', today)
        .eq('postponed', 'no')
        .order('next_due_date'));
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _refresh() async {
    setState(() {
      _tasks = _load();
    });
    try {
      await _tasks;
    } catch (_) {/* The error state offers retry. */}
  }

  Future<void> _open(Map<String, dynamic> task) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MaintenanceTaskPage(id: task['id'].toString())));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => EmvillePage(
      section: 3,
      child: EmvilleBody(
          child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(22),
                  children: [
                    const EmvilleHeading('Pending tasks',
                        eyebrow: 'Property / maintenance',
                        subtitle: 'Overdue work that needs your attention.'),
                    const SizedBox(height: 22),
                    FutureBuilder<List<Map<String, dynamic>>>(
                        future: _tasks,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return EmvilleError(
                                message: 'Could not load pending tasks.',
                                onRetry: _refresh);
                          }
                          if (!snapshot.hasData) {
                            return const Padding(
                                padding: EdgeInsets.all(32),
                                child:
                                    Center(child: CircularProgressIndicator()));
                          }
                          final rows = snapshot.data!;
                          return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                EmvilleCallout(
                                    leading: Text('${rows.length}',
                                        style: Emville.heading(24)),
                                    trailing: const EmvilleTag('Overdue',
                                        overdue: true),
                                    child: Text(rows.isEmpty
                                        ? 'Everything is up to date.'
                                        : 'Select a task to review and follow up.')),
                                const EmvilleSectionTitle('Needs attention'),
                                if (rows.isEmpty)
                                  const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 24),
                                      child: Text('No overdue tasks.',
                                          style:
                                              TextStyle(color: Emville.muted))),
                                for (final task in rows)
                                  EmvilleTile(
                                      icon: Icons.assignment_late_outlined,
                                      title: task['task_name']?.toString() ??
                                          'Maintenance task',
                                      subtitle:
                                          'Job ${task['job_seq']} · Due ${_date(task['next_due_date'])}',
                                      onTap: () => _open(task)),
                              ]);
                        }),
                  ]))));

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null ? '—' : DateFormat('d MMM yyyy').format(date);
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'package:emville_pms/ui/emville_widgets.dart';
import 'package:emville_pms/features/pms/upcoming_tasks_page.dart';
import 'package:emville_pms/features/pms/pending_tasks_page.dart';
import 'package:emville_pms/features/pms/postponed_tasks_page.dart';
import 'package:emville_pms/features/pms/work_planning_page.dart';
import 'package:emville_pms/features/pms/add_pms_task.dart';

class FirstPage extends StatefulWidget {
  const FirstPage({super.key, this.role});
  final String? role;
  @override
  State<FirstPage> createState() => _FirstPageState();
}

class _FirstPageState extends State<FirstPage> {
  String _filter = 'All';
  bool _month = false;
  late Future<List<Map<String, dynamic>>> _work;
  @override
  void initState() {
    super.initState();
    _work = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = _month
        ? DateTime(today.year, today.month + 1, 0)
        : today.add(Duration(days: 7 - today.weekday));
    final rows = await Supabase.instance.client
        .from('main_pms_db')
        .select('id,task_name,job_description,next_due_date,task_interval')
        .eq('postponed', 'no')
        .lte('next_due_date', DateFormat('yyyy-MM-dd').format(end))
        .order('next_due_date');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _refresh() async {
    setState(() {
      _work = _load();
    });
    try {
      await _work;
    } catch (_) {}
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _refresh();
  }

  bool _overdue(Map<String, dynamic> row) {
    final due = DateTime.tryParse(row['next_due_date']?.toString() ?? '');
    final now = DateTime.now();
    return due != null && due.isBefore(DateTime(now.year, now.month, now.day));
  }

  @override
  Widget build(BuildContext context) => EmvilleBody(
      child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
              children: [
                const EmvilleHeading('Planned maintenance',
                    eyebrow: 'Care for the property',
                    subtitle: 'Keep every stay running beautifully.'),
                FutureBuilder<List<Map<String, dynamic>>>(
                    future: _work,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return EmvilleError(onRetry: _refresh);
                      }
                      final all = snapshot.data ?? [];
                      final overdue = all.where(_overdue).length;
                      final filtered = all
                          .where((r) =>
                              _filter == 'All' ||
                              _filter == 'Overdue' && _overdue(r) ||
                              _filter == 'Upcoming' && !_overdue(r))
                          .toList();
                      return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 18),
                            EmvilleCallout(
                                leading: Text(
                                    snapshot.hasData ? '$overdue' : '—',
                                    style: Emville.heading(18)),
                                trailing:
                                    const EmvilleTag('Overdue', overdue: true),
                                onTap: () => _open(const PendingTasksPage()),
                                child:
                                    const Text('Overdue tasks need attention')),
                            const SizedBox(height: 18),
                            DropdownButtonFormField<bool>(
                                initialValue: _month,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    isDense: true),
                                style: const TextStyle(
                                    fontFamily: 'Roboto',
                                    fontSize: 11,
                                    color: Emville.ink),
                                items: [
                                  const DropdownMenuItem(
                                      value: false, child: Text('This week')),
                                  DropdownMenuItem(
                                      value: true,
                                      child: Text(
                                          'This month · ${DateFormat('MMMM').format(DateTime.now())}'))
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    _month = value;
                                    _refresh();
                                  }
                                }),
                            const SizedBox(height: 20),
                            EmvilleTabs(
                                labels: const ['All', 'Overdue', 'Upcoming'],
                                selected: _filter,
                                onSelected: (value) =>
                                    setState(() => _filter = value)),
                            EmvilleSectionTitle('Your work plan',
                                trailing: Text('${filtered.length} tasks',
                                    style: const TextStyle(
                                        fontFamily: 'Roboto',
                                        fontSize: 10,
                                        color: Emville.muted))),
                            if (!snapshot.hasData)
                              const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Center(
                                      child: CircularProgressIndicator())),
                            if (snapshot.hasData && filtered.isEmpty)
                              const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 25),
                                  child: Text('No tasks due in this plan.',
                                      style: TextStyle(
                                          fontFamily: 'Roboto',
                                          color: Emville.muted,
                                          fontSize: 12))),
                            for (final row in filtered) _task(row),
                          ]);
                    }),
                const SizedBox(height: 20),
                FilledButton(
                    onPressed: () => _open(const AddPmsTaskPage()),
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, size: 16),
                          SizedBox(width: 8),
                          Text('Schedule task')
                        ])),
                const SizedBox(height: 8),
                Wrap(alignment: WrapAlignment.spaceBetween, children: [
                  TextButton(
                      onPressed: () => _open(const WorkPlanningPage()),
                      child: const Text('Export work plan',
                          style:
                              TextStyle(fontFamily: 'Roboto', fontSize: 11))),
                  TextButton(
                      onPressed: () => _open(const PostponedTasksPage()),
                      child: const Text('Postponed tasks',
                          style: TextStyle(fontFamily: 'Roboto', fontSize: 11)))
                ]),
              ])));
  Widget _task(Map<String, dynamic> row) {
    final due = DateTime.tryParse(row['next_due_date']?.toString() ?? '');
    final overdue = _overdue(row);
    return InkWell(
        onTap: () => _open(
            overdue ? const PendingTasksPage() : const UpcomingTasksPage()),
        child: Container(
            padding: const EdgeInsets.symmetric(vertical: 17),
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Emville.line))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  width: 39,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: Emville.sage,
                      borderRadius: BorderRadius.circular(11)),
                  child: Text(
                      due == null
                          ? '—'
                          : DateFormat('d\nMMM').format(due).toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: 'Roboto', fontSize: 10, height: 1.5))),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(row['task_name']?.toString() ?? 'Maintenance task',
                        style: const TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    Text(
                        '${row['task_interval'] ?? 'Scheduled'} · Due ${due == null ? '—' : DateFormat('d MMM').format(due)}',
                        style: const TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 10,
                            color: Emville.muted,
                            height: 1.5)),
                    const SizedBox(height: 7),
                    EmvilleTag(overdue ? 'Overdue' : 'Upcoming',
                        overdue: overdue)
                  ])),
              IconButton(
                  tooltip: 'Open task workflow',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _open(overdue
                      ? const PendingTasksPage()
                      : const UpcomingTasksPage()),
                  icon: const Icon(Icons.radio_button_unchecked,
                      size: 18, color: Emville.muted)),
            ])));
  }
}

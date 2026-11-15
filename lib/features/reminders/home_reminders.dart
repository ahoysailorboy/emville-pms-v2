import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/ui/emville_widgets.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'reminder_repository.dart';
import 'reminder_pages.dart';
import 'reminder_calendar.dart';

class HomeReminders extends StatefulWidget {
  const HomeReminders({super.key});
  @override
  State<HomeReminders> createState() => _HomeRemindersState();
}

class _HomeRemindersState extends State<HomeReminders>
    with WidgetsBindingObserver {
  final _repo = ReminderRepository(Supabase.instance.client);
  final _calendar = ReminderCalendar();
  late Future<List<Map<String, dynamic>>> _rows;
  String _calendarStatus = '';
  bool _syncing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _rows = _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await _repo.mine();
    unawaited(_sync(rows));
    unawaited(_repo.notify());
    return rows;
  }

  Future<void> _sync(List<Map<String, dynamic>> rows,
      {bool enable = false}) async {
    if (_syncing) return;
    _syncing = true;
    try {
      final message = await _calendar
          .sync(_repo.client.auth.currentUser!.id, rows, enable: enable);
      if (mounted) setState(() => _calendarStatus = message);
    } catch (_) {
      if (mounted) {
        setState(() => _calendarStatus =
            'Tasks are saved. Calendar sync needs attention; check permission and a writable phone calendar.');
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _rows = _load();
    });
    try {
      await _rows;
    } catch (_) {}
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        EmvilleSectionTitle('My tasks & reminders',
            trailing: IconButton(
                tooltip: 'Refresh reminders',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh, size: 18))),
        FutureBuilder(
            future: _rows,
            builder: (context, s) {
              if (s.hasError) {
                return EmvilleError(
                    message: 'Could not load reminders.', onRetry: _refresh);
              }
              if (!s.hasData) return const LinearProgressIndicator();
              final rows =
                  s.data!.where((r) => r['status'] != 'completed').toList();
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (rows.isEmpty)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Text('No outstanding tasks assigned to you.',
                              style: TextStyle(
                                  color: Emville.muted, fontSize: 12))),
                    for (final r in rows)
                      EmvilleTile(
                          icon: Icons.task_alt,
                          title: r['title'],
                          subtitle: reminderDate(r['due_at']),
                          trailing: EmvilleTag(
                              DateTime.parse(r['due_at'])
                                      .isBefore(DateTime.now())
                                  ? 'Overdue'
                                  : r['status'],
                              overdue: DateTime.parse(r['due_at'])
                                  .isBefore(DateTime.now())),
                          onTap: () => _open(ReminderDetailPage(id: r['id']))),
                    if (ReminderCalendar.supported)
                      TextButton.icon(
                          onPressed: () => _sync(s.data!, enable: true),
                          icon: const Icon(Icons.calendar_month_outlined,
                              size: 18),
                          label: const Text('Enable / sync phone calendar')),
                  ]);
            }),
        if (_calendarStatus.isNotEmpty && ReminderCalendar.supported)
          Text(_calendarStatus,
              style: const TextStyle(fontSize: 11, color: Emville.muted)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
            onPressed: () => _open(const ScheduleReminderPage()),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Schedule a task')),
      ]);
}

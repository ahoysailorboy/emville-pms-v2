import 'dart:async';
import 'reminder_calendar.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/ui/emville_widgets.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'reminder_repository.dart';

Future<DateTime?> pickReminderTime(
    BuildContext context, DateTime initial) async {
  final now = DateTime.now();
  final start = initial.isBefore(now) ? now : initial;
  final date = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateUtils.dateOnly(now),
      lastDate: DateTime(now.year + 5));
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
      context: context, initialTime: TimeOfDay.fromDateTime(start));
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

// Own-device calendar changes must also work when details were opened from a
// notification or after replacing the scheduling route (Home may be inactive).
Future<void> _syncOwnCalendar(ReminderRepository repo) async {
  try {
    final uid = repo.client.auth.currentUser?.id;
    if (uid != null && ReminderCalendar.supported) {
      await ReminderCalendar().sync(uid, await repo.mine());
    }
  } catch (_) {
    /* Task save succeeds independently; Home offers a sync retry. */
  }
}

String reminderDate(dynamic value) => DateFormat('d MMM yyyy · h:mm a')
    .format(DateTime.parse(value.toString()).toLocal());

class ScheduleReminderPage extends StatefulWidget {
  const ScheduleReminderPage({super.key});
  @override
  State<ScheduleReminderPage> createState() => _ScheduleReminderPageState();
}

class _ScheduleReminderPageState extends State<ScheduleReminderPage> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(),
      _description = TextEditingController();
  final _repo = ReminderRepository(Supabase.instance.client);
  late Future<List<Map<String, dynamic>>> _people;
  String? _assignee = Supabase.instance.client.auth.currentUser?.id;
  DateTime _due = DateTime.now().add(const Duration(hours: 1));
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _people = _repo.people();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _assignee == null) return;
    if (!_due.isAfter(DateTime.now())) {
      _message('Choose a future date and time.');
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await _repo.create(
          title: _title.text,
          description: _description.text,
          assignee: _assignee!,
          due: _due);
      unawaited(_syncOwnCalendar(_repo));
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => ReminderDetailPage(id: id)));
    } catch (_) {
      _message('Could not schedule task. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) => EmvillePage(
      section: 3,
      child: EmvilleBody(
          child: ListView(padding: const EdgeInsets.all(22), children: [
        const EmvilleHeading('Schedule a task',
            eyebrow: 'Property / reminders',
            subtitle:
                'Assign a task, choose a time and keep the conversation together.'),
        const SizedBox(height: 24),
        Form(
            key: _form,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                      controller: _title,
                      maxLength: 200,
                      decoration:
                          const InputDecoration(labelText: 'Task title'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Enter a task title'
                          : null),
                  const SizedBox(height: 16),
                  TextFormField(
                      controller: _description,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          labelText: 'Details / instructions')),
                  const SizedBox(height: 20),
                  FutureBuilder<List<Map<String, dynamic>>>(
                      future: _people,
                      builder: (context, s) {
                        if (s.hasError) {
                          return EmvilleError(
                              message: 'Could not load team members.',
                              onRetry: () =>
                                  setState(() => _people = _repo.people()));
                        }
                        if (!s.hasData) return const LinearProgressIndicator();
                        return DropdownButtonFormField<String>(
                            initialValue:
                                s.data!.any((p) => p['uid'] == _assignee)
                                    ? _assignee
                                    : null,
                            decoration:
                                const InputDecoration(labelText: 'Assign to'),
                            isExpanded: true,
                            items: s.data!
                                .map((p) => DropdownMenuItem(
                                    value: p['uid'].toString(),
                                    child: Text(
                                        '${p['full_name']}${p['uid'] == Supabase.instance.client.auth.currentUser?.id ? ' (me)' : ''}')))
                                .toList(),
                            validator: (v) =>
                                v == null ? 'Choose a person' : null,
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _assignee = v));
                      }),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(reminderDate(_due)),
                      onPressed: _busy
                          ? null
                          : () async {
                              final date =
                                  await pickReminderTime(context, _due);
                              if (date != null && mounted) {
                                setState(() => _due = date);
                              }
                            }),
                  const SizedBox(height: 12),
                  const Text(
                      'The assignee will see this on Home. Calendar reminders sync on their phone after calendar access is enabled.',
                      style: TextStyle(color: Emville.muted, fontSize: 12)),
                  const SizedBox(height: 24),
                  FilledButton(
                      onPressed: _busy ? null : _save,
                      child: Text(_busy ? 'Saving…' : 'Schedule task')),
                ])),
      ])));
}

class ReminderDetailPage extends StatefulWidget {
  const ReminderDetailPage({super.key, required this.id});
  final String id;
  @override
  State<ReminderDetailPage> createState() => _ReminderDetailPageState();
}

class _ReminderDetailPageState extends State<ReminderDetailPage> {
  final _repo = ReminderRepository(Supabase.instance.client);
  final _remarks = TextEditingController();
  late Future<
      (
        Map<String, dynamic>,
        List<Map<String, dynamic>>,
        List<Map<String, dynamic>>
      )> _data;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data = _load();
  }

  Future<
      (
        Map<String, dynamic>,
        List<Map<String, dynamic>>,
        List<Map<String, dynamic>>
      )> _load() async {
    final values = await Future.wait(
        [_repo.get(widget.id), _repo.activity(widget.id), _repo.people()]);
    return (
      values[0] as Map<String, dynamic>,
      values[1] as List<Map<String, dynamic>>,
      values[2] as List<Map<String, dynamic>>
    );
  }

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _act(Map<String, dynamic> row, String action) async {
    if (_remarks.text.trim().isEmpty) {
      _message('Add remarks before continuing.');
      return;
    }
    DateTime? due;
    if (action == 'postponed') {
      due = await pickReminderTime(
          context, DateTime.now().add(const Duration(days: 1)));
      if (due == null || !mounted) return;
      if (!due.isAfter(DateTime.now())) {
        _message('Choose a future follow-up time.');
        return;
      }
    }
    if (action == 'completed') {
      final confirm = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text('Complete this task?'),
                  content: const Text(
                      'Your remarks will be saved and the team notified.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Complete'))
                  ]));
      if (confirm != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await _repo.update(row, action, _remarks.text, due: due);
      unawaited(_syncOwnCalendar(_repo));
      _remarks.clear();
      if (mounted) setState(_reload);
    } catch (_) {
      _message('Could not save. Refresh to check for changes, then try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) => EmvillePage(
      section: 3,
      child: EmvilleBody(
          child: FutureBuilder(
              future: _data,
              builder: (context, s) {
                if (s.hasError) {
                  return EmvilleError(
                      message: 'Could not load this task.',
                      onRetry: () => setState(_reload));
                }
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final (r, activity, people) = s.data!;
                String name(dynamic id) =>
                    people
                        .where((p) => p['uid'] == id)
                        .map((p) => p['full_name'].toString())
                        .firstOrNull ??
                    'Team member';
                return RefreshIndicator(
                    onRefresh: () async {
                      setState(_reload);
                      await _data;
                    },
                    child:
                        ListView(padding: const EdgeInsets.all(22), children: [
                      EmvilleHeading(r['title'],
                          eyebrow: 'Property / task details'),
                      const SizedBox(height: 20),
                      Align(
                          alignment: Alignment.centerLeft,
                          child: EmvilleTag(r['status'])),
                      const SizedBox(height: 18),
                      Text(r['description'] ?? ''),
                      const SizedBox(height: 18),
                      Text('Assigned to ${name(r['assigned_to'])}'),
                      const SizedBox(height: 8),
                      Text('Created by ${name(r['created_by'])}'),
                      const SizedBox(height: 8),
                      Text('Due ${reminderDate(r['due_at'])}'),
                      const EmvilleSectionTitle('Conversation'),
                      for (final a in activity)
                        Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: const BoxDecoration(
                                border: Border(
                                    bottom: BorderSide(color: Emville.line))),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${name(a['actor'])} · ${a['action']}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 5),
                                  Text(reminderDate(a['created_at']),
                                      style: const TextStyle(
                                          fontSize: 11, color: Emville.muted)),
                                  if ((a['remarks'] ?? '').isNotEmpty)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(a['remarks'])),
                                  if (a['due_at'] != null)
                                    Text(
                                        'Scheduled: ${reminderDate(a['due_at'])}'),
                                ])),
                      if (r['status'] != 'completed') ...[
                        const SizedBox(height: 24),
                        TextField(
                            controller: _remarks,
                            maxLines: 3,
                            decoration:
                                const InputDecoration(labelText: 'Remarks')),
                        const SizedBox(height: 16),
                        OutlinedButton(
                            onPressed: _busy ? null : () => _act(r, 'remark'),
                            child: const Text('Add remark')),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                            onPressed:
                                _busy ? null : () => _act(r, 'postponed'),
                            icon: const Icon(Icons.snooze),
                            label: const Text('Postpone / follow up')),
                        const SizedBox(height: 8),
                        FilledButton(
                            onPressed:
                                _busy ? null : () => _act(r, 'completed'),
                            child: Text(_busy ? 'Saving…' : 'Complete task')),
                      ],
                    ]));
              })));
}

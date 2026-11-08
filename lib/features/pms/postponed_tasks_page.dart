// lib/features/pms/postponed_tasks_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/supabase_call.dart';
// ✅ Reuse shared responsive helper
import 'package:emville_pms/responsive/responsive.dart';

class PostponedTasksPage extends StatefulWidget {
  const PostponedTasksPage({super.key});

  @override
  State<PostponedTasksPage> createState() => _PostponedTasksPageState();
}

class _PostponedTasksPageState extends State<PostponedTasksPage> {
  // Emville brand
  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  final _sb = Supabase.instance.client;
  final _dfApi = DateFormat('yyyy-MM-dd'); // DB
  final _dfUi = DateFormat('dd MMM yyyy'); // UI

  final Set<int> _expanded = {};
  Future<List<TaskRow>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _loadPostponed();
  }

  Future<List<TaskRow>> _loadPostponed() async {
    final rows = await supabaseCall(() async {
      return await _sb
          .from('main_pms_db')
          .select(
            'job_seq, task_name, job_description, last_done_date, remarks, next_due_date, task_interval, custom_interval, postponed, done_by, user_uuid, attachment_path',
          )
          .eq('postponed', 'yes')
          .order('next_due_date', ascending: true);
    });

    return ((rows) as List).map<TaskRow>((m) {
      return TaskRow(
        jobSeq: (m['job_seq'] as num).toInt(),
        taskName: (m['task_name'] as String?) ?? '',
        description: (m['job_description'] as String?) ?? '',
        lastDoneDate: (m['last_done_date'] as String?) ?? '',
        remarks: (m['remarks'] as String?) ?? '',
        nextDueDate: (m['next_due_date'] as String?) ?? '',
        taskInterval: (m['task_interval'] as String?) ?? 'monthly',
        customIntervalDays: (m['custom_interval'] as num?)?.toInt(),
        doneBy: m['done_by'] as String?,
        userUuid: m['user_uuid'] as String?,
        attachmentPath: m['attachment_path'] as String?,
      );
    }).toList();
  }

  Future<void> _refreshList() async {
    setState(() {
      _expanded.clear();
      _future = _loadPostponed();
    });
  }

  Future<String> _currentUserFullName() async {
    final u = _sb.auth.currentUser;
    if (u == null) return 'User';
    try {
      final row = await supabaseCall(() async {
        return await _sb
            .from('users')
            .select('full_name')
            .eq('uid', u.id)
            .maybeSingle();
      });
      final n = row?['full_name'] as String?;
      if (n != null && n.trim().isNotEmpty) return n.trim();
    } catch (_) {}
    final metaFull = u.userMetadata?['full_name'] as String?;
    final metaName = u.userMetadata?['name'] as String?;
    return (metaFull ?? metaName ?? u.email?.split('@').first ?? 'User').trim();
  }

  DateTime _computeNextDue(DateTime from, String interval, int? customDays) {
    switch (interval.toLowerCase()) {
      case 'weekly':
        return from.add(const Duration(days: 7));
      case 'monthly':
        return DateTime(from.year, from.month + 1, from.day);
      case 'annually':
      case 'yearly':
        return DateTime(from.year + 1, from.month, from.day);
      case 'custom':
        final d = (customDays ?? 1);
        return from.add(Duration(days: d > 0 ? d : 1));
      default:
        return DateTime(from.year, from.month + 1, from.day);
    }
  }

  String _intervalLabel(String interval, int? customDays) {
    final i = interval.toLowerCase();
    if (i == 'custom') {
      final d = (customDays ?? 0);
      return d > 0 ? 'Custom ($d days)' : 'Custom';
    }
    if (i == 'annually') return 'Annually';
    if (i == 'yearly') return 'Yearly';
    return '${i[0].toUpperCase()}${i.substring(1)}'; // Weekly/Monthly etc.
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Postponed Tasks',
          style: TextStyle(fontSize: rs.font(20), fontWeight: FontWeight.w700),
        ),
        backgroundColor: _green,
        foregroundColor: _gold,
      ),
      body: FutureBuilder<List<TaskRow>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data ?? const <TaskRow>[];
          if (rows.isEmpty) {
            return Center(
              child: Text(
                'No postponed tasks',
                style: TextStyle(fontSize: rs.font(14)),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refreshList,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView.separated(
                  padding: EdgeInsets.all(rs.space(12)),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => SizedBox(height: rs.space(8)),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    return _TaskTile(
                      key: ValueKey(r.jobSeq),
                      row: r,
                      dfApi: _dfApi,
                      dfUi: _dfUi,
                      computeNextDue: _computeNextDue,
                      intervalLabel: _intervalLabel(
                        r.taskInterval,
                        r.customIntervalDays,
                      ),
                      currentUserFullName: _currentUserFullName,
                      expanded: _expanded.contains(r.jobSeq),
                      onToggleExpanded: (open) {
                        setState(() {
                          if (open) {
                            _expanded.add(r.jobSeq);
                          } else {
                            _expanded.remove(r.jobSeq);
                          }
                        });
                      },
                      onChanged: _refreshList,
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tile (no GlobalKey usage)
// ─────────────────────────────────────────────────────────────────────────────
class _TaskTile extends StatefulWidget {
  const _TaskTile({
    super.key,
    required this.row,
    required this.dfApi,
    required this.dfUi,
    required this.computeNextDue,
    required this.intervalLabel,
    required this.currentUserFullName,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onChanged,
  });

  final TaskRow row;
  final DateFormat dfApi;
  final DateFormat dfUi;
  final DateTime Function(DateTime, String, int?) computeNextDue;
  final String intervalLabel;
  final Future<String> Function() currentUserFullName;

  final bool expanded;
  final ValueChanged<bool> onToggleExpanded;
  final Future<void> Function() onChanged;

  @override
  State<_TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<_TaskTile> {
  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  final _sb = Supabase.instance.client;

  DateTime _date = DateTime.now();
  final _remarksCtrl = TextEditingController();
  File? _photo;
  bool _busy = false;

  @override
  void dispose() {
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    // Start at day-after-last-done (if exists), up to today
    final lastDone = widget.row.lastDoneDate.isNotEmpty
        ? DateTime.parse(widget.row.lastDoneDate)
        : null;
    DateTime firstDate = DateTime(2020, 1, 1);
    if (lastDone != null) {
      firstDate = DateTime(
        lastDone.year,
        lastDone.month,
        lastDone.day,
      ).add(const Duration(days: 1));
    }
    final now = DateTime.now();
    if (firstDate.isAfter(now)) firstDate = now;

    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(firstDate) ? firstDate : _date,
      firstDate: firstDate,
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final x = await ImagePicker().pickImage(source: source, imageQuality: 80);
    if (x != null) setState(() => _photo = File(x.path));
  }

  Future<void> _submit() async {
    final remarks = _remarksCtrl.text.trim();
    if (remarks.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Remarks are required')));
      return;
    }

    final lastDone = widget.row.lastDoneDate.isNotEmpty
        ? DateTime.parse(widget.row.lastDoneDate)
        : null;
    if (lastDone != null &&
        _date.isBefore(lastDone.add(const Duration(days: 1)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Date cannot be earlier than the last done date (${widget.dfUi.format(lastDone)})',
          ),
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Update'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Job: ${widget.row.jobSeq} • ${widget.row.taskName}'),
            Text('Date: ${widget.dfUi.format(_date)}'),
            Text('Remarks: $remarks'),
            if (_photo != null) const SizedBox(height: 8),
            if (_photo != null) const Text('A photo will be uploaded.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Edit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      final user = _sb.auth.currentUser;
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Not signed in')));
        }
        return;
      }

      // 1) Archive previous state to maintenance_history
      await supabaseCall(() async {
        return await _sb.from('maintenance_history').insert({
          'job_id': widget.row.jobSeq,
          'task_name': widget.row.taskName,
          'done_date': widget.row.lastDoneDate,
          'done_by': widget.row.doneBy ?? '—',
          'user_uuid': widget.row.userUuid ?? user.id,
          'remarks': widget.row.remarks.isNotEmpty ? widget.row.remarks : '—',
          'attachment_path': widget.row.attachmentPath,
          'updated_at': DateTime.now().toIso8601String(),
        });
      });

      // 2) Compute new values
      final fullName = await widget.currentUserFullName();
      final newLastDone = widget.dfApi.format(_date);
      final newNextDue = widget.dfApi.format(
        widget.computeNextDue(
          _date,
          widget.row.taskInterval,
          widget.row.customIntervalDays,
        ),
      );

      String? newAttachmentPath;
      if (_photo != null) {
        final key =
            'pms/${user.id}/${widget.row.jobSeq}-${DateTime.now().millisecondsSinceEpoch}.jpg';
        try {
          await supabaseCall(() async {
            return await _sb.storage
                .from('maintenance_done')
                .upload(key, _photo!);
          });
          newAttachmentPath = key;
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Saved without photo (upload error): $e')),
            );
          }
        }
      }

      // 3) Update main_pms_db and mark postponed = 'no'
      await supabaseCall(() async {
        return await _sb.from('main_pms_db').update({
          'last_done_date': newLastDone,
          'next_due_date': newNextDue,
          'remarks': remarks,
          'done_by': fullName,
          'user_uuid': user.id,
          'updated_date': DateTime.now().toIso8601String(),
          if (newAttachmentPath != null) 'attachment_path': newAttachmentPath,
          'postponed': 'no',
        }).eq('job_seq', widget.row.jobSeq);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Task updated')));

      // Collapse and refresh
      widget.onToggleExpanded(false);
      await widget.onChanged();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update failed: ${e.message}')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Something went wrong')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    final r = widget.row;
    final lastDoneUi = r.lastDoneDate.isEmpty
        ? '—'
        : widget.dfUi.format(DateTime.parse(r.lastDoneDate));
    final dueUi = r.nextDueDate.isEmpty
        ? '—'
        : widget.dfUi.format(DateTime.parse(r.nextDueDate));

    return Card(
      key: ValueKey('card_${r.jobSeq}'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: _gold.withValues(alpha: 0.15),
          highlightColor: _gold.withValues(alpha: 0.08),
        ),
        child: ExpansionTile(
          initiallyExpanded: widget.expanded,
          onExpansionChanged: widget.onToggleExpanded,
          tilePadding: EdgeInsets.symmetric(
            horizontal: rs.space(16),
            vertical: rs.space(6),
          ),
          leading: Container(
            height: rs.space(44),
            width: rs.space(44),
            decoration: BoxDecoration(
              color: _green,
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                Icon(Icons.schedule_outlined, color: _gold, size: rs.icon(22)),
          ),
          title: Text(
            r.taskName,
            style: TextStyle(
              color: _green,
              fontWeight: FontWeight.bold,
              fontSize: rs.font(16),
            ),
          ),
          subtitle: Text(
            'Job ${r.jobSeq} • Due: $dueUi',
            style: TextStyle(
                color: _green.withValues(alpha: 0.75), fontSize: rs.font(13)),
          ),
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                rs.space(16),
                0,
                rs.space(16),
                rs.space(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv('Job ID', '${r.jobSeq}', rs),
                  _kv('Task Name', r.taskName, rs),
                  _kv(
                    'Task Description',
                    r.description.isEmpty ? '—' : r.description,
                    rs,
                  ),
                  _kv('Interval', widget.intervalLabel, rs),
                  _kv('Last Done', lastDoneUi, rs),
                  _kv('Previous Remarks', r.remarks.isEmpty ? '—' : r.remarks,
                      rs),
                  SizedBox(height: rs.space(12)),
                  const Divider(),
                  SizedBox(height: rs.space(12)),

                  // Date picker row
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.event_available_outlined,
                      color: _gold,
                      size: rs.icon(22),
                    ),
                    title: Text(
                      'Date',
                      style: TextStyle(
                        color: _green,
                        fontWeight: FontWeight.w700,
                        fontSize: rs.font(14),
                      ),
                    ),
                    subtitle: Text(
                      widget.dfUi.format(_date),
                      style: TextStyle(color: _green, fontSize: rs.font(13)),
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.date_range,
                          color: _green, size: rs.icon(22)),
                      onPressed: _busy ? null : _pickDate,
                    ),
                  ),
                  SizedBox(height: rs.space(12)),

                  // Remarks
                  TextField(
                    controller: _remarksCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Remarks (required)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                  SizedBox(height: rs.space(12)),

                  // Photo buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _pickPhoto(ImageSource.camera),
                          icon: Icon(Icons.photo_camera_outlined,
                              size: rs.icon(20)),
                          label: Text('Camera',
                              style: TextStyle(fontSize: rs.font(13))),
                        ),
                      ),
                      SizedBox(width: rs.space(8)),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _pickPhoto(ImageSource.gallery),
                          icon: Icon(Icons.photo_library_outlined,
                              size: rs.icon(20)),
                          label: Text('Gallery',
                              style: TextStyle(fontSize: rs.font(13))),
                        ),
                      ),
                    ],
                  ),
                  if (_photo != null) ...[
                    SizedBox(height: rs.space(12)),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(_photo!, height: rs.space(160)),
                    ),
                  ],
                  SizedBox(height: rs.space(16)),

                  // Actions (no Postpone button here)
                  Row(
                    children: [
                      const Spacer(),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: _gold,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _busy ? null : _submit,
                        icon: _busy
                            ? SizedBox(
                                height: rs.space(18),
                                width: rs.space(18),
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _gold,
                                  ),
                                ),
                              )
                            : Icon(Icons.save_outlined, size: rs.icon(20)),
                        label: Text(
                          'Submit',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: rs.font(14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, ResponsiveSize rs) {
    return Padding(
      padding: EdgeInsets.only(bottom: rs.space(6)),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$k: ',
              style: TextStyle(
                color: _green,
                fontWeight: FontWeight.w700,
                fontSize: rs.font(13),
              ),
            ),
            TextSpan(
              text: v,
              style: TextStyle(
                  color: _green.withValues(alpha: 0.9), fontSize: rs.font(13)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Local model
// ─────────────────────────────────────────────────────────────────────────────
class TaskRow {
  TaskRow({
    required this.jobSeq,
    required this.taskName,
    required this.description,
    required this.lastDoneDate, // yyyy-MM-dd
    required this.remarks,
    required this.nextDueDate, // yyyy-MM-dd
    required this.taskInterval, // weekly | monthly | annually | custom
    required this.customIntervalDays,
    required this.doneBy,
    required this.userUuid,
    required this.attachmentPath,
  });

  final int jobSeq;
  final String taskName;
  final String description;
  String lastDoneDate;
  String remarks;
  final String nextDueDate;
  final String taskInterval;
  final int? customIntervalDays;
  final String? doneBy;
  final String? userUuid;
  String? attachmentPath;
}

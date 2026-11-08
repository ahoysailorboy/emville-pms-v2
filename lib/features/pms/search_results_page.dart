// lib/features/pms/search_results_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ✅ same helpers used elsewhere
import 'package:emville_pms/supabase_call.dart';
import 'package:emville_pms/responsive/responsive.dart';

/// Detail page for a single PMS job selected from Advanced Search results.
/// Expects the *job row* (from main_pms_db) to be passed in `job`.
class SearchResultDetailPage extends StatefulWidget {
  const SearchResultDetailPage({super.key, required this.job});

  /// A row from main_pms_db containing at least:
  /// job_seq, task_name, job_description, task_interval, custom_interval,
  /// last_done_date, next_due_date, done_by, remarks, attachment_path
  final Map<String, dynamic> job;

  @override
  State<SearchResultDetailPage> createState() => _SearchResultDetailPageState();
}

class _SearchResultDetailPageState extends State<SearchResultDetailPage> {
  // Emville brand
  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  final _sb = Supabase.instance.client;
  final _dfApi = DateFormat('yyyy-MM-dd');
  final _dfUi = DateFormat('dd MMM yyyy');

  bool _loading = true;
  List<_HistItem> _history = [];

  // ----- job fields -----
  int get _jobSeq => (widget.job['job_seq'] as num).toInt();
  String get _taskName => (widget.job['task_name'] as String?) ?? '';
  String get _description => (widget.job['job_description'] as String?) ?? '';
  String get _intervalRaw =>
      (widget.job['task_interval'] as String?) ?? 'monthly';
  int? get _customDays => (widget.job['custom_interval'] as num?)?.toInt();
  String get _lastDone => (widget.job['last_done_date'] as String?) ?? '';
  String get _nextDue => (widget.job['next_due_date'] as String?) ?? '';
  String get _doneBy => (widget.job['done_by'] as String?) ?? '';
  String get _remarks => (widget.job['remarks'] as String?) ?? '';
  String? get _attachmentPath => widget.job['attachment_path'] as String?;

  // ----- form state (same behavior as PendingTasks) -----
  DateTime _date = DateTime.now();
  final _remarksCtrl = TextEditingController();
  File? _photo;
  bool _busy = false;

  String get _intervalPretty {
    final s = _intervalRaw.toLowerCase();
    if (s == 'custom') {
      final d = _customDays ?? 1;
      return 'Every $d day${d == 1 ? '' : 's'}';
    }
    if (s == 'annually' || s == 'yearly') return 'Annually';
    return s[0].toUpperCase() + s.substring(1); // Weekly / Monthly
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

  @override
  void initState() {
    super.initState();
    _remarksCtrl.text = '';
    _loadHistory();
  }

  @override
  void dispose() {
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    try {
      // 1) Build a "current" item from main_pms_db (the latest)
      final nowItem = _HistItem(
        date: _lastDone,
        doneBy: _doneBy.isEmpty ? '—' : _doneBy,
        remarks: _remarks.isEmpty ? '—' : _remarks,
        attachmentPath: _attachmentPath,
        source: 'current',
      );

      // 2) Fetch maintenance_history for this job
      final rows = await supabaseCall(() async {
        return await _sb
            .from('maintenance_history')
            .select('done_date, done_by, remarks, attachment_path')
            .eq('job_id', _jobSeq)
            .order('done_date', ascending: false);
      });

      final hist = <_HistItem>[];
      for (final m in (rows as List)) {
        hist.add(
          _HistItem(
            date: (m['done_date'] as String?) ?? '',
            doneBy: (m['done_by'] as String?)?.trim().isNotEmpty == true
                ? (m['done_by'] as String)
                : '—',
            remarks: (m['remarks'] as String?)?.trim().isNotEmpty == true
                ? (m['remarks'] as String)
                : '—',
            attachmentPath: m['attachment_path'] as String?,
            source: 'history',
          ),
        );
      }

      final merged = <_HistItem>[];
      if (nowItem.date.trim().isNotEmpty) merged.add(nowItem);
      merged.addAll(hist);

      if (!mounted) return;
      setState(() {
        _history = merged;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _history = const [];
        _loading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to load history')));
    }
  }

  Future<String?> _signedUrl(String path, {int seconds = 600}) async {
    try {
      return await supabaseCall(() async {
        return await _sb.storage
            .from('maintenance_done')
            .createSignedUrl(path, seconds);
      });
    } catch (_) {
      return null;
    }
  }

  Future<void> _showImageDialog(String path) async {
    final url = await _signedUrl(path, seconds: 900);
    if (!mounted || url == null) return;
    final rs = ResponsiveSize.of(context);
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: EdgeInsets.all(rs.space(16)),
        child: InteractiveViewer(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(url, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  // ----- form actions (same flow as PendingTasks) -----
  Future<void> _pickDate() async {
    final lastDone = _lastDone.isNotEmpty ? DateTime.parse(_lastDone) : null;
    DateTime firstDate = DateTime(2020, 1, 1);
    if (lastDone != null) {
      firstDate = DateTime(lastDone.year, lastDone.month, lastDone.day)
          .add(const Duration(days: 1));
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

  Future<void> _postpone() async {
    setState(() => _busy = true);
    try {
      await supabaseCall(() async {
        return await _sb.from('main_pms_db').update({
          'postponed': 'yes',
          'updated_date': DateTime.now().toIso8601String(),
        }).eq('job_seq', _jobSeq);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Task postponed')));
      await _reloadAfterChange();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Postpone failed: ${e.message}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final remarks = _remarksCtrl.text.trim();
    if (remarks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remarks are required')),
      );
      return;
    }

    final lastDone = _lastDone.isNotEmpty ? DateTime.parse(_lastDone) : null;
    if (lastDone != null &&
        _date.isBefore(lastDone.add(const Duration(days: 1)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Date cannot be earlier than the last done date (${_dfUi.format(lastDone)})',
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
            Text('Job: $_jobSeq • $_taskName'),
            Text('Date: ${_dfUi.format(_date)}'),
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
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Not signed in')));
        }
        return;
      }

      // 1) Archive previous to maintenance_history
      await supabaseCall(() async {
        return await _sb.from('maintenance_history').insert({
          'job_id': _jobSeq,
          'task_name': _taskName,
          'done_date': _lastDone,
          'done_by': _doneBy.isEmpty ? '—' : _doneBy,
          'user_uuid': user.id,
          'remarks': _remarks.isNotEmpty ? _remarks : '—',
          'attachment_path': _attachmentPath,
          'updated_at': DateTime.now().toIso8601String(),
        });
      });

      // 2) Compute new values
      final fullName = await _currentUserFullName();
      final newLastDone = _dfApi.format(_date);
      final newNextDue =
          _dfApi.format(_computeNextDue(_date, _intervalRaw, _customDays));

      String? newAttachmentPath;
      if (_photo != null) {
        final key =
            'pms/${user.id}/$_jobSeq-${DateTime.now().millisecondsSinceEpoch}.jpg';
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

      // 3) Update main_pms_db (and clear postponed)
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
        }).eq('job_seq', _jobSeq);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Task updated')));
      await _reloadAfterChange();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Update failed: ${e.message}')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Something went wrong')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reloadAfterChange() async {
    // Refresh the local "job" map with latest values so the header details update
    final refreshed = await supabaseCall(() async {
      final rows = await _sb
          .from('main_pms_db')
          .select(
            'job_seq, task_name, job_description, task_interval, custom_interval, last_done_date, next_due_date, done_by, remarks, attachment_path',
          )
          .eq('job_seq', _jobSeq)
          .limit(1);
      return (rows as List).isNotEmpty ? rows.first : null;
    });
    if (mounted && refreshed != null) {
      setState(() => widget.job.addAll(refreshed));
    }
    await _loadHistory();
    _remarksCtrl.clear();
    _photo = null;
  }

  Widget _kv(String k, String v, ResponsiveSize rs) => Padding(
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
                  color: _green.withValues(alpha: 0.9),
                  fontSize: rs.font(13),
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    final lastDoneUi =
        _lastDone.isEmpty ? '—' : _dfUi.format(DateTime.parse(_lastDone));
    final nextDueUi =
        _nextDue.isEmpty ? '—' : _dfUi.format(DateTime.parse(_nextDue));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Search Results',
          style: TextStyle(fontSize: rs.font(18), fontWeight: FontWeight.w700),
        ),
        backgroundColor: _green,
        foregroundColor: _gold,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(rs.space(16)),
              children: [
                // ── TOP EXPANSION TILE (details + update form) ────────────────
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                      splashColor: _gold.withValues(alpha: 0.12),
                      highlightColor: _gold.withValues(alpha: 0.06),
                    ),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.symmetric(
                        horizontal: rs.space(16),
                        vertical: rs.space(8),
                      ),
                      leading: Container(
                        height: rs.space(44),
                        width: rs.space(44),
                        decoration: BoxDecoration(
                          color: _green,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.manage_search,
                            color: _gold, size: rs.icon(22)),
                      ),
                      title: Text(
                        _taskName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _green,
                          fontSize: rs.font(18),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        'Job $_jobSeq • Due: $nextDueUi',
                        style: TextStyle(
                          color: _green.withValues(alpha: 0.8),
                          fontSize: rs.font(13),
                        ),
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
                              _kv('Interval', _intervalPretty, rs),
                              if (_description.trim().isNotEmpty)
                                _kv('Description', _description, rs),
                              _kv('Last done', lastDoneUi, rs),
                              _kv('Next due', nextDueUi, rs),
                              if (_doneBy.trim().isNotEmpty)
                                _kv('Done by', _doneBy, rs),
                              if (_remarks.trim().isNotEmpty)
                                _kv('Remarks', _remarks, rs),

                              // Current attachment (clickable)
                              if (_attachmentPath != null &&
                                  _attachmentPath!.trim().isNotEmpty)
                                Padding(
                                  padding: EdgeInsets.only(top: rs.space(8)),
                                  child: Row(
                                    children: [
                                      Icon(Icons.attachment,
                                          color: _green, size: rs.icon(18)),
                                      SizedBox(width: rs.space(8)),
                                      TextButton(
                                        onPressed: () =>
                                            _showImageDialog(_attachmentPath!),
                                        child: const Text('View current photo'),
                                      ),
                                    ],
                                  ),
                                ),

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
                                  _dfUi.format(_date),
                                  style: TextStyle(
                                      color: _green, fontSize: rs.font(13)),
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
                                          : () =>
                                              _pickPhoto(ImageSource.camera),
                                      icon: const Icon(
                                          Icons.photo_camera_outlined),
                                      label: const Text('Camera'),
                                    ),
                                  ),
                                  SizedBox(width: rs.space(8)),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _busy
                                          ? null
                                          : () =>
                                              _pickPhoto(ImageSource.gallery),
                                      icon: const Icon(
                                          Icons.photo_library_outlined),
                                      label: const Text('Gallery'),
                                    ),
                                  ),
                                ],
                              ),
                              if (_photo != null) ...[
                                SizedBox(height: rs.space(12)),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(_photo!,
                                      height: rs.space(160)),
                                ),
                              ],
                              SizedBox(height: rs.space(16)),

                              // Actions
                              Row(
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _busy ? null : _postpone,
                                    icon: const Icon(Icons.snooze),
                                    label: const Text('Postpone'),
                                  ),
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
                                            child:
                                                const CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                      _gold),
                                            ),
                                          )
                                        : const Icon(Icons.save_outlined),
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
                ),

                SizedBox(height: rs.space(16)),

                // ── HISTORY (each image clickable) ────────────────────────────
                Text(
                  'History',
                  style: TextStyle(
                    color: _green,
                    fontSize: rs.font(16),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: rs.space(8)),
                if (_history.isEmpty)
                  Text('No history found',
                      style: TextStyle(color: _green, fontSize: rs.font(14)))
                else
                  ..._history.map((h) {
                    final dateUi = h.date.isEmpty
                        ? '—'
                        : _dfUi.format(DateTime.parse(h.date));
                    return Card(
                      elevation: 1.5,
                      margin: EdgeInsets.symmetric(vertical: rs.space(6)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                          splashColor: _gold.withValues(alpha: 0.12),
                          highlightColor: _gold.withValues(alpha: 0.06),
                        ),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.symmetric(
                            horizontal: rs.space(16),
                            vertical: rs.space(6),
                          ),
                          title: Text(
                            dateUi,
                            style: TextStyle(
                              color: _green,
                              fontWeight: FontWeight.w700,
                              fontSize: rs.font(14),
                            ),
                          ),
                          subtitle: Text(
                            'Done by: ${h.doneBy}',
                            style: TextStyle(
                              color: _green.withValues(alpha: 0.8),
                              fontSize: rs.font(13),
                            ),
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
                                  _kv('Remarks',
                                      h.remarks.isEmpty ? '—' : h.remarks, rs),
                                  if (h.attachmentPath != null &&
                                      h.attachmentPath!.trim().isNotEmpty)
                                    FutureBuilder<String?>(
                                      future: _signedUrl(h.attachmentPath!),
                                      builder: (context, snap) {
                                        if (snap.connectionState !=
                                            ConnectionState.done) {
                                          return Padding(
                                            padding: EdgeInsets.only(
                                                top: rs.space(8)),
                                            child: SizedBox(
                                              height: rs.space(100),
                                              child: const Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              ),
                                            ),
                                          );
                                        }
                                        final url = snap.data;
                                        if (url == null) {
                                          return const SizedBox.shrink();
                                        }
                                        return Padding(
                                          padding:
                                              EdgeInsets.only(top: rs.space(8)),
                                          child: GestureDetector(
                                            onTap: () => _showImageDialog(
                                                h.attachmentPath!),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Image.network(
                                                url,
                                                height: rs.space(120),
                                                fit: BoxFit.cover,
                                                errorBuilder: (c, e, st) =>
                                                    const SizedBox.shrink(),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

/// Simple history row model
class _HistItem {
  _HistItem({
    required this.date, // yyyy-MM-dd
    required this.doneBy,
    required this.remarks,
    required this.attachmentPath,
    required this.source, // 'current' | 'history'
  });

  final String date;
  final String doneBy;
  final String remarks;
  final String? attachmentPath;
  final String source;
}

// lib/features/pms/add_pms_task.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/supabase_call.dart';
// ✅ Responsive helper (same one used across the app)
import 'package:emville_pms/responsive/responsive.dart';

class AddPmsTaskPage extends StatefulWidget {
  const AddPmsTaskPage({super.key});

  @override
  State<AddPmsTaskPage> createState() => _AddPmsTaskPageState();
}

class _AddPmsTaskPageState extends State<AddPmsTaskPage> {
  // Emville theme colors
  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  final _sb = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _dfApi = DateFormat('yyyy-MM-dd');

  // Form fields
  int? _jobSeqToUse; // next seq we plan to use (calculated client-side)
  final _taskNameCtrl = TextEditingController();
  final _taskDescCtrl = TextEditingController();
  DateTime _initiationDate = DateTime.now();
  String _interval = 'Monthly'; // Weekly | Monthly | Annually | Custom
  final _customDaysCtrl = TextEditingController();
  String _createdBy = 'User';

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _resolveUser();
    _loadNextJobSeq();
  }

  @override
  void dispose() {
    _taskNameCtrl.dispose();
    _taskDescCtrl.dispose();
    _customDaysCtrl.dispose();
    super.dispose();
  }

  Future<void> _resolveUser() async {
    final user = _sb.auth.currentUser;

    String fullName = 'User';
    if (user != null) {
      try {
        final row = await supabaseCall(() async {
          return await _sb
              .from('users')
              .select('full_name')
              .eq('uid', user.id)
              .maybeSingle();
        });
        final name = row?['full_name'] as String?;
        if (name != null && name.trim().isNotEmpty) {
          fullName = name.trim();
        } else {
          final metaFull = user.userMetadata?['full_name'] as String?;
          final metaName = user.userMetadata?['name'] as String?;
          fullName =
              (metaFull ?? metaName ?? user.email?.split('@').first ?? 'User')
                  .toString()
                  .trim();
        }
      } catch (_) {
        final metaFull = user.userMetadata?['full_name'] as String?;
        final metaName = user.userMetadata?['name'] as String?;
        fullName =
            (metaFull ?? metaName ?? user.email?.split('@').first ?? 'User')
                .toString()
                .trim();
      }
    }
    if (mounted) setState(() => _createdBy = fullName);
  }

  // Simple preview: next = max(job_seq)+1 (client-calculated)
  Future<void> _loadNextJobSeq() async {
    try {
      final rows = await supabaseCall(() async {
        return await _sb
            .from('main_pms_db')
            .select('job_seq')
            .order('job_seq', ascending: false)
            .limit(1);
      });
      int next = 1;
      if (rows.isNotEmpty) {
        final current = (rows.first['job_seq'] as num?)?.toInt() ?? 0;
        next = current + 1;
      }
      if (mounted) setState(() => _jobSeqToUse = next);
    } catch (_) {
      if (mounted) setState(() => _jobSeqToUse = 1);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _initiationDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(), // cannot be in the future
    );
    if (picked != null) setState(() => _initiationDate = picked);
  }

  int? _customIntervalDaysOrNull() {
    if (_interval != 'Custom') return null;
    final t = _customDaysCtrl.text.trim();
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    if (v == null || v <= 0) return null;
    return v;
  }

  DateTime _computeNextDue(DateTime start) {
    switch (_interval) {
      case 'Weekly':
        return start.add(const Duration(days: 7));
      case 'Monthly':
        return DateTime(start.year, start.month + 1, start.day);
      case 'Annually':
        return DateTime(start.year + 1, start.month, start.day);
      case 'Custom':
        final days = _customIntervalDaysOrNull() ?? 1;
        return start.add(Duration(days: days));
      default:
        return DateTime(start.year, start.month + 1, start.day);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final customDays = _customIntervalDaysOrNull();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) {
        final df = DateFormat('dd MMM yyyy');
        final nextDue = _computeNextDue(_initiationDate);
        return AlertDialog(
          title: const Text('Confirm New PMS Task'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_jobSeqToUse != null) Text('Job # ${_jobSeqToUse!}'),
              Text('Task: ${_taskNameCtrl.text.trim()}'),
              Text('Description: ${_taskDescCtrl.text.trim()}'),
              Text('Initiation Date: ${df.format(_initiationDate)}'),
              Text(
                'Frequency: $_interval'
                '${_interval == "Custom" && customDays != null ? " ($customDays days)" : ""}',
              ),
              Text('Next Due: ${df.format(nextDue)}'),
              const SizedBox(height: 8),
              Text('Created by: $_createdBy'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Edit'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add Job'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await _save();
    }
  }

  Future<void> _save() async {
    if (_jobSeqToUse == null) {
      await _loadNextJobSeq();
      if (_jobSeqToUse == null) {
        _snack('Could not determine next Job #');
        return;
      }
    }

    setState(() => _busy = true);
    try {
      final user = _sb.auth.currentUser;
      if (user == null) {
        _snack('Not signed in');
        return;
      }

      final customDays = _customIntervalDaysOrNull();
      final initStr = _dfApi.format(_initiationDate);
      final nextDueStr = _dfApi.format(_computeNextDue(_initiationDate));
      final nowIso = DateTime.now().toIso8601String();

      final payload = {
        'job_seq': _jobSeqToUse, // primary identifier we use
        'task_name': _taskNameCtrl.text.trim(),
        'task_interval':
            _interval.toLowerCase(), // weekly|monthly|annually|custom
        'custom_interval': (_interval == 'Custom') ? customDays : null,
        'initiation_date': initStr,
        'next_due_date': nextDueStr,
        'last_done_date': initStr,
        'done_by': _createdBy,
        'user_uuid': user.id,
        'created_by': _createdBy,
        'creator_uuid': user.id,
        'created_date': nowIso,
        'updated_date': nowIso,
        'postponed': 'no',
        'attachment_path': null,
        'remarks': 'Initial',
        'job_description': _taskDescCtrl.text.trim(),
      };

      await supabaseCall(() async {
        return await _sb.from('main_pms_db').insert(payload);
      });

      if (!mounted) return;
      _snack('PMS task added');

      // Safe pop: return true to the opener (if any). Avoid black screen.
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop(true);
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      _snack('DB error: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to add job');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- UI ----------
  InputDecoration _fieldDeco(String label, {Widget? prefixIcon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: prefixIcon,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: _green, width: 1.8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    final dfUi = DateFormat('dd MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Add PMS Task',
          style: TextStyle(
            fontSize: rs.font(22),
            fontWeight: FontWeight.w800,
            color: _green,
          ),
        ),
        // backgroundColor: _green,
        // foregroundColor: _gold,
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: EdgeInsets.all(rs.space(16)),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    // Job # (read-only preview)
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.confirmation_number,
                          color: _green,
                          size: rs.icon(22),
                        ),
                        title: Text(
                          'Job #',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _green,
                            fontSize: rs.font(14),
                          ),
                        ),
                        subtitle: Text(
                          _jobSeqToUse?.toString() ?? '—',
                          style: TextStyle(
                            fontSize: rs.font(16),
                            color: _green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Refresh',
                          icon: Icon(Icons.refresh,
                              color: _green, size: rs.icon(20)),
                          onPressed: _busy ? null : _loadNextJobSeq,
                        ),
                      ),
                    ),
                    SizedBox(height: rs.space(12)),

                    // Task Name
                    TextFormField(
                      controller: _taskNameCtrl,
                      decoration: _fieldDeco(
                        'Task Name',
                        prefixIcon: Icon(Icons.task_alt,
                            color: _green, size: rs.icon(20)),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    SizedBox(height: rs.space(12)),

                    // Task Description
                    TextFormField(
                      controller: _taskDescCtrl,
                      maxLines: 3,
                      decoration: _fieldDeco(
                        'Task Description',
                        prefixIcon: Icon(
                          Icons.description_outlined,
                          color: _green,
                          size: rs.icon(20),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    SizedBox(height: rs.space(12)),

                    // Initiation Date (<= today)
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.event_available_outlined,
                          color: _green,
                          size: rs.icon(22),
                        ),
                        title: Text(
                          'Initiation Date',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _green,
                            fontSize: rs.font(14),
                          ),
                        ),
                        subtitle: Text(
                          dfUi.format(_initiationDate),
                          style:
                              TextStyle(color: _green, fontSize: rs.font(14)),
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.date_range,
                              color: _green, size: rs.icon(20)),
                          onPressed: _pickDate,
                        ),
                      ),
                    ),
                    SizedBox(height: rs.space(12)),

                    // Frequency + Custom
                    InputDecorator(
                      decoration: _fieldDeco('Task Frequency'),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _interval,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: 'Weekly',
                              child: Text('Weekly'),
                            ),
                            DropdownMenuItem(
                              value: 'Monthly',
                              child: Text('Monthly'),
                            ),
                            DropdownMenuItem(
                              value: 'Annually',
                              child: Text('Annually'),
                            ),
                            DropdownMenuItem(
                              value: 'Custom',
                              child: Text('Custom'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _interval = v;
                              if (_interval != 'Custom') {
                                _customDaysCtrl.clear();
                              }
                            });
                          },
                        ),
                      ),
                    ),
                    if (_interval == 'Custom') ...[
                      SizedBox(height: rs.space(12)),
                      TextFormField(
                        controller: _customDaysCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: false,
                          decimal: false,
                        ),
                        decoration: _fieldDeco(
                          'Custom interval (days)',
                          prefixIcon: Icon(
                            Icons.timelapse_outlined,
                            color: _green,
                            size: rs.icon(20),
                          ),
                        ),
                        validator: (_) {
                          if (_interval != 'Custom') return null;
                          final v = int.tryParse(_customDaysCtrl.text.trim());
                          if (v == null || v <= 0) {
                            return 'Enter whole number of days (> 0)';
                          }
                          return null;
                        },
                      ),
                    ],
                    SizedBox(height: rs.space(12)),

                    // Created by (read-only)
                    InputDecorator(
                      decoration: _fieldDeco('Created by'),
                      child: Text(
                        _createdBy,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _green,
                          fontSize: rs.font(14),
                        ),
                      ),
                    ),
                    SizedBox(height: rs.space(20)),

                    // Submit
                    SizedBox(
                      height: rs.space(48),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: _gold,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: Icon(Icons.add_task, size: rs.icon(20)),
                        label: _busy
                            ? SizedBox(
                                height: rs.icon(18),
                                width: rs.icon(18),
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(_gold),
                                ),
                              )
                            : Text(
                                'Add Job',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: rs.font(14),
                                ),
                              ),
                        onPressed: _busy ? null : _submit,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

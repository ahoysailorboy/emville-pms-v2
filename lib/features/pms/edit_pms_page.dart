import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/supabase_call.dart';
// ✅ Responsive helper (same one used across the app)
import 'package:emville_pms/responsive/responsive.dart';

class EditPmsPage extends StatefulWidget {
  const EditPmsPage({super.key});

  @override
  State<EditPmsPage> createState() => _EditPmsPageState();
}

enum _SearchMode { jobId, taskName }

class _EditPmsPageState extends State<EditPmsPage> {
  // Emville brand
  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  final _sb = Supabase.instance.client;

  _SearchMode _mode = _SearchMode.jobId;
  final _qCtrl = TextEditingController();

  bool _loading = false;
  List<_PmsRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _loadAll(); // show everything initially
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  Future<void> _deleteRow(int jobSeq) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete PMS Task'),
        content: Text(
          'Are you sure you want to delete Job $jobSeq? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final res = await supabaseCall(() async {
        return await _sb
            .from('main_pms_db')
            .delete()
            .eq('job_seq', jobSeq)
            .select('job_seq'); // return deleted rows to verify
      });

      // ignore: unnecessary_type_check
      final deleted = (res is List) ? res.length : 0;
      if (deleted == 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Delete failed: no rows deleted (check RLS/permissions).',
            ),
          ),
        );
        return;
      }

      if (!mounted) return;

      // Optimistic remove from current list
      setState(() => _rows.removeWhere((r) => r.jobSeq == jobSeq));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Job $jobSeq deleted')));

      // STEP 2: refresh list to reflect latest server state (preserve current search if any)
      if (_qCtrl.text.trim().isEmpty) {
        await _loadAll();
      } else {
        await _search();
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Something went wrong')));
    }
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final data = await supabaseCall(() async {
        return await _sb
            .from('main_pms_db')
            .select(
              'job_seq, task_name, job_description, task_interval, custom_interval, last_done_date, next_due_date',
            )
            .order('job_seq', ascending: true);
      });
      final list = (data as List).map<_PmsRow>((m) {
        return _PmsRow(
          jobSeq: (m['job_seq'] as num).toInt(),
          taskName: (m['task_name'] as String?) ?? '',
          jobDescription: (m['job_description'] as String?) ?? '',
          taskInterval: (m['task_interval'] as String?) ?? 'monthly',
          customIntervalDays: (m['custom_interval'] as num?)?.toInt(),
          lastDoneDate: (m['last_done_date'] as String?) ?? '',
          nextDueDate: (m['next_due_date'] as String?) ?? '',
        );
      }).toList();
      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _search() async {
    FocusScope.of(context).unfocus();
    final raw = _qCtrl.text.trim();

    setState(() {
      _loading = true;
      _rows = [];
    });

    try {
      // 1) Start as a filter builder (no order yet)
      var q = _sb.from('main_pms_db').select(
            'job_seq, task_name, job_description, task_interval, custom_interval, last_done_date, next_due_date',
          ) as PostgrestFilterBuilder;

      // 2) Apply filters (if any)
      if (raw.isNotEmpty) {
        if (_mode == _SearchMode.jobId) {
          // Accept "7", "0007", or "E0007"
          final digits = RegExp(
            r'\d+',
          ).allMatches(raw).map((m) => m.group(0)!).join();
          final id = int.tryParse(digits);
          if (id != null) {
            q = q.eq('job_seq', id);
          } else {
            // Force no results if nothing numeric
            q = q.eq('job_seq', -1);
          }
        } else {
          // Case-insensitive name search; escape wildcard chars
          final safe = raw.replaceAll('%', r'\%').replaceAll('_', r'\_');
          q = q.ilike('task_name', '%$safe%');
        }
      }

      // 3) Order AFTER filters, then execute
      final data = await q.order('job_seq', ascending: true);

      final list = (data as List).map<_PmsRow>((m) {
        return _PmsRow(
          jobSeq: (m['job_seq'] as num).toInt(),
          taskName: (m['task_name'] as String?) ?? '',
          jobDescription: (m['job_description'] as String?) ?? '',
          taskInterval: (m['task_interval'] as String?) ?? 'monthly',
          customIntervalDays: (m['custom_interval'] as num?)?.toInt(),
          lastDoneDate: (m['last_done_date'] as String?) ?? '',
          nextDueDate: (m['next_due_date'] as String?) ?? '',
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // Recompute next due based on last_done_date and new interval/custom
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

  Future<void> _saveRowEdits(_PmsRow before, _EditableValues values) async {
    // Confirm
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Update'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Job: ${before.jobSeq}'),
            Text('Task name: ${values.taskName}'),
            Text('Description: ${values.jobDescription}'),
            Text(
              'Interval: ${values.taskInterval.toLowerCase() == 'custom' ? 'Custom (${values.customIntervalDays ?? 0} days)' : values.taskInterval}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Edit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      // Recompute next_due_date from LAST DONE using new interval/custom
      final df = DateFormat('yyyy-MM-dd');
      final lastDone = before.lastDoneDate.isNotEmpty
          ? DateTime.parse(before.lastDoneDate)
          : DateTime.now(); // fallback (shouldn't happen)
      final nextDue = _computeNextDue(
        DateTime(lastDone.year, lastDone.month, lastDone.day),
        values.taskInterval,
        values.taskInterval.toLowerCase() == 'custom'
            ? values.customIntervalDays
            : null,
      );
      final payload = <String, dynamic>{
        'task_name': values.taskName.trim(),
        'job_description': values.jobDescription.trim(),
        'task_interval': values.taskInterval.toLowerCase() == 'yearly'
            ? 'annually'
            : values.taskInterval.toLowerCase(),
        'custom_interval': values.taskInterval.toLowerCase() == 'custom'
            ? (values.customIntervalDays ?? 1)
            : null,
        'next_due_date': df.format(nextDue),
        'updated_date': DateTime.now().toIso8601String(),
      };

      await supabaseCall(() async {
        return await _sb
            .from('main_pms_db')
            .update(payload)
            .eq('job_seq', before.jobSeq);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Task updated')));

      // Refresh the list (keeping current search, if any)
      if (_qCtrl.text.trim().isEmpty) {
        await _loadAll();
      } else {
        await _search();
      }
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    const emGreen = _green;
    const emGold = _gold;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Edit PMS',
          style: TextStyle(
            fontSize: rs.font(22),
            fontWeight: FontWeight.w800,
            color: _green,
          ),
        ),
        //backgroundColor: emGreen,
        //foregroundColor: emGreen,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              // Search section (fixed)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  rs.space(16),
                  rs.space(12),
                  rs.space(16),
                  rs.space(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Search',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: emGreen,
                        fontSize: rs.font(14),
                      ),
                    ),
                    SizedBox(height: rs.space(8)),
                    Wrap(
                      spacing: rs.space(12),
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ChoiceChip(
                          selectedColor: emGreen.withValues(alpha: 0.1),
                          label: Text(
                            'By Job ID',
                            style: TextStyle(fontSize: rs.font(13)),
                          ),
                          selected: _mode == _SearchMode.jobId,
                          onSelected: (_) =>
                              setState(() => _mode = _SearchMode.jobId),
                        ),
                        ChoiceChip(
                          selectedColor: emGreen.withValues(alpha: 0.1),
                          label: Text(
                            'By Task Name',
                            style: TextStyle(fontSize: rs.font(13)),
                          ),
                          selected: _mode == _SearchMode.taskName,
                          onSelected: (_) =>
                              setState(() => _mode = _SearchMode.taskName),
                        ),
                      ],
                    ),
                    SizedBox(height: rs.space(8)),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _qCtrl,
                            decoration: InputDecoration(
                              hintText: _mode == _SearchMode.jobId
                                  ? 'Enter Job ID'
                                  : 'Enter Task Name',
                              prefixIcon: Icon(Icons.search, size: rs.icon(20)),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              focusedBorder: const OutlineInputBorder(
                                borderSide:
                                    BorderSide(color: emGreen, width: 1.8),
                              ),
                            ),
                            onSubmitted: (_) => _search(),
                          ),
                        ),
                        SizedBox(width: rs.space(8)),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: emGreen,
                            foregroundColor: emGold,
                            padding: EdgeInsets.symmetric(
                              horizontal: rs.space(12),
                              vertical: rs.space(12),
                            ),
                          ),
                          onPressed: _search,
                          icon: Icon(Icons.filter_alt_outlined,
                              size: rs.icon(20)),
                          label: Text('Search',
                              style: TextStyle(fontSize: rs.font(14))),
                        ),
                        SizedBox(width: rs.space(8)),
                        OutlinedButton(
                          onPressed: () {
                            _qCtrl.clear();
                            _loadAll();
                          },
                          child: Text('Clear',
                              style: TextStyle(fontSize: rs.font(14))),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Results (scrollable with scrollbar)
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _rows.isEmpty
                        ? const Center(child: Text('No results'))
                        : Scrollbar(
                            child: ListView.separated(
                              padding: EdgeInsets.fromLTRB(
                                rs.space(12),
                                rs.space(8),
                                rs.space(12),
                                rs.space(16),
                              ),
                              itemCount: _rows.length,
                              separatorBuilder: (_, __) =>
                                  SizedBox(height: rs.space(8)),
                              itemBuilder: (context, i) {
                                final r = _rows[i];
                                return _EditableTaskTile(
                                  key: ValueKey(r.jobSeq),
                                  row: r,
                                  onSave: _saveRowEdits,
                                  onDelete: (jobSeq) async {
                                    // quick UI removal
                                    setState(
                                      () => _rows.removeWhere(
                                          (e) => e.jobSeq == jobSeq),
                                    );

                                    // then re-run the current query to stay accurate
                                    if (_qCtrl.text.trim().isEmpty) {
                                      await _loadAll();
                                    } else {
                                      await _search();
                                    }
                                  },
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditableTaskTile extends StatefulWidget {
  const _EditableTaskTile({
    super.key,
    required this.row,
    required this.onSave,
    required this.onDelete,
  });

  final _PmsRow row;
  final Future<void> Function(_PmsRow before, _EditableValues values) onSave;
  final Future<void> Function(int jobSeq) onDelete;

  @override
  State<_EditableTaskTile> createState() => _EditableTaskTileState();
}

class _EditableTaskTileState extends State<_EditableTaskTile> {
  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  String _interval = 'Monthly'; // UI value
  late TextEditingController _customDaysCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.row.taskName);
    _descCtrl = TextEditingController(text: widget.row.jobDescription);
    _interval = _toUiInterval(widget.row.taskInterval);
    _customDaysCtrl = TextEditingController(
      text: widget.row.customIntervalDays?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _customDaysCtrl.dispose();
    super.dispose();
  }

  String _toUiInterval(String db) {
    switch (db.toLowerCase()) {
      case 'weekly':
        return 'Weekly';
      case 'monthly':
        return 'Monthly';
      case 'annually':
      case 'yearly':
        return 'Annually';
      case 'custom':
        return 'Custom';
      default:
        return 'Monthly';
    }
  }

  String _toDbInterval(String ui) {
    switch (ui) {
      case 'Weekly':
        return 'weekly';
      case 'Monthly':
        return 'monthly';
      case 'Annually':
        return 'annually';
      case 'Custom':
        return 'custom';
      default:
        return 'monthly';
    }
  }

  int? _customDaysOrNull() {
    if (_interval != 'Custom') return null;
    final t = _customDaysCtrl.text.trim();
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    if (v == null || v <= 0) return null;
    return v;
  }

  InputDecoration _fieldDeco(String label, {Widget? prefixIcon}) =>
      InputDecoration(
        labelText: label,
        prefixIcon: prefixIcon,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: _green, width: 1.8),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    final dfUi = DateFormat('dd MMM yyyy');

    final lastDoneUi = widget.row.lastDoneDate.isEmpty
        ? '—'
        : dfUi.format(DateTime.parse(widget.row.lastDoneDate));
    final nextDueUi = widget.row.nextDueDate.isEmpty
        ? '—'
        : dfUi.format(DateTime.parse(widget.row.nextDueDate));

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: _gold.withValues(alpha: 0.15),
          highlightColor: _gold.withValues(alpha: 0.08),
        ),
        child: ExpansionTile(
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
            child: Icon(Icons.edit_calendar_outlined,
                color: _gold, size: rs.icon(22)),
          ),
          title: Text(
            'Job ${widget.row.jobSeq}',
            style: TextStyle(
              color: _green,
              fontWeight: FontWeight.bold,
              fontSize: rs.font(16),
            ),
          ),
          subtitle: Text(
            widget.row.taskName,
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
                  // Read-only quick facts
                  _kv('Last Done', lastDoneUi, rs),
                  _kv('Next Due', nextDueUi, rs),
                  SizedBox(height: rs.space(12)),
                  const Divider(),
                  SizedBox(height: rs.space(12)),

                  // Editable fields
                  TextField(
                    controller: _nameCtrl,
                    decoration: _fieldDeco(
                      'Task Name',
                      prefixIcon: Icon(Icons.task_alt,
                          color: _green, size: rs.icon(20)),
                    ),
                  ),
                  SizedBox(height: rs.space(12)),
                  TextField(
                    controller: _descCtrl,
                    maxLines: 3,
                    decoration: _fieldDeco(
                      'Task Description',
                      prefixIcon: Icon(
                        Icons.description_outlined,
                        color: _green,
                        size: rs.icon(20),
                      ),
                    ),
                  ),
                  SizedBox(height: rs.space(12)),

                  // Interval
                  InputDecorator(
                    decoration: _fieldDeco('Task Interval'),
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
                          setState(() {
                            _interval = v!;
                            if (_interval != 'Custom') _customDaysCtrl.clear();
                          });
                        },
                      ),
                    ),
                  ),
                  if (_interval == 'Custom') ...[
                    SizedBox(height: rs.space(12)),
                    TextField(
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
                    ),
                  ],
                  SizedBox(height: rs.space(16)),

                  // Row with Save + Delete
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: _gold,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: rs.space(12),
                            vertical: rs.space(12),
                          ),
                        ),
                        onPressed: () {
                          final customDays = _customDaysOrNull();
                          if (_interval == 'Custom' &&
                              (customDays == null || customDays <= 0)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Enter a valid custom interval (days > 0)',
                                ),
                              ),
                            );
                            return;
                          }

                          final values = _EditableValues(
                            taskName: _nameCtrl.text,
                            jobDescription: _descCtrl.text,
                            taskInterval: _toDbInterval(_interval),
                            customIntervalDays:
                                _interval == 'Custom' ? customDays : null,
                          );
                          widget.onSave(widget.row, values);
                        },
                        icon: Icon(Icons.save_outlined, size: rs.icon(20)),
                        label: Text(
                          'Save',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: rs.font(14),
                          ),
                        ),
                      ),
                      SizedBox(width: rs.space(12)),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade300),
                          padding: EdgeInsets.symmetric(
                            horizontal: rs.space(12),
                            vertical: rs.space(12),
                          ),
                        ),
                        onPressed: () async {
                          final state = context
                              .findAncestorStateOfType<_EditPmsPageState>();
                          if (state != null) {
                            await state._deleteRow(widget.row.jobSeq);
                          }
                        },
                        icon: Icon(Icons.delete_outline, size: rs.icon(20)),
                        label: Text('Delete',
                            style: TextStyle(fontSize: rs.font(14))),
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
                fontSize: rs.font(14),
              ),
            ),
            TextSpan(
              text: v,
              style: TextStyle(
                  color: _green.withValues(alpha: 0.9), fontSize: rs.font(14)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PmsRow {
  _PmsRow({
    required this.jobSeq,
    required this.taskName,
    required this.jobDescription,
    required this.taskInterval, // weekly | monthly | annually | custom
    required this.customIntervalDays,
    required this.lastDoneDate, // yyyy-MM-dd
    required this.nextDueDate, // yyyy-MM-dd
  });

  final int jobSeq;
  final String taskName;
  final String jobDescription;
  final String taskInterval;
  final int? customIntervalDays;
  final String lastDoneDate;
  final String nextDueDate;
}

class _EditableValues {
  _EditableValues({
    required this.taskName,
    required this.jobDescription,
    required this.taskInterval, // db value
    required this.customIntervalDays,
  });

  final String taskName;
  final String jobDescription;
  final String taskInterval; // weekly | monthly | annually | custom
  final int? customIntervalDays;
}

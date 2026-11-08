// lib/features/pms/pms_advanced_search.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'search_results_page.dart';

// ✅ Reuse your shared responsive helper
import 'package:emville_pms/responsive/responsive.dart';

class PmsAdvancedSearchPage extends StatefulWidget {
  const PmsAdvancedSearchPage({super.key});

  @override
  State<PmsAdvancedSearchPage> createState() => _PmsAdvancedSearchPageState();
}

class _PmsAdvancedSearchPageState extends State<PmsAdvancedSearchPage> {
  // Emville brand
  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  final _sb = Supabase.instance.client;

  // Form state
  final _formKey = GlobalKey<FormState>();
  final _jobIdCtrl = TextEditingController();
  final _taskNameCtrl = TextEditingController();
  final _intervalCtrl = TextEditingController();
  final _doneByCtrl = TextEditingController();
  final _descCtrl = TextEditingController(); // job_description
  final _remarksCtrl = TextEditingController();

  String? _interval; // weekly | monthly | annually | custom | null
  DateTime? _from; // last_done_date >= from
  DateTime? _to; // last_done_date <= to

  final _dfSql = DateFormat('yyyy-MM-dd');
  final _dfUi = DateFormat('dd MMM yyyy');

  bool _busy = false;

  @override
  void dispose() {
    _jobIdCtrl.dispose();
    _taskNameCtrl.dispose();
    _doneByCtrl.dispose();
    _descCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  // ---- Date pickers with validation ----
  static final DateTime _minAllowed = DateTime(2022, 1, 1);
  static final DateTime _maxAllowed = DateTime.now();

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from ?? _maxAllowed,
      firstDate: _minAllowed,
      lastDate: _maxAllowed,
      helpText: 'From date (Last Done Date)',
    );
    if (picked != null) {
      setState(() => _from = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to ?? _maxAllowed,
      firstDate: _minAllowed,
      lastDate: _maxAllowed,
      helpText: 'To date (Last Done Date)',
    );
    if (picked != null) {
      setState(() => _to = DateTime(picked.year, picked.month, picked.day));
    }
  }

  // ---- Build & run query ----
  Future<void> _runSearch() async {
    // Simple date-range sanity checks
    if (_from != null && _to != null && _from!.isAfter(_to!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('"From" cannot be after "To"')),
      );
      return;
    }

    // If NOTHING is filled, warn
    final nothingFilled = [
      _from,
      _to,
      _interval,
      _jobIdCtrl.text.trim(),
      _taskNameCtrl.text.trim(),
      _doneByCtrl.text.trim(),
      _descCtrl.text.trim(),
      _remarksCtrl.text.trim(),
    ].every((v) => (v == null) || (v is String && v.isEmpty));

    if (nothingFilled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one filter')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      // 1) Start WITHOUT .order(...)
      var query = _sb.from('main_pms_db').select(
            'job_seq, task_name, job_description, task_interval, custom_interval, '
            'last_done_date, next_due_date, done_by, remarks, attachment_path',
          );

      // 2) Apply filters (these are on PostgrestFilterBuilder)
      if (_from != null) {
        query = query.gte('last_done_date', _dfSql.format(_from!));
      }
      if (_to != null) {
        query = query.lte('last_done_date', _dfSql.format(_to!));
      }

      final jobIdText = _jobIdCtrl.text.trim();
      if (jobIdText.isNotEmpty) {
        final asInt = int.tryParse(jobIdText);
        if (asInt != null) {
          query = query.eq('job_seq', asInt);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Job ID must be a number')),
          );
        }
      }

      final taskName = _taskNameCtrl.text.trim();
      if (taskName.isNotEmpty) {
        query = query.ilike('task_name', '%$taskName%');
      }

      if (_interval != null && _interval!.trim().isNotEmpty) {
        final normalized =
            _interval!.toLowerCase() == 'yearly' ? 'annually' : _interval!;
        query = query.eq('task_interval', normalized.toLowerCase());
      }

      final doneBy = _doneByCtrl.text.trim();
      if (doneBy.isNotEmpty) {
        query = query.ilike('done_by', '%$doneBy%');
      }

      final desc = _descCtrl.text.trim();
      if (desc.isNotEmpty) {
        query = query.ilike('job_description', '%$desc%');
      }

      final rem = _remarksCtrl.text.trim();
      if (rem.isNotEmpty) {
        query = query.ilike('remarks', '%$rem%');
      }

      // 3) Only now apply order, then await
      final rows = await query.order('last_done_date', ascending: false);

      // Push to results list page (defined below)
      // ignore: use_build_context_synchronously
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _SearchResultsListPage(
            rows: List<Map<String, dynamic>>.from(rows),
          ),
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Search failed: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Something went wrong')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- Small UI helpers ----
  InputDecoration _deco(String label, {Widget? icon}) => InputDecoration(
        labelText: label,
        prefixIcon: icon,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: _green, width: 1.8),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Advanced Search',
          style: TextStyle(fontSize: rs.font(20), fontWeight: FontWeight.w700),
        ),
        //backgroundColor: _green,
        foregroundColor: _green,
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.all(rs.space(16)),
                children: [
                  // Last Done Date range
                  Text(
                    'Last Done Date',
                    style: TextStyle(
                      color: _green.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w700,
                      fontSize: rs.font(14),
                    ),
                  ),
                  SizedBox(height: rs.space(8)),
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('From',
                              style: TextStyle(fontSize: rs.font(13))),
                          subtitle: Text(
                            _from == null ? '—' : _dfUi.format(_from!),
                            style: TextStyle(fontSize: rs.font(13)),
                          ),
                          trailing: IconButton(
                            icon: Icon(Icons.date_range,
                                color: _green, size: rs.icon(22)),
                            onPressed: _pickFrom,
                          ),
                        ),
                      ),
                      SizedBox(width: rs.space(8)),
                      Expanded(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('To',
                              style: TextStyle(fontSize: rs.font(13))),
                          subtitle: Text(
                            _to == null ? '—' : _dfUi.format(_to!),
                            style: TextStyle(fontSize: rs.font(13)),
                          ),
                          trailing: IconButton(
                            icon: Icon(Icons.date_range,
                                color: _green, size: rs.icon(22)),
                            onPressed: _pickTo,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: rs.space(12)),

                  // Job ID
                  TextFormField(
                    controller: _jobIdCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: false,
                      decimal: false,
                    ),
                    decoration: _deco(
                      'Job ID',
                      icon: Icon(Icons.confirmation_number,
                          color: _green, size: rs.icon(20)),
                    ),
                  ),
                  SizedBox(height: rs.space(12)),

                  // Task Name
                  TextFormField(
                    controller: _taskNameCtrl,
                    decoration: _deco(
                      'Task Name',
                      icon: Icon(Icons.task_alt,
                          color: _green, size: rs.icon(20)),
                    ),
                  ),
                  SizedBox(height: rs.space(12)),

                  // Interval dropdown
                  InputDecorator(
                    decoration: _deco('Interval'),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _interval,
                        isExpanded: true,
                        hint: Text('Any',
                            style: TextStyle(fontSize: rs.font(13))),
                        items: const [
                          DropdownMenuItem(
                              value: 'weekly', child: Text('Weekly')),
                          DropdownMenuItem(
                              value: 'monthly', child: Text('Monthly')),
                          DropdownMenuItem(
                              value: 'annually', child: Text('Annually')),
                          DropdownMenuItem(
                              value: 'custom', child: Text('Custom')),
                        ],
                        onChanged: (v) => setState(() => _interval = v),
                      ),
                    ),
                  ),
                  SizedBox(height: rs.space(12)),

                  // Done By
                  TextFormField(
                    controller: _doneByCtrl,
                    decoration: _deco(
                      'Done By',
                      icon: Icon(Icons.person_outline,
                          color: _green, size: rs.icon(20)),
                    ),
                  ),
                  SizedBox(height: rs.space(12)),

                  // Description
                  TextFormField(
                    controller: _descCtrl,
                    maxLines: 2,
                    decoration: _deco(
                      'Description',
                      icon: Icon(Icons.description_outlined,
                          color: _green, size: rs.icon(20)),
                    ),
                  ),
                  SizedBox(height: rs.space(12)),

                  // Remarks
                  TextFormField(
                    controller: _remarksCtrl,
                    maxLines: 2,
                    decoration: _deco(
                      'Remarks',
                      icon: Icon(Icons.notes_outlined,
                          color: _green, size: rs.icon(20)),
                    ),
                  ),
                  SizedBox(height: rs.space(20)),

                  // Search button
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
                      onPressed: _busy ? null : _runSearch,
                      icon: _busy
                          ? SizedBox(
                              height: rs.space(18),
                              width: rs.space(18),
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(_gold),
                              ),
                            )
                          : Icon(Icons.search, size: rs.icon(20)),
                      label: Text(
                        'Search',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: rs.font(14)),
                      ),
                    ),
                  ),

                  SizedBox(height: rs.space(12)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.clear, color: Colors.red),
                      label: Text(
                        "Clear Filters",
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: rs.font(13),
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          // Clear text fields
                          _jobIdCtrl.clear();
                          _taskNameCtrl.clear();
                          _intervalCtrl.clear();
                          _doneByCtrl.clear();
                          _descCtrl.clear();
                          _remarksCtrl.clear();

                          // Reset dates
                          _from = DateTime(2022, 1, 1);
                          _to = DateTime.now();

                          // Reset dropdown
                          _interval = null;
                        });
                      },
                    ),
                  ),

                  SizedBox(height: rs.space(8)),
                  Text(
                    'Tip: leave fields blank to ignore them.',
                    style:
                        TextStyle(fontSize: rs.font(12), color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------------------------
/// Results list (temporary)
/// ---------------------------
/// This list page is defined here so the app compiles immediately.
/// In the NEXT step, we’ll create a dedicated `search_results_page.dart`
/// that shows a full detail view for a tapped job.
class _SearchResultsListPage extends StatelessWidget {
  const _SearchResultsListPage({required this.rows});
  final List<Map<String, dynamic>> rows;

  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    final dfUi = DateFormat('dd MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Search Results',
          style: TextStyle(fontSize: rs.font(20), fontWeight: FontWeight.w700),
        ),
        backgroundColor: _green,
        foregroundColor: _gold,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView.separated(
            padding: EdgeInsets.all(rs.space(12)),
            itemCount: rows.length,
            separatorBuilder: (_, __) => SizedBox(height: rs.space(8)),
            itemBuilder: (context, i) {
              final r = rows[i];
              final jobSeq = (r['job_seq'] as num?)?.toInt() ?? 0;
              final task = (r['task_name'] as String?) ?? '';
              final lastDone = (r['last_done_date'] as String?);
              final due = (r['next_due_date'] as String?);
              final interval = (r['task_interval'] as String?) ?? '';
              final custom = (r['custom_interval'] as num?)?.toInt();

              String intervalLabel = interval.isEmpty ? '—' : interval;
              if (interval == 'custom' && custom != null && custom > 0) {
                intervalLabel = 'Every $custom days';
              }

              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                child: ListTile(
                  leading: Container(
                    height: rs.space(44),
                    width: rs.space(44),
                    decoration: BoxDecoration(
                      color: _green,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.search, color: _gold, size: rs.icon(22)),
                  ),
                  title: Text(
                    task,
                    style: TextStyle(
                      color: _green,
                      fontWeight: FontWeight.bold,
                      fontSize: rs.font(15),
                    ),
                  ),
                  subtitle: Text(
                    'Job $jobSeq • Interval: $intervalLabel\n'
                    'Last: ${lastDone == null || lastDone.isEmpty ? '—' : dfUi.format(DateTime.parse(lastDone))}  '
                    'Next: ${due == null || due.isEmpty ? '—' : dfUi.format(DateTime.parse(due))}',
                    style: TextStyle(
                        color: _green.withValues(alpha: 0.8),
                        fontSize: rs.font(13)),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SearchResultDetailPage(job: r),
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Detail page coming next')),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

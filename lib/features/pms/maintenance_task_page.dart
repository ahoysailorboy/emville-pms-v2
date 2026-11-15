import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/ui/emville_widgets.dart';
import 'search_results_page.dart';

/// Resolve a single recurring task, including all fields used by its workflow.
class MaintenanceTaskPage extends StatefulWidget {
  const MaintenanceTaskPage({super.key, this.id, this.jobSeq});
  final String? id;
  final int? jobSeq;
  @override
  State<MaintenanceTaskPage> createState() => _MaintenanceTaskPageState();
}

class _MaintenanceTaskPageState extends State<MaintenanceTaskPage> {
  late Future<Map<String, dynamic>> _job;
  @override
  void initState() {
    super.initState();
    _job = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final query = Supabase.instance.client.from('main_pms_db').select();
    return widget.jobSeq != null
        ? await query.eq('job_seq', widget.jobSeq!).single()
        : await query.eq('id', widget.id!).single();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
      future: _job,
      builder: (context, s) {
        if (s.hasData) return SearchResultDetailPage(job: s.data!);
        return EmvillePage(
            section: 3,
            child: s.hasError
                ? EmvilleError(
                    message: 'Could not load this task.',
                    onRetry: () => setState(() {
                          _job = _load();
                        }))
                : const Center(child: CircularProgressIndicator()));
      });
}

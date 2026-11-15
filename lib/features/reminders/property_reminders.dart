import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/ui/emville_widgets.dart';
import 'reminder_pages.dart';

/// RLS limits the work list to the creator, assignee and owner/admins.
class PropertyReminders extends StatefulWidget {
  const PropertyReminders({super.key});
  @override
  State<PropertyReminders> createState() => _PropertyRemindersState();
}

class _PropertyRemindersState extends State<PropertyReminders> {
  late Future<List<Map<String, dynamic>>> _rows;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _rows = Supabase.instance.client
        .from('work_reminders')
        .select()
        .neq('status', 'completed')
        .order('due_at');
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        EmvilleSectionTitle('Assigned tasks',
            trailing: IconButton(
                tooltip: 'Refresh assigned tasks',
                onPressed: () => setState(_reload),
                icon: const Icon(Icons.refresh, size: 18))),
        FutureBuilder(
            future: _rows,
            builder: (context, s) {
              if (s.hasError) {
                return EmvilleError(
                    message: 'Could not load assigned tasks.',
                    onRetry: () => setState(_reload));
              }
              if (!s.hasData) return const LinearProgressIndicator();
              if (s.data!.isEmpty) {
                return const Text('No outstanding assigned tasks.');
              }
              return Column(children: [
                for (final r in s.data!)
                  EmvilleTile(
                      icon: Icons.task_alt,
                      title: r['title'],
                      subtitle: reminderDate(r['due_at']),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ReminderDetailPage(id: r['id'])));
                        if (mounted) setState(_reload);
                      })
              ]);
            }),
      ]);
}

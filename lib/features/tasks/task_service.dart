import 'package:supabase_flutter/supabase_flutter.dart';

final supa = Supabase.instance.client;

class TaskService {
  Future<String> createTask({
    required String title,
    required String frequency, // 'daily'|'weekly'|'monthly'|'after_x_days'
    DateTime? initiationDate,
    int? xDays,
  }) async {
    final user = supa.auth.currentUser!;
    final res = await supa
        .from('tasks')
        .insert({
          'title': title,
          'frequency': frequency,
          'initiation_date': (initiationDate ?? DateTime.now())
              .toIso8601String(),
          'x_days': xDays,
          'created_by': user.id,
        })
        .select('id')
        .single();
    return res['id'] as String;
  }

  Future<List<Map<String, dynamic>>> listInstances({int daysAhead = 7}) async {
    final today = DateTime.now();
    final max = today.add(Duration(days: daysAhead));

    final todayStr = today.toIso8601String().split('T').first;
    final maxStr = max.toIso8601String().split('T').first;

    final rows = await supa
        .from('task_instances')
        .select('id, task_id, scheduled_date, status, done_date, remarks')
        .gte('scheduled_date', todayStr) // filters first
        .lte('scheduled_date', maxStr) // filters first
        .order('scheduled_date'); // ordering last

    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> markDone(String instanceId) async {
    await supa
        .from('task_instances')
        .update({
          'status': 'done',
          'done_date': DateTime.now().toIso8601String(),
        })
        .eq('id', instanceId);
  }
}

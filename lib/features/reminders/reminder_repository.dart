import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReminderRepository {
  ReminderRepository(this.client);
  final SupabaseClient client;

  Future<List<Map<String, dynamic>>> mine() async {
    final result = <Map<String, dynamic>>[];
    for (var offset = 0;; offset += 500) {
      final page = await client
          .from('work_reminders')
          .select()
          .eq('assigned_to', client.auth.currentUser!.id)
          .order('due_at')
          .order('id')
          .range(offset, offset + 499);
      result.addAll(List<Map<String, dynamic>>.from(page));
      if (page.length < 500) return result;
    }
  }

  Future<List<Map<String, dynamic>>> people() async =>
      List<Map<String, dynamic>>.from(await client.rpc('reminder_people'));

  Future<Map<String, dynamic>> get(String id) async =>
      await client.from('work_reminders').select().eq('id', id).single();

  Future<List<Map<String, dynamic>>> activity(String id) async =>
      List<Map<String, dynamic>>.from(await client
          .from('work_reminder_activity')
          .select()
          .eq('reminder_id', id)
          .order('created_at'));

  Future<String> create(
      {required String title,
      required String description,
      required String assignee,
      required DateTime due}) async {
    final id = await client.rpc('create_work_reminder', params: {
      'p_title': title.trim(),
      'p_description': description.trim(),
      'p_assigned_to': assignee,
      'p_due_at': due.toUtc().toIso8601String(),
    });
    unawaited(notify());
    return id as String;
  }

  Future<void> update(Map<String, dynamic> row, String action, String remarks,
      {DateTime? due}) async {
    await client.rpc('update_work_reminder', params: {
      'p_id': row['id'],
      'p_revision': row['revision'],
      'p_action': action,
      'p_remarks': remarks.trim(),
      'p_due_at': due?.toUtc().toIso8601String(),
    });
    unawaited(notify());
  }

  Future<void> notify() async {
    try {
      await client.functions.invoke('task_notifications');
    } catch (_) {/* Saved queue entries remain available for server retries. */}
  }
}

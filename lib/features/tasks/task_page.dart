import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'task_service.dart';

final supa = Supabase.instance.client;

class TaskPage extends StatefulWidget {
  const TaskPage({super.key});
  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  final svc = TaskService();
  List<Map<String, dynamic>> instances = [];
  bool loading = false;
  String? error;

  Future<void> _refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      instances = await svc.listInstances(daysAhead: 30);
    } catch (e) {
      error = e.toString();
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> _createSampleTask() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await svc.createTask(
        title: 'Sample Weekly Task',
        frequency: 'weekly',
        initiationDate: DateTime.now(),
      );
      await _refresh();
    } catch (e) {
      error = e.toString();
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emville PMS')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                FilledButton(
                  onPressed: _createSampleTask,
                  child: const Text('Create Sample Task'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _refresh,
                  child: const Text('Refresh'),
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: () async {
                    await supa.auth.signOut();
                  },
                  child: const Text('Sign out'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: instances.length,
                itemBuilder: (context, i) {
                  final it = instances[i];
                  final id = it['id'] as String;
                  final sched = (it['scheduled_date'] ?? '').toString();
                  final status = (it['status'] ?? '').toString();
                  final done = (it['done_date'] ?? '').toString();
                  return Card(
                    child: ListTile(
                      title: Text('Instance: ${id.substring(0, 8)}… • $status'),
                      subtitle: Text('scheduled: $sched   done: $done'),
                      trailing: status != 'done'
                          ? FilledButton(
                              onPressed: () async {
                                await svc.markDone(id);
                                await _refresh();
                              },
                              child: const Text('Mark done'),
                            )
                          : const Icon(Icons.check_circle),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

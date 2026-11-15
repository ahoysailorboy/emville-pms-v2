import 'package:emville_pms/features/pms/pending_tasks_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/features/home/presentation/first_page.dart';
import 'package:emville_pms/features/reminders/reminder_pages.dart';
import 'package:emville_pms/features/reminders/home_reminders.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'support/mock_supabase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = EmvilleTestBackend();
  setUpAll(backend.initialize);
  setUp(() async {
    backend.reminders.clear();
    backend.reminderWrites.clear();
    backend.reminderActivity.clear();
    await backend.signIn();
  });
  tearDownAll(() => Supabase.instance.dispose());
  testWidgets(
      'Schedule task creates assigned reminder with date and details, not a PMS master item',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        MaterialApp(theme: Emville.theme, home: const ScheduleReminderPage()));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField).at(0), 'Check pool lights');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'Replace the faulty bulb');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caretaker').last);
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Schedule task'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schedule task'));
    await tester.pumpAndSettle();
    expect(find.text('Check pool lights'), findsOneWidget);
    expect(backend.reminderWrites, hasLength(1));
    expect(find.text('Assigned to Caretaker'), findsOneWidget);
    expect(backend.reminderWrites.single['p_assigned_to'], 'teammate');
    expect(backend.reminderWrites.single['p_due_at'], endsWith('Z'));
    expect(find.text('Conversation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Task remarks require text; completion confirms and records current revision',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    backend.reminders.add({
      'id': 'task-1',
      'title': 'Inspect pump',
      'description': 'Check pressure',
      'assigned_to': backend.user['id'],
      'created_by': backend.user['id'],
      'due_at': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
      'status': 'open',
      'revision': 4
    });
    await tester.pumpWidget(MaterialApp(
        theme: Emville.theme, home: const ReminderDetailPage(id: 'task-1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add remark'));
    await tester.tap(find.text('Add remark'));
    await tester.pumpAndSettle();
    expect(backend.reminderWrites, isEmpty);
    await tester.enterText(find.byType(TextField), 'Pressure normal');
    await tester.ensureVisible(find.text('Complete task'));
    await tester.tap(find.text('Complete task'));
    await tester.pumpAndSettle();
    expect(find.text('Complete this task?'), findsOneWidget);
    await tester.tap(find.text('Complete').last);
    await tester.pumpAndSettle();
    expect(backend.reminderWrites.single['p_revision'], 4);
    expect(backend.reminderWrites.single['p_action'], 'completed');
    expect(find.text('Pressure normal'), findsOneWidget);
    expect(find.text('Complete task'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Property row opens just the selected maintenance task',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: Emville.theme,
        home: const Scaffold(body: FirstPage(role: 'owner'))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Air conditioner service'));
    await tester.tap(find.text('Air conditioner service'));
    await tester.pumpAndSettle();
    expect(find.text('Task details'), findsOneWidget);
    expect(find.text('Pool filter service'), findsNothing);
    expect(find.text('Pending Tasks'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Home shows assigned reminders and opens their details',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    backend.reminders.add({
      'id': 'task-2',
      'title': 'Check kitchen',
      'description': 'Inspect sink',
      'assigned_to': backend.user['id'],
      'created_by': backend.user['id'],
      'due_at': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
      'status': 'open',
      'revision': 0
    });
    await tester.pumpWidget(MaterialApp(
        theme: Emville.theme,
        home: const Scaffold(
            body: SingleChildScrollView(child: HomeReminders()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check kitchen'));
    await tester.pumpAndSettle();
    expect(find.text('Inspect sink'), findsOneWidget);
    expect(find.text('Conversation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Pending list uses the shared header and opens the selected task',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        MaterialApp(theme: Emville.theme, home: const PendingTasksPage()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Pending tasks'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
    await tester.ensureVisible(find.text('Pool filter service'));
    await tester.tap(find.text('Pool filter service'));
    await tester.pumpAndSettle();
    expect(find.text('Task details'), findsOneWidget);
    expect(find.text('Air conditioner service'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Pending tasks'), findsOneWidget);
  });
}

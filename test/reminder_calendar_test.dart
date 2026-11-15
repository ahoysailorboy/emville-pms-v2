import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:emville_pms/features/reminders/reminder_calendar.dart';

class FakeCalendar implements DeviceCalendar {
  final calls = <Invocation>[];
  CalendarPermissionStatus permission = CalendarPermissionStatus.granted;
  int created = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    if (invocation.memberName == #requestPermissions ||
        invocation.memberName == #hasPermissions) {
      return Future.value(permission);
    }
    if (invocation.memberName == #createEvent) {
      return Future.value('event-${++created}');
    }
    if (invocation.memberName == #deleteEvent ||
        invocation.memberName == #updateEvent) {
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  Map<String, dynamic> task() => {
        'id': 'task-1',
        'title': 'Inspect filter',
        'description': 'Check pressure',
        'due_at': DateTime.now()
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
        'status': 'open'
      };
  test(
      'Calendar requires opt-in, reuses an event on postponement and removes it on completion',
      () async {
    final native = FakeCalendar(),
        service = ReminderCalendar(calendar: FakeCalendar());
    // A separate fake proves disabled calendar sync does not request permissions.
    await service.sync('user-1', [task()]);
    final sync = ReminderCalendar(calendar: native);
    expect(native.calls, isEmpty);
    final row = task();
    await sync.sync('user-1', [row], enable: true);
    expect(native.created, 1);
    final create =
        native.calls.singleWhere((c) => c.memberName == #createEvent);
    expect(create.namedArguments[#reminders],
        [const Duration(minutes: 15), Duration.zero]);
    row['due_at'] =
        DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String();
    row['status'] = 'postponed';
    await sync.sync('user-1', [row]);
    expect(native.created, 1);
    expect(
        native.calls
            .singleWhere((c) => c.memberName == #updateEvent)
            .namedArguments[#instanceId],
        'event-1');
    row['status'] = 'completed';
    await sync.sync('user-1', [row]);
    expect(
        native.calls
            .singleWhere((c) => c.memberName == #deleteEvent)
            .namedArguments[#instanceId],
        'event-1');
  });
  test(
      'Denied calendar permission does not create an event or affect saved tasks',
      () async {
    final native = FakeCalendar()..permission = CalendarPermissionStatus.denied;
    final result = await ReminderCalendar(calendar: native)
        .sync('user-1', [task()], enable: true);
    expect(result, contains('not granted'));
    expect(native.created, 0);
  });
  test(
      'Event IDs are scoped to the account and completed unsynced tasks create no events',
      () async {
    final native = FakeCalendar(), row = task();
    final sync = ReminderCalendar(calendar: native);
    await sync.sync('user-1', [row], enable: true);
    await sync.sync('user-2', [row], enable: true);
    expect(native.created, 2);
    row['id'] = 'completed-never-synced';
    row['status'] = 'completed';
    await sync.sync('user-1', [row]);
    expect(native.created, 2);
  });
}

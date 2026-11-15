import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device event IDs are local to this device AND signed-in account.
/// A recipient's phone must open the app to reconcile assigned work.
class ReminderCalendar {
  ReminderCalendar({DeviceCalendar? calendar})
      : _calendar = calendar ?? DeviceCalendar.instance;
  final DeviceCalendar _calendar;
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  Future<String> sync(String uid, List<Map<String, dynamic>> rows,
      {bool enable = false}) async {
    if (!supported) return 'Calendar sync is available on iPhone and Android.';
    final prefs = await SharedPreferences.getInstance();
    if (enable) {
      final permission = await _calendar.requestPermissions();
      if (permission != CalendarPermissionStatus.granted) {
        return 'Calendar access was not granted. Enable it in phone Settings to sync reminders.';
      }
      await prefs.setBool('reminder-calendar-enabled-$uid', true);
    }
    if (prefs.getBool('reminder-calendar-enabled-$uid') != true) {
      return 'Enable phone calendar to receive task reminders.';
    }
    if (await _calendar.hasPermissions() != CalendarPermissionStatus.granted) {
      return 'Calendar access is unavailable. Check phone Settings.';
    }
    for (final row in rows) {
      final key = 'reminder-event-$uid-${row['id']}';
      final event = prefs.getString(key);
      if (row['status'] == 'completed') {
        if (event != null) {
          try {
            await _calendar.deleteEvent(instanceId: event);
          } on DeviceCalendarException catch (e) {
            if (e.errorCode != DeviceCalendarError.notFound) rethrow;
          }
          await prefs.remove(key);
        }
        continue;
      }
      final due = DateTime.parse(row['due_at']).toLocal();
      if (event == null && due.isBefore(DateTime.now())) continue;
      final title = 'Emville · ${row['title']}';
      final description = row['description']?.toString() ?? '';
      if (event != null) {
        try {
          await _calendar.updateEvent(
              instanceId: event,
              title: title,
              startDate: due,
              endDate: due.add(const Duration(minutes: 30)),
              description: Patch.set(description),
              reminders:
                  Patch.set([const Duration(minutes: 15), Duration.zero]));
          continue;
        } on DeviceCalendarException catch (e) {
          if (e.errorCode != DeviceCalendarError.notFound) rethrow;
        }
      }
      final id = await _calendar.createEvent(
          title: title,
          startDate: due,
          endDate: due.add(const Duration(minutes: 30)),
          description: description,
          reminders: [const Duration(minutes: 15), Duration.zero]);
      await prefs.setString(key, id);
    }
    return 'Phone calendar is up to date · alerts 15 minutes before tasks.';
  }
}

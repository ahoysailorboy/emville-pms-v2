import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Isolated fixture data for interaction tests and design captures. Never reaches a live service.
class EmvilleTestBackend {
  String role = 'owner';
  bool failCalendar = false;
  bool rejectBookingUpdate = false;
  final bookingUpdates = <String, Map<String, dynamic>>{};
  List<Map<String, dynamic>>? bookingRows;
  final bookingReads = <Uri>[];
  final extras = <Map<String, dynamic>>[];
  final reads = <Uri>[];
  final writes = <String>[];
  final removed = <String>{};
  final today =
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  String date(int offset) =>
      today.add(Duration(days: offset)).toIso8601String().split('T').first;
  List<Map<String, dynamic>> get main => [
        {
          'id': 'booking',
          'date': date(0),
          'amount': 42000,
          'transaction_type': 'income',
          'payee_payer_name': 'Alex Morgan',
          'remarks': 'Booking payment',
          'transaction_status': 'approved',
          'payment_mode': 'UPI',
          'created_by': 'Admin'
        },
        {
          'id': 'linen',
          'date': date(0),
          'amount': 3500,
          'transaction_type': 'expense',
          'payee_payer_name': 'Fresh Fold',
          'remarks': 'Linen & laundry',
          'transaction_status': 'approved',
          'payment_mode': 'Bank',
          'created_by': 'Admin'
        },
        {
          'id': 'garden',
          'date': date(-1),
          'amount': 2000,
          'transaction_type': 'expense',
          'payee_payer_name': 'Green Care',
          'remarks': 'Garden upkeep',
          'transaction_status': 'approved',
          'payment_mode': 'Cash',
          'created_by': 'Admin'
        },
      ];
  List<Map<String, dynamic>> get petty => [
        {
          'id': 'flowers',
          'date': date(0),
          'amount': 450,
          'transaction_type': 'expense',
          'remarks': 'Fresh flowers',
          'transaction_status': 'pending',
          'entered_by': 'Caretaker'
        },
        {
          'id': 'cleaning',
          'date': date(-1),
          'amount': 750,
          'transaction_type': 'expense',
          'remarks': 'Cleaning supplies',
          'transaction_status': 'approved',
          'entered_by': 'Caretaker'
        },
        {
          'id': 'topup',
          'date': date(-2),
          'amount': 5000,
          'transaction_type': 'income',
          'remarks': 'Cash top-up',
          'transaction_status': 'approved',
          'entered_by': 'Admin'
        },
      ];
  List<Map<String, dynamic>> get pendingMain => [
        {
          'id': 'plumbing',
          'date': date(0),
          'amount': 2800,
          'transaction_type': 'expense',
          'remarks': 'Plumbing repair',
          'transaction_status': 'pending',
          'created_by': 'Admin'
        },
        {
          'id': 'advance',
          'date': date(-1),
          'amount': 12000,
          'transaction_type': 'income',
          'remarks': 'Guest advance',
          'transaction_status': 'pending',
          'created_by': 'Admin'
        },
      ];
  Map<String, dynamic> get user => {
        'id': '00000000-0000-0000-0000-000000000001',
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'anoop@example.com',
        'app_metadata': {
          'provider': 'email',
          'providers': ['email']
        },
        'user_metadata': {'full_name': 'Anoop Thomas'},
        'created_at': '2026-01-01T00:00:00Z'
      };
  Future<void> initialize() async {
    for (final font in <String, String>{
      'EmvilleSerif': 'assets/fonts/Gelasio.ttf',
      'Roboto': 'assets/fonts/Roboto-Regular.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf'
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/shared_preferences'),
            (call) async =>
                call.method == 'getAll' ? <String, Object>{} : true);
    await Supabase.initialize(
        url: 'https://emville-test.supabase.co',
        publishableKey: 'test-key',
        httpClient: MockClient(_request),
        authOptions: const FlutterAuthClientOptions(
            localStorage: EmptyLocalStorage(),
            authFlowType: AuthFlowType.implicit,
            autoRefreshToken: false,
            detectSessionInUri: false));
  }

  Future<void> signIn() async {
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'anoop@example.com', password: 'test-password');
  }

  Future<http.Response> _request(http.Request request) async {
    if (request.method == 'GET') reads.add(request.url);
    final path = request.url.path;
    final query = request.url.queryParameters;
    dynamic body = <dynamic>[];
    var status = 200;
    if (path.contains('/auth/v1/token')) {
      final payload = base64Url
          .encode(utf8.encode(jsonEncode({
            'sub': user['id'],
            'exp': DateTime.now()
                    .add(const Duration(hours: 1))
                    .millisecondsSinceEpoch ~/
                1000
          })))
          .replaceAll('=', '');
      body = {
        'access_token': 'e30.$payload.signature',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': user
      };
    } else if (request.method == 'POST' &&
        (path.endsWith('/main_ledger') ||
            path.endsWith('/petty_cash_ledger') ||
            path.endsWith('/bookings_extras'))) {
      writes.add('POST $path ${request.body}');
      if (path.endsWith('/bookings_extras')) {
        extras.add({
          ...jsonDecode(request.body) as Map<String, dynamic>,
          'created_at': DateTime.now().toIso8601String()
        });
      }
      body = {'id': 'new-entry'};
    } else if (request.method == 'PATCH' && path.endsWith('/booking_details')) {
      final id = query['id']?.replaceFirst('eq.', '');
      if (rejectBookingUpdate || id == null) {
        status = 406;
        body = {
          'code': 'PGRST116',
          'message': 'No rows returned',
          'details': 'Results contain 0 rows'
        };
      } else {
        final patch = jsonDecode(request.body) as Map<String, dynamic>;
        bookingUpdates[id] = {...?bookingUpdates[id], ...patch};
        writes.add('PATCH $path ${request.body}');
        body = {'id': id};
      }
    } else if (request.method == 'PATCH' || request.method == 'DELETE') {
      writes.add('${request.method} $path ${request.body}');
      removed.add(
          '${path.split('/').last}/${query['id']?.replaceFirst('eq.', '')}');
      body = null;
    } else if (path.endsWith('/users') || path.endsWith('/users_v')) {
      body = [
        {'full_name': 'Anoop Thomas', 'approved': true, 'role': role}
      ];
    } else if (path.endsWith('/user_roles')) {
      body = [
        {'role': role}
      ];
    } else if (path.endsWith('/main_ledger_balance')) {
      body = [
        {'ledger_balance': 248500, 'approved_balance': 248500}
      ];
    } else if (path.endsWith('/petty_cash_balance')) {
      body = [
        {'ledger_balance': 5800, 'approved_balance': 6250}
      ];
    } else if (path.endsWith('/main_ledger')) {
      if (query['transaction_status'] == 'eq.pending') {
        body = pendingMain
            .where((r) => !removed.contains('main_ledger/${r['id']}'))
            .toList();
      } else if (query['select'] == 'amount,transaction_type') {
        body = [
          {'amount': 186000, 'transaction_type': 'income'},
          {'amount': 72400, 'transaction_type': 'expense'}
        ];
      } else if (query['select'] == 'date,amount') {
        body = [
          for (var i = 0; i < 6; i++)
            {
              'date': DateTime(today.year, today.month - 5 + i, 5)
                  .toIso8601String()
                  .split('T')
                  .first,
              'amount': [105000, 122000, 139000, 155000, 170000, 186000][i]
            }
        ];
      } else {
        body = main;
      }
    } else if (path.endsWith('/petty_cash_ledger')) {
      body = petty
          .where((r) =>
              (query['transaction_status'] != 'eq.pending' ||
                  r['transaction_status'] == 'pending') &&
              !removed.contains('petty_cash_ledger/${r['id']}'))
          .toList();
    } else if (path.endsWith('/main_pms_db')) {
      body = [
        for (final task in <(String, String, int, String)>[
          ('pool', 'Pool filter service', -2, 'Monthly'),
          ('lights', 'Check emergency lights', -1, 'Monthly'),
          ('ac', 'Air conditioner service', 1, 'Monthly'),
          ('pump', 'Inspect water pump', 1, 'Weekly')
        ])
          {
            'id': task.$1,
            'task_name': task.$2,
            'next_due_date': date(task.$3),
            'task_interval': task.$4,
            'postponed': 'no'
          }
      ];
    } else if (path.endsWith('/booking_calendar_days')) {
      if (failCalendar) {
        status = 500;
        body = {'message': 'Unavailable'};
      } else {
        body = [
          for (final d in [5, 6, 12, 14, 15, 19, 20, 26])
            {
              'day': DateTime(today.year, today.month, d).toIso8601String(),
              'status': 'confirmed'
            }
        ];
      }
    } else if (path.endsWith('/bookings_extras')) {
      body = extras
          .where((r) => query['bill_type'] == 'eq.${r['bill_type']}')
          .toList();
    } else if (path.endsWith('/booking_details')) {
      bookingReads.add(request.url);
      body = bookingRows ??
          [
            {
              'id': 'alex',
              'status': 'confirmed',
              'guest_name': 'Alex Morgan',
              'check_in': date(0),
              'check_out': date(2),
              'no_of_rooms': 2,
              'no_of_pax': 4,
              'source': 'Direct',
              'total_price': 42000,
              'advance_paid': 12000,
              'balance': 30000,
              'currency': 'INR'
            },
            {
              'id': 'jamie',
              'status': 'confirmed',
              'guest_name': 'Jamie Lee',
              'check_in': date(-1),
              'check_out': date(1),
              'no_of_rooms': 1,
              'no_of_pax': 2
            },
            {
              'id': 'lisa',
              'status': 'confirmed',
              'guest_name': 'Lisa Brown',
              'check_in': date(-2),
              'check_out': date(0),
              'no_of_rooms': 1,
              'no_of_pax': 2
            },
          ];
      body = (body as List).map((row) {
        final result = <String, dynamic>{...row, ...?bookingUpdates[row['id']]};
        if (bookingUpdates.containsKey(row['id'])) {
          result['balance'] = (result['total_price'] as num? ?? 0) -
              (result['advance_paid'] as num? ?? 0);
        }
        return result;
      }).toList();
      final idFilter = query['id'];
      if (idFilter != null) {
        body = (body)
            .where((r) => idFilter.startsWith('neq.')
                ? r['id'] != idFilter.substring(4)
                : r['id'] == idFilter.replaceFirst('eq.', ''))
            .toList();
      }
      for (final key in ['status', 'property_id']) {
        if (query[key] != null) {
          body = (body as List)
              .where((r) => query[key] == 'eq.${r[key]}')
              .toList();
        }
      }
      for (final key in ['check_in', 'check_out']) {
        final filter = query[key];
        if (filter == null ||
            (!filter.startsWith('lt.') && !filter.startsWith('gt.'))) {
          continue;
        }
        final boundary = DateTime.parse(filter.substring(3));
        body = (body as List).where((r) {
          final date = DateTime.tryParse('${r[key]}');
          return date != null &&
              (filter.startsWith('lt.')
                  ? date.isBefore(boundary)
                  : filter.startsWith('gt.')
                      ? date.isAfter(boundary)
                      : true);
        }).toList();
      }
      final offset = int.tryParse(query['offset'] ?? '0') ?? 0;
      final limit = int.tryParse(query['limit'] ?? '');
      if (limit != null) {
        body = (body as List).skip(offset).take(limit).toList();
      }
    }
    return http.Response(body == null ? '' : jsonEncode(body), status,
        request: request,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }
}

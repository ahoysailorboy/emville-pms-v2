// lib/check_email.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/features/bookings/booking_new.dart';

const _emGreen = Color(0xFF103329);
const _emGold = Color(0xFFD9A633);

class CheckEmailPage extends StatefulWidget {
  const CheckEmailPage({super.key});

  @override
  State<CheckEmailPage> createState() => _CheckEmailPageState();
}

class _CheckEmailPageState extends State<CheckEmailPage> {
  bool _loading = true;
  Object? _error;

  // Detail-mode state
  Map<String, dynamic>? _emailRow;
  Map<String, dynamic>? _parsed;

  // List-mode state
  List<Map<String, dynamic>> _rows = [];
  bool _listMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _emailRow = null;
      _parsed = null;
      _rows = [];
    });

    try {
      final args = ModalRoute.of(context)?.settings.arguments;
      final Map<String, dynamic> data = (args is Map)
          ? args.cast<String, dynamic>()
          : const <String, dynamic>{};

      final String? messageId = (() {
        final v =
            (data['message_id'] ?? data['gmail_message_id'] ?? data['id']);
        final s = v?.toString().trim();
        return (s == null || s.isEmpty) ? null : s;
      })();

      if (messageId == null) {
        _listMode = true;
        await _loadList();
      } else {
        _listMode = false;
        await _loadDetail(messageId);
      }
    } catch (e) {
      _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadDetail(String messageId) async {
    final supa = Supabase.instance.client;
    final row = await supa
        .from('emails_ingested')
        .select(
            'message_id,from_addr,subject,snippet,raw,received_at,booking_id')
        .eq('message_id', messageId)
        .maybeSingle();

    if (row == null) {
      throw StateError('Email not found: $messageId');
    }

    final parsed = _parseEmail(
      from: (row['from_addr'] as String?) ?? '',
      subject: (row['subject'] as String?) ?? '',
      snippet: (row['snippet'] as String?) ?? '',
      raw: row['raw'],
      receivedAtIso: row['received_at'] as String?,
    );

    setState(() {
      _emailRow = Map<String, dynamic>.from(row);
      _parsed = parsed;
    });
  }

  Future<void> _loadList() async {
    final supa = Supabase.instance.client;
    final List<dynamic> rows = await supa
        .from('emails_ingested')
        .select(
            'message_id,from_addr,subject,snippet,raw,received_at,booking_id')
        .order('received_at', ascending: false);

    final parsedRows = rows.map<Map<String, dynamic>>((r) {
      final m = Map<String, dynamic>.from(r as Map);
      final parsed = _parseEmail(
        from: (m['from_addr'] as String?) ?? '',
        subject: (m['subject'] as String?) ?? '',
        snippet: (m['snippet'] as String?) ?? '',
        raw: m['raw'],
        receivedAtIso: m['received_at'] as String?,
      );
      m['_parsed'] = parsed;

      final bool converted = _isConverted(m);
      m['_converted'] = converted;
      m['_group'] = converted ? 1 : 0;
      return m;
    }).toList();

    parsedRows.sort((a, b) {
      final ga = a['_group'] as int;
      final gb = b['_group'] as int;
      if (ga != gb) return ga.compareTo(gb);

      final da = DateTime.tryParse(a['received_at'] ?? '') ?? DateTime(1970);
      final db = DateTime.tryParse(b['received_at'] ?? '') ?? DateTime(1970);
      return db.compareTo(da);
    });

    setState(() => _rows = parsedRows);
  }

  bool _isConverted(Map<String, dynamic> row) {
    final bid = row['booking_id'];
    return bid != null && '$bid'.trim().isNotEmpty;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Email parsing (Airbnb confirmed/enquiry + Booking.com placeholders)

  Map<String, dynamic> _parseEmail({
    required String from,
    required String subject,
    required String snippet,
    required dynamic raw,
    String? receivedAtIso,
  }) {
    final body = _extractBody(raw) ?? snippet;
    final lowerFrom = from.toLowerCase();

    String source = 'Other';
    if (lowerFrom.contains('airbnb')) source = 'AirBnB';
    if (lowerFrom.contains('booking.com')) source = 'Booking.com';

    final DateTime? receivedAt =
        (receivedAtIso != null) ? DateTime.tryParse(receivedAtIso) : null;
    final int inferredYear = (receivedAt ?? DateTime.now()).year;

    final status = _detectStatus(source: source, subject: subject, body: body);

    if (status == 'unknown') {
      return {
        'source': source,
        'status': status,
        'guest_name': null,
        'check_in': null,
        'check_out': null,
        'pax': null,
        'payout_net': null,
        'confirmation_code': null,
        'subject': subject,
        'from_addr': from,
      };
    }

    final bool isConfirmed = status == 'confirmed';

    String? guest;
    Map<String, String>? dates;
    int? pax;
    double? payoutNet;
    String? confCode;

    if (source == 'AirBnB') {
      guest = _extractGuestNameAirbnb(subject, body) ??
          _extractGuestNameGeneric(subject, body);

      // now passes inferredYear and looks at both subject + body
      dates = _extractDatesAirbnb(body, inferredYear) ??
          _extractDatesGeneric(subject, body, inferredYear);

      pax = _extractPaxAirbnb(body) ?? _extractPaxGeneric(body);

      if (isConfirmed) {
        payoutNet = _extractPayoutAirbnb(body) ?? _extractPayoutGeneric(body);
        confCode = _extractConfirmationCodeAirbnb(subject, body);
      }
    } else if (source == 'Booking.com') {
      guest = _extractGuestNameGeneric(subject, body);

      // added inferredYear and subject parsing
      dates = _extractDatesGeneric(subject, body, inferredYear);

      pax = _extractPaxGeneric(body);

      if (isConfirmed) {
        payoutNet = _extractPayoutBooking(body) ?? _extractPayoutGeneric(body);
        confCode = _extractConfirmationCodeGeneric(subject, body);
      }
    } else {
      guest = _extractGuestNameGeneric(subject, body);

      // added inferredYear and subject parsing
      dates = _extractDatesGeneric(subject, body, inferredYear);

      pax = _extractPaxGeneric(body);

      if (isConfirmed) {
        payoutNet = _extractPayoutGeneric(body);
        confCode = _extractConfirmationCodeGeneric(subject, body);
      }
    }

    return {
      'source': source,
      'status': status,
      'guest_name': guest,
      'check_in': dates?['check_in'],
      'check_out': dates?['check_out'],
      'pax': pax,
      'payout_net': payoutNet,
      'confirmation_code': confCode,
      'subject': subject,
      'from_addr': from,
    };
  }

  String? _extractBody(dynamic raw) {
    return null;
  }

  String _detectStatus(
      {required String source, required String subject, required String body}) {
    final s = ('$subject\n$body').toLowerCase();

    final isAirbnbEnquiry = s.contains("respond to") && s.contains("inquiry") ||
        s.contains("enquiry") ||
        s.contains("pre-approve") ||
        s.contains("preapprove") ||
        s.contains("you have 24 hours to respond");

    final isAirbnbConfirmed = s.contains("booking confirmed") ||
        s.contains("new booking confirmed") ||
        s.contains("confirmation code");

    if (source == 'AirBnB') {
      if (isAirbnbConfirmed) return 'confirmed';
      if (isAirbnbEnquiry) return 'enquiry';
    }

    if (source == 'Booking.com') {
      final isConfirmed =
          s.contains("confirmed") || s.contains("reservation confirmed");
      final isEnquiry = s.contains("request") ||
          s.contains("pending") ||
          s.contains("inquiry");
      if (isConfirmed) return 'confirmed';
      if (isEnquiry) return 'enquiry';
    }

    return 'unknown';
  }

  String? _extractGuestNameAirbnb(String subject, String body) {
    final r1 = RegExp(
      r"confirmed!\s+([A-Z][A-Za-z]+(?:\s+[A-Z][A-Za-z]+){0,3})\s+arrives",
      caseSensitive: false,
    );
    final m1 = r1.firstMatch(subject);
    if (m1 != null) return m1.group(1);

    final r2 = RegExp(
      r"^\s*Guest(?:\s*name)?\s*:\s*(.+)$",
      caseSensitive: false,
      multiLine: true,
    );
    final m2 = r2.firstMatch(body);
    if (m2 != null) {
      return m2.group(1)!.trim().replaceAll(RegExp(r"[.,;:]+$"), "");
    }

    final r3 = RegExp(
      r"^[ \t]*([A-Z][A-Za-z]+(?:\s+[A-Z][A-Za-z]+){0,3})[ \t]*$",
      multiLine: true,
    );
    final m3 = r3.firstMatch(body);
    if (m3 != null) return m3.group(1);

    return null;
  }

  String? _extractGuestNameGeneric(String subject, String body) {
    final r1 = RegExp(
      r"\bfor\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,3})\b",
      caseSensitive: false,
    );
    final m1 = r1.firstMatch(subject);
    if (m1 != null) return m1.group(1);

    final r2 = RegExp(
      r"^\s*Guest(?:\s*name)?\s*:\s*(.+)$",
      caseSensitive: false,
      multiLine: true,
    );
    final m2 = r2.firstMatch(body);
    if (m2 != null) {
      return m2.group(1)!.trim().replaceAll(RegExp(r"[.,;:]+$"), "");
    }

    final r3 = RegExp(
      r"^\s*Name\s*:\s*(.+)$",
      caseSensitive: false,
      multiLine: true,
    );
    final m3 = r3.firstMatch(body);
    if (m3 != null) {
      return m3.group(1)!.trim().replaceAll(RegExp(r"[.,;:]+$"), "");
    }

    return null;
  }

  Map<String, String>? _extractDatesAirbnb(String text, int yearHint) {
    String? cin;
    String? cout;

    final rIn = RegExp(
      r"check[- ]?in.*?\b([A-Za-z]{3},?\s+[A-Za-z]{3,}\s+\d{1,2})",
      caseSensitive: false,
      dotAll: true,
    );
    final mIn = rIn.firstMatch(text);

    final rOut = RegExp(
      r"check[- ]?out.*?\b([A-Za-z]{3},?\s+[A-Za-z]{3,}\s+\d{1,2})",
      caseSensitive: false,
      dotAll: true,
    );
    final mOut = rOut.firstMatch(text);
    if (mIn != null) cin = _normalizeAirbnbDate(mIn.group(1)!, yearHint);
    if (mOut != null) cout = _normalizeAirbnbDate(mOut.group(1)!, yearHint);

    if (cin == null && cout == null) return null;
    return {
      if (cin != null) 'check_in': cin,
      if (cout != null) 'check_out': cout,
    };
  }

  String _normalizeAirbnbDate(String d, int yearHint) {
    final cleaned = d
        .trim()
        .replaceAll(
          RegExp(r'(mon|tue|wed|thu|fri|sat|sun),?\s*', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'^\s*,\s*'), '')
        .trim();

    try {
      final parsed = DateFormat('MMM d').parseStrict(cleaned);
      final withYear = DateTime(yearHint, parsed.month, parsed.day);
      return DateFormat('yyyy-MM-dd').format(withYear);
    } catch (_) {
      try {
        final parsed = DateFormat('MMMM d').parseStrict(cleaned);
        final withYear = DateTime(yearHint, parsed.month, parsed.day);
        return DateFormat('yyyy-MM-dd').format(withYear);
      } catch (_) {
        return cleaned;
      }
    }
  }

  Map<String, String>? _extractDatesGeneric(
    String subject,
    String body, [
    int? yearHint, // optional: helps when year is missing (e.g., "Mar 3–5")
  ]) {
    final text = '${_normalizeDashes(subject)}\n${_normalizeDashes(body)}';

    String? cin;
    String? cout;

    String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

    DateTime? tryParseDayMonYear(String s) {
      try {
        return DateFormat('d MMM yyyy').parseStrict(s);
      } catch (_) {}
      try {
        return DateFormat('d MMMM yyyy').parseStrict(s);
      } catch (_) {}
      return null;
    }

    int? monNum(String mon) {
      const m = {
        'jan': 1,
        'january': 1,
        'feb': 2,
        'february': 2,
        'mar': 3,
        'march': 3,
        'apr': 4,
        'april': 4,
        'may': 5,
        'jun': 6,
        'june': 6,
        'jul': 7,
        'july': 7,
        'aug': 8,
        'august': 8,
        'sep': 9,
        'sept': 9,
        'september': 9,
        'oct': 10,
        'october': 10,
        'nov': 11,
        'november': 11,
        'dec': 12,
        'december': 12,
      };
      return m[mon.toLowerCase()];
    }

    DateTime? safeDate(int y, int m, int d) {
      try {
        return DateTime(y, m, d);
      } catch (_) {
        return null;
      }
    }

    int inferYear(int? y) => y ?? yearHint ?? DateTime.now().year;

    // A) "Mar 3–5, 2026" or "Mar 3-5, 2026"
    final r1 = RegExp(
      r'\b([A-Za-z]{3,9})\s+(\d{1,2})\s*[–-]\s*(\d{1,2}),\s*(\d{4})\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (r1 != null) {
      final m = monNum(r1.group(1)!);
      final d1 = int.parse(r1.group(2)!);
      final d2 = int.parse(r1.group(3)!);
      final y = int.parse(r1.group(4)!);
      if (m != null) {
        final a = safeDate(y, m, d1);
        final b = safeDate(y, m, d2);
        if (a != null && b != null) {
          cin ??= ymd(a);
          cout ??= ymd(b);
        }
      }
    }

    // B) "3–5 Mar 2026" or "3-5 March 2026" (year optional)
    if (cin == null || cout == null) {
      final r2 = RegExp(
        r'\b(\d{1,2})\s*[–-]\s*(\d{1,2})\s+([A-Za-z]{3,9})(?:\s+(\d{4}))?\b',
        caseSensitive: false,
      ).firstMatch(text);
      if (r2 != null) {
        final d1 = int.parse(r2.group(1)!);
        final d2 = int.parse(r2.group(2)!);
        final m = monNum(r2.group(3)!);
        final y = inferYear(int.tryParse(r2.group(4) ?? ''));
        if (m != null) {
          final a = safeDate(y, m, d1);
          final b = safeDate(y, m, d2);
          if (a != null && b != null) {
            cin ??= ymd(a);
            cout ??= ymd(b);
          }
        }
      }
    }

    // C) "Mar 30 - Apr 2, 2026" (month changes)
    if (cin == null || cout == null) {
      final r3 = RegExp(
        r'\b([A-Za-z]{3,9})\s+(\d{1,2})\s*[–-]\s*([A-Za-z]{3,9})\s+(\d{1,2}),\s*(\d{4})\b',
        caseSensitive: false,
      ).firstMatch(text);
      if (r3 != null) {
        final m1 = monNum(r3.group(1)!);
        final d1 = int.parse(r3.group(2)!);
        final m2 = monNum(r3.group(3)!);
        final d2 = int.parse(r3.group(4)!);
        final y = int.parse(r3.group(5)!);
        if (m1 != null && m2 != null) {
          final a = safeDate(y, m1, d1);
          final b = safeDate(y, m2, d2);
          if (a != null && b != null) {
            cin ??= ymd(a);
            cout ??= ymd(b);
          }
        }
      }
    }

    // D) "Check-in: 1 Mar 2026" / "Check-out: 3 Mar 2026"
    if (cin == null || cout == null) {
      final inLine = RegExp(
        r'\bcheck[-\s]*in\b\s*[:\-]?\s*(\d{1,2}\s+[A-Za-z]{3,9}\s+\d{4})',
        caseSensitive: false,
      ).firstMatch(text);
      final outLine = RegExp(
        r'\bcheck[-\s]*out\b\s*[:\-]?\s*(\d{1,2}\s+[A-Za-z]{3,9}\s+\d{4})',
        caseSensitive: false,
      ).firstMatch(text);

      final a = inLine != null ? tryParseDayMonYear(inLine.group(1)!) : null;
      final b = outLine != null ? tryParseDayMonYear(outLine.group(1)!) : null;
      if (a != null) cin ??= ymd(a);
      if (b != null) cout ??= ymd(b);
    }

    // E) "from 1 Mar 2026 to 3 Mar 2026"
    if (cin == null || cout == null) {
      final range = RegExp(
        r'\bfrom\s+(\d{1,2}\s+[A-Za-z]{3,9}\s+\d{4})\s+to\s+(\d{1,2}\s+[A-Za-z]{3,9}\s+\d{4})',
        caseSensitive: false,
      ).firstMatch(text);

      if (range != null) {
        final a = tryParseDayMonYear(range.group(1)!);
        final b = tryParseDayMonYear(range.group(2)!);
        if (a != null && b != null) {
          cin ??= ymd(a);
          cout ??= ymd(b);
        }
      }
    }

    // F) Bare ISO fallback "yyyy-MM-dd ... yyyy-MM-dd"
    if (cin == null || cout == null) {
      final iso = RegExp(r'\b(\d{4}-\d{2}-\d{2})\b');
      final all = iso.allMatches(text).map((m) => m.group(1)!).toList();
      if (all.length >= 2) {
        cin ??= all[0];
        cout ??= all[1];
      }
    }

    // G) "Mar 3-5" WITHOUT year → use yearHint if present
    if ((cin == null || cout == null) && yearHint != null) {
      final r = RegExp(
        r'\b([A-Za-z]{3,9})\s+(\d{1,2})\s*[–-]\s*(\d{1,2})\b',
        caseSensitive: false,
      ).firstMatch(text);
      if (r != null) {
        final m = monNum(r.group(1)!);
        final d1 = int.parse(r.group(2)!);
        final d2 = int.parse(r.group(3)!);
        final y = yearHint;
        if (m != null) {
          final a = safeDate(y, m, d1);
          final b = safeDate(y, m, d2);
          if (a != null && b != null) {
            cin ??= ymd(a);
            cout ??= ymd(b);
          }
        }
      }
    }

    if (cin == null && cout == null) return null;
    return {
      if (cin != null) 'check_in': cin,
      if (cout != null) 'check_out': cout,
    };
  }

// normalize en/em dashes to a plain hyphen to simplify regex
  String _normalizeDashes(String s) =>
      s.replaceAll('\u2013', '-').replaceAll('\u2014', '-');

  int? _extractPaxAirbnb(String body) {
    final m = RegExp(
      r'guests?\s*[\r\n ]+(\d{1,2})\s+adults?',
      caseSensitive: false,
    ).firstMatch(body);

    if (m != null) {
      final v = int.tryParse(m.group(1)!);
      if (v != null && v >= 1 && v <= 20) return v;
    }

    final m2 = RegExp(
      r'guests?\s*[:\-]?\s*(\d{1,2})(?:\s+adults?)?',
      caseSensitive: false,
    ).firstMatch(body);

    if (m2 != null) {
      final v = int.tryParse(m2.group(1)!);
      if (v != null && v >= 1 && v <= 20) return v;
    }

    return null;
  }

  int? _extractPaxGeneric(String text) {
    final m = RegExp(
      r'\bguests?\b.*?(\d{1,2})',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(text);

    if (m != null) {
      final v = int.tryParse(m.group(1)!);
      if (v != null && v >= 1 && v <= 20) return v;
    }

    final m2 = RegExp(
      r'\bguests?\b\s*[:\-]?\s*(\d{1,2})',
      caseSensitive: false,
    ).firstMatch(text);

    if (m2 != null) {
      final v = int.tryParse(m2.group(1)!);
      if (v != null && v >= 1 && v <= 20) return v;
    }

    return null;
  }

  double? _extractPayoutAirbnb(String body) {
    final m1 = RegExp(
      r'\byou\s+earn\b.*?([₹$]|INR|Rs\.?)\s*([0-9,]+(?:\.[0-9]+)?)',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(body);
    if (m1 != null) {
      return double.tryParse(m1.group(2)!.replaceAll(',', ''));
    }

    final m2 = RegExp(
      r'\b(host\s+)?payout\b.*?([₹$]|INR|Rs\.?)\s*([0-9,]+(?:\.[0-9]+)?)',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(body);
    if (m2 != null) {
      return double.tryParse(m2.group(3)!.replaceAll(',', ''));
    }

    return null;
  }

  double? _extractPayoutBooking(String body) {
    final regex = RegExp(
      r"(amount\s+you(?:'|’|‘)ll\s+receive|payout)\b.*?(?:₹|\$|INR|Rs\.?)\s*([0-9,]+(?:\.[0-9]+)?)",
      caseSensitive: false,
      dotAll: true,
    );
    final m = regex.firstMatch(body);
    if (m != null) {
      final value = m.group(2)?.replaceAll(',', '');
      return double.tryParse(value ?? '');
    }
    return null;
  }

  double? _extractPayoutGeneric(String text) {
    final regex = RegExp(
      r"\b(payout|you\s+earn|amount\s+you(?:'|’|‘)ll\s+receive)\b.*?(?:₹|\$|INR|Rs\.?)\s*([0-9,]+(?:\.[0-9]+)?)",
      caseSensitive: false,
      dotAll: true,
    );
    final m = regex.firstMatch(text);
    if (m != null) {
      final value = m.group(2)?.replaceAll(',', '');
      return double.tryParse(value ?? '');
    }
    return null;
  }

  String? _extractConfirmationCodeAirbnb(String subject, String body) {
    final m1 = RegExp(
      r'confirmation\s+code\s*[:\s]\s*([A-Z0-9\-]{5,})',
      caseSensitive: false,
    ).firstMatch(body);
    if (m1 != null) return m1.group(1);

    final m2 = RegExp(
      r'\b([A-Z0-9]{6,})\b',
      caseSensitive: false,
    ).firstMatch(subject);
    return m2?.group(1);
  }

  String? _extractConfirmationCodeGeneric(String subject, String body) {
    final m = RegExp(
      r'\b(confirmation\s*code|code)\b[:\s]*([A-Z0-9\-]{5,})',
      caseSensitive: false,
    ).firstMatch('$subject\n$body');
    return m?.group(2);
  }

  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final argsPretty = _pretty(ModalRoute.of(context)?.settings.arguments);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Incoming Mail'),
        backgroundColor: _emGreen,
        foregroundColor: Colors.white,
        actions: _listMode
            ? [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _load,
                ),
              ]
            : null,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorBox(error: _error, onRetry: _load)
                : _listMode
                    ? _buildListMode()
                    : _buildDetailMode(argsPretty),
      ),
    );
  }

  // ---------- LIST MODE UI ----------
  Widget _buildListMode() {
    if (_rows.isEmpty) {
      return const Center(child: Text('No emails found.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final row = _rows[i];
          final parsed = Map<String, dynamic>.from(row['_parsed'] ?? {});
          final converted = row['_converted'] == true;

          final guest = (parsed['guest_name'] as String?) ?? '—';
          final status = (parsed['status'] as String?) ?? 'unknown';
          final cin = (parsed['check_in'] as String?) ?? '—';
          final cout = (parsed['check_out'] as String?) ?? '—';
          final source = (parsed['source'] as String?) ?? '—';

          final receivedAt = row['received_at'] as String?;
          final when = _fmtWhen(receivedAt);

          return Dismissible(
            key: ValueKey(row['message_id']),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: Colors.red.shade400,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (_) async {
              return await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Delete email?'),
                      content: const Text(
                        'This will permanently delete the email record from emails_ingested.',
                      ),
                      actions: [
                        TextButton(
                          child: const Text('Cancel'),
                          onPressed: () => Navigator.of(context).pop(false),
                        ),
                        TextButton(
                          child: const Text('Delete'),
                          onPressed: () => Navigator.of(context).pop(true),
                        ),
                      ],
                    ),
                  ) ??
                  false;
            },
            onDismissed: (_) => _deleteRow(row['message_id']),
            child: ListTile(
              tileColor: converted ? Colors.grey.shade100 : Colors.white,
              leading: CircleAvatar(
                backgroundColor: converted ? Colors.grey.shade400 : _emGold,
                foregroundColor: _emGreen,
                child:
                    Icon(converted ? Icons.done_all : Icons.mark_email_unread),
              ),
              title: Text(
                guest == '—' ? (row['subject'] ?? 'Email') : guest,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: converted ? Colors.grey.shade600 : _emGreen,
                ),
              ),
              subtitle: Text(
                'Status: ${status.toUpperCase()} • $source • $cin → $cout\n$when',
              ),
              isThreeLine: true,
              trailing: converted
                  ? const SizedBox.shrink()
                  : const Icon(Icons.chevron_right),
              onTap: () => _openEmail(row['message_id'] as String),
            ),
          );
        },
      ),
    );
  }

  // ✅ Push the SAME page directly, with RouteSettings carrying message_id
  Future<void> _openEmail(String messageId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CheckEmailPage(),
        settings: RouteSettings(arguments: {'message_id': messageId}),
      ),
    );
    // refresh list when returning (shows "converted" immediately)
    if (mounted) _load();
  }

  Future<void> _deleteRow(String messageId) async {
    final supa = Supabase.instance.client;
    try {
      await supa.from('emails_ingested').delete().eq('message_id', messageId);
      setState(() => _rows.removeWhere((r) => r['message_id'] == messageId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deleted.')),
      );
    } catch (e) {
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  String _fmtWhen(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final now = DateTime.now();
    if (dt.year == now.year) {
      return DateFormat('MMM d • h:mm a').format(dt);
    }
    return DateFormat('MMM d, yyyy • h:mm a').format(dt);
  }

  // ---------- DETAIL MODE UI ----------
  Widget _buildDetailMode(String argsPretty) {
    if (_emailRow == null) {
      return const Center(child: Text('No email loaded'));
    }
    final bool converted = _isConverted(_emailRow!);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📩 Email',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          _kv('From', _emailRow!['from_addr']),
          _kv('Subject', _emailRow!['subject']),
          _kv('Received', _emailRow!['received_at']),
          const SizedBox(height: 8),
          Text(_emailRow!['snippet'] ?? '',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          const Text('🧠 Parsed fields',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          _kv('Status', _parsed?['status']),
          _kv('Source', _parsed?['source']),
          _kv('Guest', _parsed?['guest_name']),
          _kv('Check-in', _parsed?['check_in']),
          _kv('Check-out', _parsed?['check_out']),
          _kv('Pax', _parsed?['pax']),
          _kv('Payout (INR)', _fmtAmt(_parsed?['payout_net'])),
          _kv('Conf. code', _parsed?['confirmation_code']),
          const SizedBox(height: 16),
          if (!converted)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _emGold,
                  foregroundColor: _emGreen,
                ),
                onPressed: () => _gotoCreateBooking(context),
                icon: const Icon(Icons.add_task),
                label: const Text(
                  'Reserve booking based on email',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: const Text(
                'Already converted to booking.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          const Text('Debug payload (args):',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          Text(argsPretty,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Future<void> _gotoCreateBooking(BuildContext context) async {
    final String? status =
        (_parsed?['status'] as String?)?.toLowerCase().trim();
    final String? guest = _parsed?['guest_name'] as String?;
    final String? checkIn = _parsed?['check_in'] as String?;
    final String? checkOut = _parsed?['check_out'] as String?;
    final String? source = _parsed?['source'] as String?;
    final String? confCode = _parsed?['confirmation_code'] as String?;
    final String? subj =
        (_parsed?['subject'] as String?) ?? (_emailRow?['subject'] as String?);
    final String? msgId = (_emailRow?['message_id'] as String?)?.trim();

    double? _toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse('$v'.replaceAll(',', ''));
    }

    int? _toInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v');
    }

    final double? payoutNet = _toDouble(_parsed?['payout_net']);
    final int? pax = _toInt(_parsed?['pax']);

    if (status == null || (status != 'confirmed' && status != 'enquiry')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('This email is not a booking or enquiry.')),
      );
      return;
    }

    final args = <String, dynamic>{
      'prefill_status': status,
      'prefill_guest_name': guest,
      'prefill_check_in': checkIn,
      'prefill_check_out': checkOut,
      'prefill_source': source,
      'prefill_advance': payoutNet,
      'prefill_pax': pax,
      'confirmation_code': confCode,
      'email_subject': subj,
      'email_message_id': msgId,
    };

    // Push BookingNewPage directly and await the result (bookingId).
    final bookingId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BookingNewPage(),
        settings: RouteSettings(arguments: args),
      ),
    );

    // If booking was created and returned, link it and refresh detail view.
    if (bookingId != null && bookingId.trim().isNotEmpty && _emailRow != null) {
      try {
        final supa = Supabase.instance.client;
        await supa.from('emails_ingested').update({'booking_id': bookingId}).eq(
            'message_id', _emailRow!['message_id']);
        await _loadDetail(_emailRow!['message_id'] as String);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Booking created and email linked.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to link booking: $e')),
          );
        }
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  Widget _kv(String k, Object? v) {
    final s = (v == null || '$v'.trim().isEmpty) ? '—' : '$v';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              k,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, color: _emGreen),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(s)),
        ],
      ),
    );
  }

  String _fmtAmt(dynamic v) {
    if (v == null) return '—';
    final n = (v is num) ? v.toDouble() : double.tryParse('$v');
    if (n == null) return '—';
    return n.toStringAsFixed(2);
  }

  String _pretty(Object? o) {
    if (o == null) return '{}';
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(o);
    } catch (_) {
      return o.toString();
    }
  }
}

class _ErrorBox extends StatelessWidget {
  final Object? error;
  final Future<void> Function() onRetry;
  const _ErrorBox({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
            const SizedBox(height: 10),
            Text('Failed to load.\n${error ?? ''}',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _emGold,
                foregroundColor: _emGreen,
              ),
              onPressed: onRetry,
              child: const Text('Retry'),
            )
          ],
        ),
      ),
    );
  }
}

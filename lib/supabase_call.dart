import 'package:supabase_flutter/supabase_flutter.dart';

Future<T> supabaseCall<T>(Future<T> Function() run) async {
  final client = Supabase.instance.client;
  try {
    return await run();
  } on PostgrestException catch (e) {
    // In Supabase Flutter 2.x, only `code` is available
    final is401 = e.code == 'PGRST301'; // expired / invalid JWT
    if (is401) {
      try {
        await client.auth.refreshSession();
        return await run(); // retry once after refreshing
      } catch (_) {
        rethrow;
      }
    }
    rethrow;
  }
}

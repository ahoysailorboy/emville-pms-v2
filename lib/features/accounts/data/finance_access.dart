import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolve privileges from the signed-in user's database roles, never editable user metadata.
abstract final class FinanceAccess {
  static Future<bool> isOwnerOrAdmin(SupabaseClient client) async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      final roles =
          await client.from('user_roles').select('role').eq('user_id', uid);
      return roles.any((r) => r['role'] == 'owner' || r['role'] == 'admin');
    } catch (_) {
      return false;
    }
  }
}

class AccountBalance {
  const AccountBalance({required this.approved, this.ledger});
  final num? approved, ledger;
  factory AccountBalance.fromRow(Map<String, dynamic>? row) => AccountBalance(
      approved: row?['approved_balance'] as num?,
      ledger: row?['ledger_balance'] as num?);
}

class AccountsOverview {
  const AccountsOverview(
      {required this.privileged,
      required this.petty,
      required this.pending,
      this.main});
  final bool privileged;
  final AccountBalance petty;
  final AccountBalance? main;
  final int pending;
}

class AccountsRepository {
  AccountsRepository(this.client);
  final SupabaseClient client;
  Future<AccountsOverview> load() async {
    final privileged = await FinanceAccess.isOwnerOrAdmin(client);
    final uid = client.auth.currentUser?.id;
    final petty = await client
        .from('petty_cash_balance')
        .select(
            privileged ? 'approved_balance,ledger_balance' : 'approved_balance')
        .limit(1)
        .maybeSingle();
    Map<String, dynamic>? main;
    if (privileged) {
      main = await client
          .from('main_ledger_balance')
          .select('approved_balance,ledger_balance')
          .limit(1)
          .maybeSingle();
    }
    Future<int> pending(String table) async {
      var query =
          client.from(table).select('id').eq('transaction_status', 'pending');
      if (!privileged) {
        if (uid == null) return 0;
        query = query.eq('creator_uuid', uid);
      }
      return (await query).length;
    }

    final counts = await Future.wait(
        [pending('main_ledger'), pending('petty_cash_ledger')]);
    return AccountsOverview(
        privileged: privileged,
        petty: AccountBalance.fromRow(petty),
        main: privileged ? AccountBalance.fromRow(main) : null,
        pending: counts.fold(0, (a, b) => a + b));
  }
}

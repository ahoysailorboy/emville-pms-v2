// Deno Edge function: accounts_approval_notify
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

type HookPayload = {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: "main_ledger" | "petty_cash_ledger" | string;
  record?: Record<string, unknown>;
  old_record?: Record<string, unknown>;
};

interface OneSignalPayload {
  app_id: string;
  included_segments?: string[];                 // we'll target Admins
  exclude_external_user_ids?: string[];         // exclude the creator
  headings: { en: string };
  contents: { en: string };
  subtitle?: { en: string };
  data?: Record<string, string>;
  ios_sound?: string;
  priority?: number;
}

async function sendPush(p: OneSignalPayload) {
  const apiKey = Deno.env.get("ONESIGNAL_API_KEY")!;
  const res = await fetch("https://onesignal.com/api/v1/notifications", {
    method: "POST",
    headers: {
      Authorization: `Basic ${apiKey}`,
      "Content-Type": "application/json; charset=utf-8",
    },
    body: JSON.stringify(p),
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`OneSignal error: ${res.status} ${t}`);
  }
}

function fmtInr(amount: unknown): string {
  const n = Number(amount ?? 0);
  if (!isFinite(n)) return "0.00";
  // keep it simple; your app shows INR in locale anyway
  return n.toFixed(2);
}

Deno.serve(async (req) => {
  try {
    // Simple shared-secret to ensure only your DB webhook calls this
    const expected = Deno.env.get("ACCOUNTS_HOOK_SECRET");
    const got = req.headers.get("x-hook-secret");
    if (expected && got !== expected) {
      return new Response(JSON.stringify({ ok: false, error: "unauthorized" }), {
        status: 401,
        headers: { "content-type": "application/json" },
      });
    }

    const body = (await req.json()) as HookPayload;

    // Only act on INSERTs into our two ledgers
    if (body.type !== "INSERT" || !body.record) {
      return new Response(JSON.stringify({ ok: true, skipped: true }), {
        headers: { "content-type": "application/json" },
      });
    }

    const table = body.table as string;
    const rec = body.record as Record<string, unknown>;

    // Expect these common fields (based on your codebase):
    // amount: number   (main_ledger.amount / petty_cash_ledger.amount)
    // transaction_type: 'income' | 'expense'
    // approved_by: string | null
    // creator_uuid: string (auth uid of submitter)
    const approvedBy = rec["approved_by"];
    const transactionType = String(rec["transaction_type"] ?? "").toLowerCase();
    const amount = rec["amount"];
    const creatorUuid = String(rec["creator_uuid"] ?? "").trim();

    // Ignore if already approved (defensive)
    if (approvedBy != null) {
      return new Response(JSON.stringify({ ok: true, skipped: "already-approved" }), {
        headers: { "content-type": "application/json" },
      });
    }

    const appId = Deno.env.get("ONESIGNAL_APP_ID")!;
    // Segment name that contains your admins (configure in OneSignal)
    const adminsSegment = Deno.env.get("ONESIGNAL_ADMINS_SEGMENT") ?? "Admins";

    // Title by table
    const isMain = table === "main_ledger";
    const title = isMain
      ? "Pending Main Cash Account Approval"
      : table === "petty_cash_ledger"
      ? "Pending Petty Cash Account Approval"
      : "Pending Account Approval";

    // Subtitle by transaction type
    const subtitle = transactionType === "expense" ? "Expense Receipt" : "Income Receipt";

    // Body with INR amount
    const bodyText = `Approval pending for INR ${fmtInr(amount)}`;

    // Route for your app to open the correct pending approvals page
    // (Your Flutter app should route on this `data.route` value.)
    const route = isMain
      ? "main_accounts_pending_approvals"
      : "petty_cash_pending_approvals";

    const payload: OneSignalPayload = {
      app_id: appId,
      included_segments: [adminsSegment],
      // exclude the submitter (works if you set OneSignal external_user_id = auth.uid)
      exclude_external_user_ids: creatorUuid ? [creatorUuid] : undefined,
      headings: { en: title },
      subtitle: { en: subtitle },
      contents: { en: bodyText },
      data: {
        route,            // <- your app uses this to navigate
        table,            // optional context
        type: "pending_approval",
      },
      ios_sound: "default",
      priority: 10,
    };

    await sendPush(payload);

    return new Response(JSON.stringify({ ok: true, sent: true }), {
      headers: { "content-type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e) }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }
});
// supabase/functions/email_poll/index.ts
// Deno Edge function to poll Gmail and push via OneSignal
// - Dedupes via public.email_seen
// - Stores email into public.emails_ingested (now includes `parsed` jsonb)
// - Sends OneSignal push with { route: "check_email", message_id }
// - Marks Gmail messages as read (optional)

// Edge runtime types
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// Gmail endpoints
const GMAIL_TOKEN_URL = "https://oauth2.googleapis.com/token";
const GMAIL_LIST_URL =
  "https://gmail.googleapis.com/gmail/v1/users/me/messages";
const GMAIL_MSG_URL =
  "https://gmail.googleapis.com/gmail/v1/users/me/messages/";
const GMAIL_MODIFY_URL =
  "https://gmail.googleapis.com/gmail/v1/users/me/messages/"; // + {id}/modify

// Minimal Gmail types
type GmailHeader = { name: string; value: string };
type GmailPart = {
  mimeType?: string;
  filename?: string;
  body?: { size?: number; data?: string };
  parts?: GmailPart[];
};
type GmailMessageList = {
  messages?: { id: string; threadId: string }[];
  nextPageToken?: string;
  resultSizeEstimate?: number;
};
type GmailMessage = {
  id: string;
  snippet?: string;
  internalDate?: string;
  payload?: {
    headers?: GmailHeader[];
    mimeType?: string;
    body?: { size?: number; data?: string };
    parts?: GmailPart[];
  };
};

// ─────────────────────────── Helpers: decoding / headers ────────────────────
function b64urlToUtf8(input: string): string {
  const normalized = input.replace(/-/g, "+").replace(/_/g, "/");
  try {
    return new TextDecoder().decode(
      Uint8Array.from(atob(normalized), (c) => c.charCodeAt(0)),
    );
  } catch {
    return "";
  }
}

function header(
  hdrs: GmailHeader[] | undefined,
  name: string,
): string | undefined {
  if (!hdrs) return undefined;
  const h = hdrs.find((x) => x.name.toLowerCase() === name.toLowerCase());
  return h?.value;
}

// ─────────────────────────── Helpers: Gmail REST ────────────────────────────
async function getAccessToken(): Promise<string> {
  const client_id = Deno.env.get("GMAIL_CLIENT_ID")!;
  const client_secret = Deno.env.get("GMAIL_CLIENT_SECRET")!;
  const refresh_token = Deno.env.get("GMAIL_REFRESH_TOKEN")!;
  const res = await fetch(GMAIL_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id,
      client_secret,
      refresh_token,
      grant_type: "refresh_token",
    }),
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`Gmail token exchange failed: ${res.status} ${t}`);
  }
  const json = await res.json();
  return json.access_token as string;
}

async function gmailListIds(
  accessToken: string,
  q: string,
  max = 25,
): Promise<string[]> {
  const url = new URL(GMAIL_LIST_URL);
  url.searchParams.set("q", q);
  url.searchParams.set("maxResults", `${max}`);
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`Gmail list failed: ${res.status} ${t}`);
  }
  const list = (await res.json()) as GmailMessageList;
  return (list.messages ?? []).map((m) => m.id);
}

async function gmailGet(accessToken: string, id: string): Promise<GmailMessage> {
  const url = `${GMAIL_MSG_URL}${id}?format=full`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`Gmail get failed: ${res.status} ${t}`);
  }
  return (await res.json()) as GmailMessage;
}

// OPTIONAL: mark as read so "is:unread" won’t keep returning the same emails
async function gmailMarkRead(accessToken: string, id: string): Promise<void> {
  const url = `${GMAIL_MODIFY_URL}${id}/modify`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ removeLabelIds: ["UNREAD"] }),
  });
  if (!res.ok) {
    const t = await res.text();
    console.error(`Gmail modify (mark read) failed: ${res.status} ${t}`);
  }
}

// ─────────────────────────── Helpers: OneSignal ─────────────────────────────
async function onesignalNotify(
  title: string,
  subtitle: string | undefined,
  body: string,
  data: Record<string, string>,
) {
  const app_id = Deno.env.get("ONESIGNAL_APP_ID")!;
  const api_key = Deno.env.get("ONESIGNAL_API_KEY")!;

  interface OneSignalPayload {
    app_id: string;
    included_segments: string[];
    headings: { en: string };
    contents: { en: string };
    data: Record<string, string>;
    ios_sound: string;
    priority: number;
    subtitle?: { en: string }; // <— added proper type
  }

  const payload: OneSignalPayload = {
    app_id,
    included_segments: ["All"],
    headings: { en: title },
    contents: { en: body },
    data,
    ios_sound: "default",
    priority: 10,
  };

  if (subtitle && subtitle.trim()) {
    payload.subtitle = { en: subtitle.trim() };
  }

  const res = await fetch("https://onesignal.com/api/v1/notifications", {
    method: "POST",
    headers: {
      Authorization: `Basic ${api_key}`,
      "Content-Type": "application/json; charset=utf-8",
    },
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    const t = await res.text();
    throw new Error(`OneSignal error: ${res.status} ${t}`);
  }
}

// ─────────────────────────── Helpers: DB (REST) ─────────────────────────────
async function upsertEmail(
  dbUrl: string,
  dbKey: string,
  row: {
    message_id: string;
    from_addr?: string;
    subject?: string;
    received_at?: string;
    snippet?: string;
    raw?: unknown;
    parsed?: unknown; // NEW: structured extraction
  },
) {
  const headers = {
    apikey: dbKey,
    Authorization: `Bearer ${dbKey}`,
    "Content-Type": "application/json",
  };

  // Insert email record (now includes `parsed`)
  const r1 = await fetch(`${dbUrl}/rest/v1/emails_ingested`, {
    method: "POST",
    headers,
    body: JSON.stringify(row),
  });
  if (!r1.ok) {
    const t = await r1.text();
    console.error(`emails_ingested insert failed: ${r1.status} ${t}`);
  }

  // Mark as seen
  const r2 = await fetch(`${dbUrl}/rest/v1/email_seen`, {
    method: "POST",
    headers,
    body: JSON.stringify({ message_id: row.message_id }),
  });
  if (!r2.ok) {
    const t = await r2.text();
    console.error(`email_seen insert failed: ${r2.status} ${t}`);
  }
}

async function isSeen(
  dbUrl: string,
  dbKey: string,
  messageId: string,
): Promise<boolean> {
  const res = await fetch(
    `${dbUrl}/rest/v1/email_seen?message_id=eq.${encodeURIComponent(messageId)}&select=message_id`,
    { headers: { apikey: dbKey, Authorization: `Bearer ${dbKey}` } },
  );
  if (!res.ok) {
    const t = await res.text();
    console.error(`email_seen check failed: ${res.status} ${t}`);
    return false;
  }
  const rows = await res.json();
  return Array.isArray(rows) && rows.length > 0;
}

// ─────────────────────────── Helpers: Parsing ───────────────────────────────
function firstMatch(re: RegExp, s: string): string | undefined {
  const m = re.exec(s);
  return m && m[1] ? m[1].trim() : undefined;
}

function extractGuest(text: string): string | undefined {
  const patterns: RegExp[] = [
    /Guest(?: Name)?:\s*([^\n,|]+)\b/i,
    /Reservation confirmed for\s+([^\n,|]+)\b/i,
    /Booking for\s+([^\n,|]+)\b/i,
    /Traveller:\s*([^\n,|]+)\b/i,
  ];
  for (const r of patterns) {
    const v = firstMatch(r, text);
    if (v) return v;
  }
  const near = /(?:reservation|booking)\s+(?:for|–|-)\s+([A-Za-z .'-]{2,})/i.exec(
    text,
  );
  return near?.[1]?.trim();
}

function extractCurrencyAmount(text: string): {
  currency?: string;
  amount?: number;
} {
  const re =
    /(₹|INR|Rs\.?|USD|\$|EUR|GBP)\s*([0-9]{1,3}(?:[, ]?[0-9]{3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)/i;
  const m = re.exec(text);
  if (!m) return {};
  const cur = m[1].toUpperCase().replace(/\.$/, "");
  const amt = Number(m[2].replace(/[ ,]/g, ""));
  return {
    currency: cur === "$" ? "USD" : cur === "RS" ? "INR" : cur,
    amount: isFinite(amt) ? amt : undefined,
  };
}

function normalizeDashes(s: string): string {
  return s.replace(/\u2013|\u2014/g, "-"); // en/em dash → hyphen
}

function extractDates(
  text: string,
  yearHint?: number,
): { check_in?: string; check_out?: string } {
  const t = normalizeDashes(text);

  const monthIndex = (m: string) => {
    const key = m.slice(0, 3).toLowerCase();
    return ["jan","feb","mar","apr","may","jun","jul","aug","sep","oct","nov","dec"]
      .indexOf(key) + 1;
  };

  const isoYmd = (y: number, m: number, d: number) =>
    new Date(Date.UTC(y, m - 1, d)).toISOString();

  const inferYear = (y?: number) => y ?? yearHint ?? (new Date()).getUTCFullYear();

  // A) "Mar 3–5, 2026" or "Mar 3-5, 2026"
  {
    const r = /\b([A-Za-z]{3,9})\s+(\d{1,2})\s*-\s*(\d{1,2}),\s*(\d{4})\b/i.exec(t);
    if (r) {
      const mon = monthIndex(r[1]);
      const d1 = Number(r[2]);
      const d2 = Number(r[3]);
      const y  = Number(r[4]);
      if (mon) {
        return { check_in: isoYmd(y, mon, d1), check_out: isoYmd(y, mon, d2) };
      }
    }
  }

  // B) "3–5 Mar 2026" or "3-5 March 2026" (year optional)
  {
    const r = /\b(\d{1,2})\s*-\s*(\d{1,2})\s+([A-Za-z]{3,9})(?:\s+(\d{4}))?\b/i.exec(t);
    if (r) {
      const d1 = Number(r[1]);
      const d2 = Number(r[2]);
      const mon = monthIndex(r[3]);
      const y = inferYear(r[4] ? Number(r[4]) : undefined);
      if (mon) {
        return { check_in: isoYmd(y, mon, d1), check_out: isoYmd(y, mon, d2) };
      }
    }
  }

  // C) "Mar 30 - Apr 2, 2026"
  {
    const r = /\b([A-Za-z]{3,9})\s+(\d{1,2})\s*-\s*([A-Za-z]{3,9})\s+(\d{1,2}),\s*(\d{4})\b/i.exec(t);
    if (r) {
      const m1 = monthIndex(r[1]);
      const d1 = Number(r[2]);
      const m2 = monthIndex(r[3]);
      const d2 = Number(r[4]);
      const y  = Number(r[5]);
      if (m1 && m2) {
        return { check_in: isoYmd(y, m1, d1), check_out: isoYmd(y, m2, d2) };
      }
    }
  }

  // D) "12 Oct 2025 to 15 Oct 2025"
  {
    const r = /\b([0-3]?\d)\s+([A-Za-z]{3,9})\s+(20\d{2}|19\d{2})\s+(?:to|-|until|through)\s+([0-3]?\d)\s+([A-Za-z]{3,9})\s+(20\d{2}|19\d{2})\b/i.exec(t);
    if (r) {
      const d1 = Number(r[1]); const m1 = monthIndex(r[2]); const y1 = Number(r[3]);
      const d2 = Number(r[4]); const m2 = monthIndex(r[5]); const y2 = Number(r[6]);
      if (m1 && m2) {
        return { check_in: isoYmd(y1, m1, d1), check_out: isoYmd(y2, m2, d2) };
      }
    }
  }

  // E) "dd/mm/yyyy - dd/mm/yyyy"
  {
    const r = /([0-3]?\d)\/([01]?\d)\/(20\d{2}|19\d{2})\s*-\s*([0-3]?\d)\/([01]?\d)\/(20\d{2}|19\d{2})/i.exec(t);
    if (r) {
      const d1 = Number(r[1]), m1 = Number(r[2]), y1 = Number(r[3]);
      const d2 = Number(r[4]), m2 = Number(r[5]), y2 = Number(r[6]);
      return { check_in: isoYmd(y1, m1, d1), check_out: isoYmd(y2, m2, d2) };
    }
  }

  // F) "Check-in: 1 Mar 2026" / "Check-out: 3 Mar 2026"
  {
    const cinTxt = /Check-?in[:\s]+([^\n]+)/i.exec(t)?.[1];
    const coutTxt = /Check-?out[:\s]+([^\n]+)/i.exec(t)?.[1];
    const p = (s?: string) => {
      if (!s) return undefined;
      const dt = Date.parse(s);
      return isNaN(dt) ? undefined : new Date(dt).toISOString();
    };
    const ci = p(cinTxt);
    const co = p(coutTxt);
    if (ci || co) return { check_in: ci, check_out: co };
  }

  // G) Bare ISO pair
  {
    const all = [...t.matchAll(/\b(\d{4}-\d{2}-\d{2})\b/g)].map(m => m[1]);
    if (all.length >= 2) {
      return { check_in: new Date(all[0]).toISOString(), check_out: new Date(all[1]).toISOString() };
    }
  }

  // H) "Mar 3-5" WITHOUT year → use hint
  {
    const r = /\b([A-Za-z]{3,9})\s+(\d{1,2})\s*-\s*(\d{1,2})\b/i.exec(t);
    if (r) {
      const m = monthIndex(r[1]);
      const d1 = Number(r[2]);
      const d2 = Number(r[3]);
      const y = inferYear();
      if (m) {
        return { check_in: isoYmd(y, m, d1), check_out: isoYmd(y, m, d2) };
      }
    }
  }

  return {};
}

function detectSource(fromHeader: string): "airbnb" | "booking.com" | "unknown" {
  const f = fromHeader.toLowerCase();
  if (f.includes("airbnb")) return "airbnb";
  if (f.includes("booking.com")) return "booking.com";
  return "unknown";
}



// ─────────────────────────── HTTP entry ─────────────────────────────────────
Deno.serve(async (req) => {
  try {
    // Optional shared-secret for scheduler
    const cronSecret = Deno.env.get("CRON_SECRET");
    if (cronSecret) {
      const h = req.headers.get("x-cron-secret");
      if (h !== cronSecret) {
        return new Response(JSON.stringify({ ok: false, error: "unauthorized" }), {
          status: 401,
          headers: { "content-type": "application/json" },
        });
      }
    }

    // 1) Gmail access token
    const access = await getAccessToken();

    // 2) Search query (Airbnb / Booking.com, unread, last 2 days)
    const body = await req.json().catch(() => ({}));
    const q = typeof body.q === 'string' && body.q.trim()
      ? body.q.trim()
      : "from:(airbnb.com OR booking.com) newer_than:2d is:unread";
    const ids = await gmailListIds(access, q, 20);

    const dbUrl = Deno.env.get("SUPABASE_URL")!;
    const dbKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    let processedCount = 0;

    for (const id of ids) {
      // dedupe
      if (await isSeen(dbUrl, dbKey, id)) continue;

      const msg = await gmailGet(access, id);
      const hdrs = msg.payload?.headers ?? [];
      const from = header(hdrs, "From") ?? "";
      const subject = header(hdrs, "Subject") ?? "(no subject)";
      const dateStr = header(hdrs, "Date");
      const receivedAt = dateStr ? new Date(dateStr).toISOString() : undefined;
      const snippet = msg.snippet ?? "";

      // drill into text/plain parts if present
      let textBody = "";
      const walk = (node?: GmailPart) => {
        if (!node) return;
        if (node.mimeType === "text/plain" && node.body?.data) {
          textBody += b64urlToUtf8(node.body.data) + "\n";
        }
        if (Array.isArray(node.parts)) node.parts.forEach(walk);
      };
      walk(msg.payload as unknown as GmailPart);

      const readable = (textBody && textBody.trim().length > 0)
        ? textBody.trim()
        : snippet;

      // ── Parse structured info
      const combined = [subject, readable].filter(Boolean).join("\n");
      const guest = extractGuest(combined) ?? "";
      const inferredYear = receivedAt ? new Date(receivedAt).getUTCFullYear() : undefined;
      const dates = extractDates(combined, inferredYear);
      const money = extractCurrencyAmount(combined);
      const source = detectSource(from);

      // ── Classify status (confirmed / enquiry / unknown)
      const lc = combined.toLowerCase();
      let status: "confirmed" | "enquiry" | "unknown" = "unknown";

      // Strong "confirmed" signals
      if (
        lc.includes("new booking confirmed") ||
        lc.includes("reservation confirmed") ||
        lc.includes("booking confirmed") ||
        /confirmation code\s*[A-Z0-9\-]{5,}/i.test(combined)
      ) {
        status = "confirmed";
      } else if (
        // Enquiry / inquiry signals
        lc.includes("respond to") && (lc.includes("inquiry") || lc.includes("enquiry")) ||
        lc.includes("pre-approve / decline") ||
        lc.includes("you have 24 hours to respond") ||
        /\binquiry\b/i.test(combined) || /\benquiry\b/i.test(combined)
      ) {
        status = "enquiry";
      }

      const parsed = {
        source,
        guest_name: guest || undefined,
        check_in: dates.check_in,
        check_out: dates.check_out,
        amount: money.amount,
        currency: money.currency,
        status,
      };

      // 3) Store + mark seen
      await upsertEmail(dbUrl, dbKey, {
        message_id: msg.id,
        from_addr: from,
        subject,
        received_at: receivedAt,
        snippet: readable.slice(0, 240),
        raw: { headers: hdrs, snippet, id: msg.id },
        parsed, // keep parsed payload
      });

      // 4) Push ONLY for confirmed / enquiry
      // 4) Push ONLY for confirmed / enquiry
      if (status === "confirmed" || status === "enquiry") {
        const fmt = (iso?: string) => {
          if (!iso) return "—";
          const d = new Date(iso);
          try {
            return d.toLocaleDateString("en-US", {
              month: "short",
              day: "numeric",
              year: "numeric",
            });
          } catch {
            const y = d.getUTCFullYear();
            const m = String(d.getUTCMonth() + 1).padStart(2, "0");
            const day = String(d.getUTCDate()).padStart(2, "0");
            return `${y}-${m}-${day}`;
          }
        };

        const title = status === "confirmed" ? "New Confirmation" : "New Inquiry";
        const subtitle = (guest && guest.trim()) ? guest.trim() : "(Unknown guest)";
        const body =
          (status === "confirmed"
            ? `New confirmation received for ${fmt(dates.check_in)} to ${fmt(dates.check_out)}`
            : `New inquiry received for ${fmt(dates.check_in)} to ${fmt(dates.check_out)}`);

        await onesignalNotify(
          title,
          subtitle,
          body,
          { route: "check_email", message_id: msg.id, status },
        );
      }

      // 5) OPTIONAL: mark as read
      await gmailMarkRead(access, id);

      processedCount++;
    }

    return new Response(JSON.stringify({ ok: true, processed: processedCount }), {
      headers: { "content-type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e) }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }
});
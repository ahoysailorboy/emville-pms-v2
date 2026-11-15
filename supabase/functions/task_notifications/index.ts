import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
// Any authenticated, authorized app user may wake the durable delivery queue.
// The database scheduler uses its Vault secret to retry without app use.
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-task-secret",
};
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const url = Deno.env.get("SUPABASE_URL")!;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const db = createClient(url, key);
  const suppliedSecret = req.headers.get("x-task-secret");
  let isCron = false;
  if (suppliedSecret) {
    const { data } = await db.rpc("validate_task_scheduler_secret", {
      p_secret: suppliedSecret,
    });
    isCron = data === true;
  }
  if (!isCron) {
    const token = req.headers.get("Authorization")?.replace(/^Bearer /i, "") ??
      "";
    const { data: { user } } = await db.auth.getUser(token);
    if (!user) {
      return new Response("Unauthorized", { status: 401, headers: cors });
    }
    const { data: profile } = await db.from("users").select("is_authorized").eq(
      "uid",
      user.id,
    ).single();
    if (!profile?.is_authorized) {
      return new Response("Forbidden", { status: 403, headers: cors });
    }
  }
  const api = Deno.env.get("ONESIGNAL_API_KEY");
  const app = Deno.env.get("ONESIGNAL_APP_ID");
  if (!api || !app) {
    return new Response("Push configuration missing", {
      status: 503,
      headers: cors,
    });
  }
  const { data: rows, error } = await db.from("task_notification_queue").select(
    "*",
  ).is("delivered_at", null).lte("next_attempt_at", new Date().toISOString())
    .gte("created_at", new Date(Date.now() - 7 * 86400000).toISOString()).order(
      "created_at",
    ).limit(50);
  if (error) {
    return new Response("Queue unavailable", { status: 500, headers: cors });
  }
  let sent = 0;
  for (const row of rows ?? []) {
    try {
      const { data: recipient } = await db.from("users").select("is_authorized")
        .eq("uid", row.recipient).single();
      if (!recipient?.is_authorized) {
        await db.from("task_notification_queue").update({
          delivered_at: new Date().toISOString(),
        }).eq("id", row.id);
        continue;
      }
      const retryAt = new Date(
        Date.now() +
          Math.min(3600, 60 * Math.pow(2, Math.min(row.attempts, 6))) * 1000,
      ).toISOString();
      await db.from("task_notification_queue").update({
        attempts: row.attempts + 1,
        next_attempt_at: retryAt,
      }).eq("id", row.id);
      const res = await fetch("https://api.onesignal.com/notifications", {
        method: "POST",
        headers: {
          Authorization: `Key ${api}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          app_id: app,
          target_channel: "push",
          include_aliases: { external_id: [row.recipient] },
          headings: { en: row.title },
          contents: { en: row.message },
          idempotency_key: row.id,
          data: {
            route: row.route ??
              (row.reminder_id ? "work_reminder" : "maintenance_task"),
            reminder_id: row.reminder_id,
            job_seq: row.job_seq,
          },
          ios_sound: "default",
        }),
      });
      const response = await res.json();
      // No subscribed device: retain the queue item for a later login/retry.
      if (res.ok && response.id) {
        await db.from("task_notification_queue").update({
          delivered_at: new Date().toISOString(),
          attempts: row.attempts + 1,
        }).eq("id", row.id);
        sent++;
      }
    } catch {
      /* Keep pending; stable idempotency key prevents duplicate delivery. */
    }
  }
  return Response.json({ sent }, { headers: cors });
});

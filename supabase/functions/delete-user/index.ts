// supabase/functions/delete-user/index.ts
// Deno runtime Edge Function

import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (status: number, data: unknown) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });

// Supabase client bound to the caller's JWT (for role check)
const clientForRequest = (req: Request) =>
  createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });

// Service-role client for privileged operations
const admin = createClient(SUPABASE_URL, SERVICE_KEY);

Deno.serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return json(405, { error: "Method not allowed" });
    }

    const { uid } = await req.json().catch(() => ({}));
    if (!uid || typeof uid !== "string") {
      return json(400, { error: "Missing 'uid' (string) in body" });
    }

    // 1) Who is calling? Must be owner/admin.
    const authed = clientForRequest(req);
    const { data: me } = await authed.auth.getUser();
    if (!me?.user) {
      return json(401, { error: "Unauthorized" });
    }

    const myUid = me.user.id;
    const { data: myRow, error: meErr } = await admin
      .from("users")
      .select("role")
      .eq("uid", myUid)
      .maybeSingle();

    if (meErr) return json(500, { error: `Role check failed: ${meErr.message}` });

    const myRole = (myRow?.role as string) ?? "user";
    const isAdmin = myRole === "owner" || myRole === "admin";
    if (!isAdmin) {
      return json(403, { error: "Only owner/admin can delete users" });
    }

    // Never allow deleting the owner (extra guard even if UI hides it)
    const { data: targetRow, error: tErr } = await admin
      .from("users")
      .select("role, email")
      .eq("uid", uid)
      .maybeSingle();

    if (tErr) return json(500, { error: `Lookup target failed: ${tErr.message}` });
    if (!targetRow) return json(404, { error: "Target user not found in public.users" });
    if ((targetRow.role as string) === "owner") {
      return json(403, { error: "Owner cannot be deleted" });
    }

    // 2) SOFT DELETE in auth (sets deleted_at)
    // Preferred: supabase-js Admin API with shouldSoftDelete flag
    let softDeleted = false;
    try {
      // @ts-ignore - some older type defs may not include the option yet
      const { error: delErr } = await admin.auth.admin.deleteUser(uid, {
        shouldSoftDelete: true,
      });
      if (delErr) throw delErr;
      softDeleted = true;
    } catch (e) {
      // Fallback to raw HTTP if SDK flag is missing in your runtime
      try {
        const resp = await fetch(
          `${SUPABASE_URL}/auth/v1/admin/users/${uid}?should_soft_delete=true`,
          {
            method: "DELETE",
            headers: {
              apikey: SERVICE_KEY,
              Authorization: `Bearer ${SERVICE_KEY}`,
            },
          },
        );
        if (!resp.ok) {
          const txt = await resp.text();
          throw new Error(`HTTP ${resp.status}: ${txt}`);
        }
        softDeleted = true;
      } catch (e2) {
        return json(500, {
          error: `Soft delete failed: ${(e as Error).message} / ${(e2 as Error).message}`,
        });
      }
    }

    // 3) Flip approved + is_authorized to FALSE in public.users
    const { error: updErr } = await admin
      .from("users")
      .update({ approved: false, is_authorized: false })
      .eq("uid", uid);

    if (updErr) return json(500, { error: `Flag update failed: ${updErr.message}` });

    // 4) Remove the row from public.users
    const { error: delRowErr } = await admin.from("users").delete().eq("uid", uid);
    if (delRowErr) return json(500, { error: `Public row delete failed: ${delRowErr.message}` });

    return json(200, { ok: true, uid, softDeleted });
  } catch (e) {
    return json(500, { error: (e as Error).message });
  }
});
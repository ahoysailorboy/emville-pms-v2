// @ts-nocheck
/// <reference lib="deno.ns" />
// supabase/functions/send-signup-otp/index.ts
// Disabled placeholder so callers get a clear response.
// You can safely deploy this; it does not send anything.

//import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { serve } from "npm:@supabase/functions-js";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = (origin: string | null) => ({
  "Access-Control-Allow-Origin": origin ?? "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
});

Deno.serve((req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors(req.headers.get("origin")) });
  }

  // Always return 410 Gone to signal this endpoint is intentionally disabled
  const body = JSON.stringify({
    error: "send-signup-otp endpoint is disabled. This project no longer uses an Edge Function for OTP.",
  });

  return new Response(body, { status: 410, headers: cors(req.headers.get("origin")) });
});
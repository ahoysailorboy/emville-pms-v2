import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { getDocumentProxy } from "npm:unpdf@1.4.0";
import { parseFederalCells, type PdfCell } from "./parser.ts";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const db = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const token = req.headers.get("Authorization")?.replace(/^Bearer /i, "") ??
      "";
    const { data: { user } } = await db.auth.getUser(token);
    if (!user) {
      return Response.json({ error: "Sign in first" }, {
        status: 401,
        headers: cors,
      });
    }
    const { data: profile } = await db.from("users").select(
      "role,is_authorized",
    ).eq("uid", user.id).single();
    if (!profile?.is_authorized || !["owner", "admin"].includes(profile.role)) {
      return Response.json({
        error: "Only admins and owners can read bank statements",
      }, { status: 403, headers: cors });
    }
    const { path } = await req.json();
    if (
      typeof path !== "string" ||
      !new RegExp(`^${user.id}/[0-9a-f-]{36}\\.pdf$`).test(path)
    ) throw new Error("Invalid statement file");
    const { data: file, error } = await db.storage.from("bank-statements")
      .download(path);
    if (error || !file) throw new Error("Cannot read uploaded PDF");
    if (file.size > 10 * 1024 * 1024) {
      throw new Error("PDF must be under 10 MB");
    }
    const pdf = await getDocumentProxy(
      new Uint8Array(await file.arrayBuffer()),
      { maxImageSize: 16777216, isEvalSupported: false },
    );
    try {
      if (pdf.numPages > 40) {
        throw new Error("Use a monthly statement of 40 pages or fewer");
      }
      const cells: PdfCell[] = [];
      for (let n = 1; n <= pdf.numPages; n++) {
        const page = await pdf.getPage(n);
        const content = await page.getTextContent();
        for (const item of content.items) {
          if ("str" in item && item.str.trim()) {
            cells.push({
              text: item.str.trim(),
              x: item.transform[4],
              y: item.transform[5],
              page: n,
            });
          }
        }
      }
      if (cells.length > 100000) {
        throw new Error(
          "PDF contains too much text. Use a smaller monthly statement.",
        );
      }
      const result = parseFederalCells(cells);
      if (!cells.length) {
        result.warnings.push(
          "This PDF appears scanned. Enter the transactions manually from the original statement.",
        );
      }
      return Response.json({ ...result, pages: pdf.numPages }, {
        headers: { ...cors, "Cache-Control": "no-store" },
      });
    } finally {
      await pdf.destroy();
    }
  } catch (e) {
    return Response.json({
      error:
        e instanceof Error && /PDF|statement|monthly|Invalid/.test(e.message)
          ? e.message
          : "Could not read this PDF. Check it is a readable, unprotected bank statement.",
    }, { status: 400, headers: cors });
  }
});

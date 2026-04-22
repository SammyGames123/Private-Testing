import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type ReportRow = {
  id: string;
  reporter_id: string;
  target_user_id: string | null;
  target_video_id: string | null;
  target_comment_id: string | null;
  target_live_stream_id: string | null;
  category: string;
  note: string | null;
  status: string;
  created_at: string;
};

type ProfileRow = {
  username: string | null;
  display_name: string | null;
  email: string | null;
};

serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  const authHeader = request.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing Authorization header." }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  const moderationEmailTo = Deno.env.get("MODERATION_EMAIL_TO");
  const moderationEmailFrom = Deno.env.get("MODERATION_EMAIL_FROM") ?? "Spilltop Safety <onboarding@resend.dev>";

  if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) {
    return jsonResponse({ error: "Supabase function environment is incomplete." }, 500);
  }

  if (!resendApiKey || !moderationEmailTo) {
    return jsonResponse({
      ok: false,
      error: "Report stored, but moderation email is not configured. Set RESEND_API_KEY and MODERATION_EMAIL_TO.",
    }, 200);
  }

  let body: { report_id?: string } = {};
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "Request body must be valid JSON." }, 400);
  }

  const reportId = body.report_id?.trim();
  if (!reportId) {
    return jsonResponse({ error: "report_id is required." }, 400);
  }

  const userClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) {
    return jsonResponse({ error: "You need to be signed in." }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: report, error: reportError } = await admin
    .from("content_reports")
    .select("*")
    .eq("id", reportId)
    .eq("reporter_id", user.id.toLowerCase())
    .maybeSingle();

  if (reportError) {
    return jsonResponse({ error: reportError.message }, 500);
  }
  if (!report) {
    return jsonResponse({ error: "Report not found." }, 404);
  }

  const typedReport = report as ReportRow;
  const { data: reporterProfile } = await admin
    .from("profiles")
    .select("username, display_name, email")
    .eq("id", typedReport.reporter_id)
    .maybeSingle();

  const reporter = reporterProfile as ProfileRow | null;
  const subject = `Spilltop safety report: ${typedReport.category}`;
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${resendApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: moderationEmailFrom,
      to: moderationEmailTo,
      subject,
      text: buildEmailText(typedReport, reporter),
    }),
  });

  if (!response.ok) {
    return jsonResponse({ ok: false, error: await response.text() }, 200);
  }

  return jsonResponse({ ok: true });
});

function buildEmailText(report: ReportRow, reporter: ProfileRow | null): string {
  const reporterName = reporter?.display_name || reporter?.username || reporter?.email || report.reporter_id;
  const targetLines = [
    ["Target user", report.target_user_id],
    ["Target post", report.target_video_id],
    ["Target comment", report.target_comment_id],
    ["Target live stream", report.target_live_stream_id],
  ]
    .filter(([, value]) => value)
    .map(([label, value]) => `${label}: ${value}`)
    .join("\n");

  return [
    "A new Spilltop report was submitted.",
    "",
    `Report ID: ${report.id}`,
    `Created: ${report.created_at}`,
    `Category: ${report.category}`,
    `Reporter: ${reporterName} (${report.reporter_id})`,
    targetLines,
    "",
    "Note:",
    report.note || "(none)",
    "",
    "Open Supabase > Table Editor > content_reports to review and action this report.",
  ].filter(Boolean).join("\n");
}

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

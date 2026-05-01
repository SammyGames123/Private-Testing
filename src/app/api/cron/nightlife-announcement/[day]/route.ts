import { hasAdminAuditRecord, recordAdminAudit } from "@/lib/admin-audit";
import { broadcastAnnouncement } from "@/lib/push-broadcast";
import {
  isNightKey,
  scheduledAnnouncementFor,
} from "@/lib/scheduled-nightlife-announcements";
import { createAdminClient } from "@/lib/supabase/admin";
import { NextRequest, NextResponse } from "next/server";

export const dynamic = "force-dynamic";

function unauthorizedResponse() {
  return NextResponse.json({ error: "Unauthorized." }, { status: 401 });
}

function verifyCronSecret(request: NextRequest) {
  const expectedSecret = process.env.CRON_SECRET;
  if (!expectedSecret) {
    return NextResponse.json(
      { error: "CRON_SECRET is not configured." },
      { status: 500 },
    );
  }

  const authorization = request.headers.get("authorization");
  if (authorization !== `Bearer ${expectedSecret}`) {
    return unauthorizedResponse();
  }

  return null;
}

export async function GET(
  request: NextRequest,
  context: { params: Promise<{ day: string }> },
) {
  const authError = verifyCronSecret(request);
  if (authError) {
    return authError;
  }

  const { day } = await context.params;
  if (!isNightKey(day)) {
    return NextResponse.json({ error: "Unknown schedule." }, { status: 404 });
  }

  const admin = createAdminClient();
  const message = scheduledAnnouncementFor(day);
  const alreadySent = await hasAdminAuditRecord(
    admin,
    "push.scheduled_announcement",
    "scheduled_announcement",
    message.dispatchKey,
  );

  if (alreadySent) {
    return NextResponse.json({
      skipped: true,
      reason: "already_sent",
      dispatchKey: message.dispatchKey,
    });
  }

  const result = await broadcastAnnouncement(admin, {
    title: message.title,
    body: message.body,
    data: {
      scheduled_day: message.day,
      week_index: message.weekIndex + 1,
      dispatch_key: message.dispatchKey,
    },
  });

  await recordAdminAudit(
    admin,
    null,
    "push.scheduled_announcement",
    "scheduled_announcement",
    message.dispatchKey,
    {
      scheduled_day: message.day,
      week_index: message.weekIndex + 1,
      title: message.title,
      body: message.body,
      ...result,
    },
  );

  return NextResponse.json({
    ok: true,
    ...result,
    scheduledDay: message.day,
    weekIndex: message.weekIndex + 1,
    dispatchKey: message.dispatchKey,
  });
}

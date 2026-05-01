import type { SupabaseClient } from "@supabase/supabase-js";

type BroadcastAnnouncementInput = {
  title: string;
  body: string;
  data?: Record<string, unknown>;
};

export type BroadcastAnnouncementResult = {
  recipientsConsidered: number;
  deliveredUsers: number;
  skippedUsers: number;
  failedUsers: number;
};

function functionsBaseUrl() {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!supabaseUrl) {
    throw new Error("Missing NEXT_PUBLIC_SUPABASE_URL.");
  }

  const url = new URL(supabaseUrl);
  const projectRef = url.hostname.split(".")[0];
  return `https://${projectRef}.functions.supabase.co`;
}

function requirePushWebhookSecret() {
  const secret = process.env.PUSH_WEBHOOK_SECRET;
  if (!secret) {
    throw new Error("Broadcast notifications need PUSH_WEBHOOK_SECRET configured.");
  }
  return secret;
}

function chunk<T>(items: T[], size: number) {
  const result: T[][] = [];
  for (let index = 0; index < items.length; index += size) {
    result.push(items.slice(index, index + size));
  }
  return result;
}

export async function broadcastAnnouncement(
  admin: SupabaseClient,
  input: BroadcastAnnouncementInput,
): Promise<BroadcastAnnouncementResult> {
  const { title, body, data = {} } = input;

  const { data: tokenRows, error: tokenError } = await admin
    .from("device_push_tokens")
    .select("user_id");

  if (tokenError) {
    throw new Error(tokenError.message);
  }

  const userIds = Array.from(
    new Set(
      ((tokenRows ?? []) as Array<{ user_id: string | null }>)
        .map((row) => row.user_id?.toLowerCase())
        .filter((value): value is string => Boolean(value)),
    ),
  );

  if (!userIds.length) {
    throw new Error("No registered push recipients were found.");
  }

  const webhookSecret = requirePushWebhookSecret();
  const endpoint = `${functionsBaseUrl()}/send-push`;
  let deliveredUsers = 0;
  let skippedUsers = 0;
  let failedUsers = 0;

  for (const batch of chunk(userIds, 25)) {
    const results = await Promise.allSettled(
      batch.map(async (userId) => {
        const response = await fetch(endpoint, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Webhook-Secret": webhookSecret,
          },
          body: JSON.stringify({
            user_id: userId,
            category: "announcements",
            title,
            body,
            data: {
              category: "announcements",
              ...data,
            },
          }),
        });

        let payload: Record<string, unknown> | null = null;
        try {
          payload = (await response.json()) as Record<string, unknown>;
        } catch {
          payload = null;
        }

        if (!response.ok) {
          throw new Error(
            typeof payload?.error === "string" && payload.error.length > 0
              ? payload.error
              : `Push request failed with status ${response.status}.`,
          );
        }

        return payload;
      }),
    );

    for (const result of results) {
      if (result.status !== "fulfilled") {
        failedUsers += 1;
        continue;
      }

      const payload = result.value;
      if (payload && payload.skipped === true) {
        skippedUsers += 1;
        continue;
      }

      if (payload && typeof payload.sent === "number" && payload.sent > 0) {
        deliveredUsers += 1;
      } else {
        skippedUsers += 1;
      }
    }
  }

  return {
    recipientsConsidered: userIds.length,
    deliveredUsers,
    skippedUsers,
    failedUsers,
  };
}

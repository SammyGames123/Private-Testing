"use server";

import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

function getSafeRedirectPath(value: FormDataEntryValue | null) {
  const path =
    typeof value === "string" && value.startsWith("/") ? value : "/messages";
  return path;
}

export async function startConversation(formData: FormData) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/auth/login");
  }

  const targetUserId = String(formData.get("target_user_id") ?? "");
  const redirectTo = getSafeRedirectPath(formData.get("redirect_to"));

  if (!targetUserId || targetUserId === user.id) {
    redirect(redirectTo);
  }

  const { data: existingParticipants } = await supabase
    .from("thread_participants")
    .select("thread_id, user_id")
    .in("user_id", [user.id, targetUserId]);

  const grouped = new Map<string, Set<string>>();
  (existingParticipants ?? []).forEach((row) => {
    const entry = grouped.get(row.thread_id) ?? new Set<string>();
    entry.add(row.user_id);
    grouped.set(row.thread_id, entry);
  });

  const existingThreadId = [...grouped.entries()].find(([, users]) => {
    return users.has(user.id) && users.has(targetUserId) && users.size === 2;
  })?.[0];

  if (!existingThreadId) {
    const { data: thread, error: threadError } = await supabase
      .from("message_threads")
      .insert({ created_by: user.id })
      .select("id")
      .single<{ id: string }>();

    if (threadError || !thread) {
      redirect("/messages");
    }

    await supabase.from("thread_participants").insert([
      { thread_id: thread.id, user_id: user.id },
      { thread_id: thread.id, user_id: targetUserId },
    ]);
  }

  revalidatePath("/messages");
  redirect("/messages");
}

export async function sendMessage(formData: FormData) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/auth/login");
  }

  const threadId = String(formData.get("thread_id") ?? "");
  const body = String(formData.get("body") ?? "").trim();
  const redirectTo = getSafeRedirectPath(formData.get("redirect_to"));

  if (!threadId || !body) {
    redirect(redirectTo);
  }

  await supabase.from("messages").insert({
    thread_id: threadId,
    sender_id: user.id,
    body,
  });

  revalidatePath("/messages");
  redirect(redirectTo);
}

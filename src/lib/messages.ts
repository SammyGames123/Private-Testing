import { createClient } from "@/lib/supabase/server";

export type MessagePreview = {
  id: string;
  body: string;
  created_at: string;
  sender_id: string;
};

export type ThreadPreview = {
  id: string;
  otherUserId: string;
  otherUserName: string;
  otherUserHandle: string;
  latestMessage: string;
  latestMessageAt: string;
};

export type ConversationMessage = {
  id: string;
  body: string;
  created_at: string;
  senderId: string;
  senderHandle: string;
};

function formatTimeAgo(dateString: string) {
  const diffSeconds = Math.max(
    0,
    Math.floor((Date.now() - new Date(dateString).getTime()) / 1000),
  );

  if (diffSeconds >= 86400) {
    return `${Math.floor(diffSeconds / 86400)}d ago`;
  }
  if (diffSeconds >= 3600) {
    return `${Math.floor(diffSeconds / 3600)}h ago`;
  }
  if (diffSeconds >= 60) {
    return `${Math.floor(diffSeconds / 60)}m ago`;
  }
  return "just now";
}

function profileFromRelation<T>(value: T | T[] | null) {
  if (!value) return null;
  return Array.isArray(value) ? (value[0] ?? null) : value;
}

export async function getInboxData() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return { user: null, threads: [], creators: [], activeThread: null };
  }

  const [{ data: profileList }, { data: participantRows }] = await Promise.all([
    supabase
      .from("profiles")
      .select("id, username, display_name, bio")
      .neq("id", user.id)
      .limit(20),
    supabase
      .from("thread_participants")
      .select("thread_id, user_id")
      .eq("user_id", user.id),
  ]);

  const threadIds = [...new Set((participantRows ?? []).map((row) => row.thread_id))];

  let threads: ThreadPreview[] = [];
  let activeThread:
    | {
        id: string;
        otherUserId: string;
        otherUserName: string;
        otherUserHandle: string;
        messages: ConversationMessage[];
      }
    | null = null;

  if (threadIds.length > 0) {
    const [{ data: allParticipants }, { data: allMessages }] = await Promise.all([
      supabase
        .from("thread_participants")
        .select("thread_id, user_id, profiles:user_id(username, display_name)")
        .in("thread_id", threadIds),
      supabase
        .from("messages")
        .select("id, thread_id, sender_id, body, created_at")
        .in("thread_id", threadIds)
        .order("created_at", { ascending: true }),
    ]);

    threads = threadIds
      .map((threadId) => {
        const threadParticipants =
          allParticipants?.filter((row) => row.thread_id === threadId) ?? [];
        const otherParticipant = threadParticipants.find((row) => row.user_id !== user.id);
        if (!otherParticipant) return null;

        const otherProfile = profileFromRelation(otherParticipant.profiles) as
          | { username: string | null; display_name: string | null }
          | null;
        const messages = allMessages?.filter((row) => row.thread_id === threadId) ?? [];
        const latest = messages[messages.length - 1];

        return {
          id: threadId,
          otherUserId: otherParticipant.user_id,
          otherUserName:
            otherProfile?.display_name ?? otherProfile?.username ?? "Creator",
          otherUserHandle: `@${otherProfile?.username ?? "creator"}`,
          latestMessage: latest?.body ?? "No messages yet.",
          latestMessageAt: latest?.created_at ?? new Date().toISOString(),
        };
      })
      .filter((thread): thread is ThreadPreview => Boolean(thread))
      .sort(
        (a, b) =>
          new Date(b.latestMessageAt).getTime() -
          new Date(a.latestMessageAt).getTime(),
      );

    const firstThread = threads[0];
    if (firstThread) {
      const selectedParticipants =
        allParticipants?.filter((row) => row.thread_id === firstThread.id) ?? [];
      const otherParticipant = selectedParticipants.find((row) => row.user_id !== user.id);
      const otherProfile = otherParticipant
        ? (profileFromRelation(otherParticipant.profiles) as
            | { username: string | null; display_name: string | null }
            | null)
        : null;
      const selectedMessages =
        allMessages?.filter((row) => row.thread_id === firstThread.id) ?? [];

      activeThread = {
        id: firstThread.id,
        otherUserId: firstThread.otherUserId,
        otherUserName:
          otherProfile?.display_name ?? otherProfile?.username ?? "Creator",
        otherUserHandle: `@${otherProfile?.username ?? "creator"}`,
        messages: selectedMessages.map((message) => ({
          id: message.id,
          body: message.body,
          created_at: message.created_at,
          senderId: message.sender_id,
          senderHandle:
            message.sender_id === user.id
              ? "@you"
              : `@${otherProfile?.username ?? "creator"}`,
        })),
      };
    }
  }

  return {
    user,
    threads: threads.map((thread) => ({
      ...thread,
      latestMessageAt: formatTimeAgo(thread.latestMessageAt),
    })),
    creators:
      profileList?.map((profile) => ({
        id: profile.id,
        name: profile.display_name ?? profile.username ?? "Creator",
        handle: `@${profile.username ?? "creator"}`,
        bio: profile.bio ?? "No bio yet.",
      })) ?? [],
    activeThread,
  };
}

import Link from "next/link";
import { redirect } from "next/navigation";
import { getInboxData } from "@/lib/messages";
import { sendMessage, startConversation } from "./actions";

export default async function MessagesPage() {
  const { user, threads, creators, activeThread } = await getInboxData();

  if (!user) {
    redirect("/auth/login");
  }

  return (
    <main className="min-h-screen bg-[linear-gradient(135deg,_#f8f1e7_0%,_#efe4d5_100%)] px-4 py-8 text-[var(--ink)]">
      <div className="mx-auto max-w-7xl space-y-6">
        <section className="rounded-[32px] border border-black/10 bg-white/78 p-6 shadow-[0_24px_70px_rgba(74,49,29,0.12)]">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="eyebrow">Inbox</p>
              <h1 className="text-5xl font-semibold tracking-[-0.06em]">
                Direct messages
              </h1>
              <p className="mt-4 max-w-2xl text-base leading-7 text-[var(--muted)]">
                Start a conversation with another creator and send messages in a
                real Supabase-backed thread.
              </p>
            </div>

            <Link
              className="rounded-2xl border border-black/10 bg-white px-4 py-3 font-semibold"
              href="/dashboard"
            >
              Back to dashboard
            </Link>
          </div>
        </section>

        <section className="grid gap-6 xl:grid-cols-[320px_minmax(0,1fr)_320px]">
          <aside className="rounded-[32px] border border-black/10 bg-white/82 p-6 shadow-[0_24px_70px_rgba(74,49,29,0.12)]">
            <p className="eyebrow">Threads</p>
            <div className="mt-4 space-y-3">
              {threads.length > 0 ? (
                threads.map((thread) => (
                  <article
                    className="rounded-[20px] border border-black/8 bg-white/75 p-4"
                    key={thread.id}
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <strong className="block text-base text-[var(--ink)]">
                          {thread.otherUserName}
                        </strong>
                        <p className="mt-1 text-sm text-[var(--muted)]">
                          {thread.otherUserHandle}
                        </p>
                      </div>
                      <span className="text-xs text-[var(--muted)]">
                        {thread.latestMessageAt}
                      </span>
                    </div>
                    <p className="mt-3 text-sm leading-6 text-[var(--muted)]">
                      {thread.latestMessage}
                    </p>
                  </article>
                ))
              ) : (
                <p className="text-sm leading-7 text-[var(--muted)]">
                  No conversations yet. Start one from the creator list.
                </p>
              )}
            </div>
          </aside>

          <section className="rounded-[32px] border border-black/10 bg-white/82 p-6 shadow-[0_24px_70px_rgba(74,49,29,0.12)]">
            {activeThread ? (
              <>
                <div className="border-b border-black/8 pb-4">
                  <p className="eyebrow">Active conversation</p>
                  <h2 className="text-3xl font-semibold tracking-[-0.05em]">
                    {activeThread.otherUserName}
                  </h2>
                  <p className="mt-2 text-sm text-[var(--muted)]">
                    {activeThread.otherUserHandle}
                  </p>
                </div>

                <div className="mt-4 grid gap-3">
                  {activeThread.messages.map((message) => (
                    <article
                      className="rounded-[20px] border border-black/8 bg-white/75 p-4"
                      key={message.id}
                    >
                      <div className="flex items-start justify-between gap-3">
                        <strong className="text-sm text-[var(--ink)]">
                          {message.senderHandle}
                        </strong>
                        <span className="text-xs text-[var(--muted)]">
                          {new Date(message.created_at).toLocaleString()}
                        </span>
                      </div>
                      <p className="mt-2 text-sm leading-6 text-[var(--muted)]">
                        {message.body}
                      </p>
                    </article>
                  ))}
                </div>

                <form action={sendMessage} className="mt-4 grid gap-3">
                  <input name="thread_id" type="hidden" value={activeThread.id} />
                  <input name="redirect_to" type="hidden" value="/messages" />
                  <textarea
                    className="min-h-28 w-full rounded-2xl border border-black/10 bg-white px-4 py-3 outline-none"
                    name="body"
                    placeholder={`Message ${activeThread.otherUserName}`}
                  />
                  <button
                    className="rounded-2xl bg-[var(--accent)] px-4 py-3 font-semibold text-white"
                    type="submit"
                  >
                    Send message
                  </button>
                </form>
              </>
            ) : (
              <div>
                <p className="eyebrow">No active thread</p>
                <h2 className="text-3xl font-semibold tracking-[-0.05em]">
                  Start a conversation
                </h2>
                <p className="mt-4 text-sm leading-7 text-[var(--muted)]">
                  Use the creator list to create your first DM thread.
                </p>
              </div>
            )}
          </section>

          <aside className="rounded-[32px] border border-black/10 bg-white/82 p-6 shadow-[0_24px_70px_rgba(74,49,29,0.12)]">
            <p className="eyebrow">Creators</p>
            <div className="mt-4 space-y-3">
              {creators.map((creator) => (
                <article
                  className="rounded-[20px] border border-black/8 bg-white/75 p-4"
                  key={creator.id}
                >
                  <strong className="block text-base text-[var(--ink)]">
                    {creator.name}
                  </strong>
                  <p className="mt-1 text-sm text-[var(--muted)]">
                    {creator.handle}
                  </p>
                  <p className="mt-3 text-sm leading-6 text-[var(--muted)]">
                    {creator.bio}
                  </p>
                  <form action={startConversation} className="mt-4">
                    <input
                      name="target_user_id"
                      type="hidden"
                      value={creator.id}
                    />
                    <input name="redirect_to" type="hidden" value="/messages" />
                    <button
                      className="rounded-2xl border border-black/10 bg-white px-4 py-3 text-sm font-semibold"
                      type="submit"
                    >
                      Message
                    </button>
                  </form>
                </article>
              ))}
            </div>
          </aside>
        </section>
      </div>
    </main>
  );
}

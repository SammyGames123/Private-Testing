import Link from "next/link";
import { redirect } from "next/navigation";
import { getInboxData } from "@/lib/messages";
import { sendMessage } from "./actions";

type MessagesPageProps = {
  searchParams?: Promise<{ thread?: string }>;
};

export default async function MessagesPage({ searchParams }: MessagesPageProps) {
  const resolved = await searchParams;
  const selectedThreadId = resolved?.thread;
  const { user, threads, activeThread } = await getInboxData(selectedThreadId);

  if (!user) {
    redirect("/auth/login");
  }

  // Conversation view
  if (activeThread) {
    return (
      <main
        style={{
          minHeight: "100vh",
          background: "black",
          color: "white",
          display: "flex",
          flexDirection: "column",
          paddingBottom: "6rem",
        }}
      >
        {/* Header */}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: "0.85rem",
            padding: "1.25rem 1rem 0.85rem",
            borderBottom: "1px solid rgba(255,255,255,0.08)",
          }}
        >
          <Link
            href="/messages"
            style={{
              color: "white",
              textDecoration: "none",
              fontSize: "1.5rem",
              lineHeight: 1,
            }}
            aria-label="Back"
          >
            ‹
          </Link>
          <div
            style={{
              width: 40,
              height: 40,
              borderRadius: "50%",
              background: "rgba(255,255,255,0.08)",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontSize: "1rem",
              fontWeight: 700,
              color: "rgba(255,255,255,0.7)",
            }}
          >
            {activeThread.otherUserName.charAt(0).toUpperCase()}
          </div>
          <div>
            <p style={{ margin: 0, fontSize: "0.95rem", fontWeight: 700 }}>
              {activeThread.otherUserName}
            </p>
            <p
              style={{
                margin: 0,
                fontSize: "0.75rem",
                color: "rgba(255,255,255,0.55)",
              }}
            >
              {activeThread.otherUserHandle}
            </p>
          </div>
        </div>

        {/* Messages */}
        <div
          style={{
            flex: 1,
            padding: "1rem",
            display: "flex",
            flexDirection: "column",
            gap: "0.5rem",
          }}
        >
          {activeThread.messages.map((message) => {
            const fromMe = message.senderHandle === "@you";
            return (
              <div
                key={message.id}
                style={{
                  alignSelf: fromMe ? "flex-end" : "flex-start",
                  maxWidth: "75%",
                  padding: "0.65rem 0.9rem",
                  borderRadius: 18,
                  background: fromMe ? "var(--accent)" : "rgba(255,255,255,0.1)",
                  color: "white",
                  fontSize: "0.9rem",
                  lineHeight: 1.35,
                }}
              >
                {message.body}
              </div>
            );
          })}
        </div>

        {/* Compose */}
        <form
          action={sendMessage}
          style={{
            display: "flex",
            gap: "0.5rem",
            padding: "0.85rem 1rem",
            borderTop: "1px solid rgba(255,255,255,0.08)",
            background: "black",
          }}
        >
          <input type="hidden" name="thread_id" value={activeThread.id} />
          <input
            type="hidden"
            name="redirect_to"
            value={`/messages?thread=${activeThread.id}`}
          />
          <input
            name="body"
            placeholder="Message..."
            style={{
              flex: 1,
              padding: "0.6rem 0.85rem",
              borderRadius: 20,
              border: "1px solid rgba(255,255,255,0.12)",
              background: "rgba(255,255,255,0.05)",
              color: "white",
              fontSize: "0.9rem",
              outline: "none",
            }}
          />
          <button
            type="submit"
            style={{
              padding: "0.6rem 1.15rem",
              borderRadius: 20,
              background: "var(--accent)",
              color: "white",
              border: "none",
              fontWeight: 700,
              fontSize: "0.85rem",
              cursor: "pointer",
            }}
          >
            Send
          </button>
        </form>
      </main>
    );
  }

  // Inbox list view
  return (
    <main
      style={{
        minHeight: "100vh",
        background: "black",
        color: "white",
        padding: "1.5rem 1rem 6rem",
      }}
    >
      <h1
        style={{
          fontSize: "1.5rem",
          fontWeight: 700,
          margin: "0 0 1.25rem",
        }}
      >
        Inbox
      </h1>

      {threads.length === 0 ? (
        <p
          style={{
            fontSize: "0.9rem",
            color: "rgba(255,255,255,0.5)",
            textAlign: "center",
            padding: "3rem 1rem",
          }}
        >
          No conversations yet
        </p>
      ) : (
        <div>
          {threads.map((thread) => (
            <Link
              href={`/messages?thread=${thread.id}`}
              key={thread.id}
              style={{
                display: "flex",
                alignItems: "center",
                gap: "0.85rem",
                padding: "0.85rem 0",
                borderBottom: "1px solid rgba(255,255,255,0.06)",
                textDecoration: "none",
                color: "white",
              }}
            >
              <div
                style={{
                  width: 48,
                  height: 48,
                  borderRadius: "50%",
                  background: "rgba(255,255,255,0.08)",
                  flexShrink: 0,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  fontSize: "1.1rem",
                  fontWeight: 700,
                  color: "rgba(255,255,255,0.7)",
                }}
              >
                {thread.otherUserName.charAt(0).toUpperCase()}
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div
                  style={{
                    display: "flex",
                    justifyContent: "space-between",
                    alignItems: "baseline",
                    marginBottom: 4,
                  }}
                >
                  <strong
                    style={{
                      fontSize: "0.95rem",
                      fontWeight: 600,
                      overflow: "hidden",
                      textOverflow: "ellipsis",
                      whiteSpace: "nowrap",
                    }}
                  >
                    {thread.otherUserName}
                  </strong>
                  <span
                    style={{
                      fontSize: "0.7rem",
                      color: "rgba(255,255,255,0.5)",
                      flexShrink: 0,
                      marginLeft: "0.5rem",
                    }}
                  >
                    {thread.latestMessageAt}
                  </span>
                </div>
                <p
                  style={{
                    margin: 0,
                    fontSize: "0.8rem",
                    color: "rgba(255,255,255,0.55)",
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                    whiteSpace: "nowrap",
                  }}
                >
                  {thread.latestMessage}
                </p>
              </div>
            </Link>
          ))}
        </div>
      )}
    </main>
  );
}

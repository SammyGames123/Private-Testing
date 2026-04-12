export default function FeedLoading() {
  return (
    <main className="feed-shell">
      <div className="feed-topbar">
        <div className="feed-tab-strip">
          <span className="feed-tab active">For You</span>
          <span className="feed-tab">Following</span>
        </div>
      </div>
      <section className="feed-scroll">
        <div
          style={{
            position: "absolute",
            inset: 0,
            background: "black",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <div
            style={{
              width: 32,
              height: 32,
              borderRadius: "50%",
              border: "3px solid rgba(255,255,255,0.15)",
              borderTopColor: "white",
              animation: "spin 0.8s linear infinite",
            }}
          />
        </div>
      </section>
    </main>
  );
}

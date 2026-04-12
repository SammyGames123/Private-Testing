export default function MessagesLoading() {
  return (
    <main
      style={{
        minHeight: "100vh",
        background: "black",
        padding: "1.5rem 1rem 6rem",
      }}
    >
      <div
        style={{
          height: 28,
          width: 120,
          background: "rgba(255,255,255,0.08)",
          borderRadius: 6,
          marginBottom: "1.5rem",
        }}
      />
      {Array.from({ length: 6 }).map((_, i) => (
        <div
          key={i}
          style={{
            display: "flex",
            alignItems: "center",
            gap: "0.85rem",
            padding: "0.85rem 0",
            borderBottom: "1px solid rgba(255,255,255,0.06)",
          }}
        >
          <div
            style={{
              width: 48,
              height: 48,
              borderRadius: "50%",
              background: "rgba(255,255,255,0.08)",
              flexShrink: 0,
            }}
          />
          <div style={{ flex: 1 }}>
            <div
              style={{
                width: "40%",
                height: 14,
                background: "rgba(255,255,255,0.08)",
                borderRadius: 4,
                marginBottom: 8,
              }}
            />
            <div
              style={{
                width: "70%",
                height: 12,
                background: "rgba(255,255,255,0.05)",
                borderRadius: 4,
              }}
            />
          </div>
        </div>
      ))}
    </main>
  );
}

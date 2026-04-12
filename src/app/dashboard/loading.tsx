export default function DashboardLoading() {
  return (
    <main
      style={{
        minHeight: "100vh",
        background: "black",
        display: "flex",
        flexDirection: "column",
        padding: "1.5rem 1rem 6rem",
        gap: "1rem",
      }}
    >
      <div
        style={{
          width: 96,
          height: 96,
          borderRadius: "50%",
          background: "rgba(255,255,255,0.08)",
          margin: "1rem auto 0.5rem",
        }}
      />
      <div
        style={{
          width: 140,
          height: 18,
          background: "rgba(255,255,255,0.08)",
          borderRadius: 6,
          margin: "0 auto",
        }}
      />
      <div
        style={{
          width: 100,
          height: 14,
          background: "rgba(255,255,255,0.06)",
          borderRadius: 6,
          margin: "0 auto",
        }}
      />
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "1fr 1fr 1fr",
          gap: 4,
          marginTop: "2rem",
        }}
      >
        {Array.from({ length: 9 }).map((_, i) => (
          <div
            key={i}
            style={{
              aspectRatio: "9 / 16",
              background: "rgba(255,255,255,0.05)",
              borderRadius: 4,
            }}
          />
        ))}
      </div>
    </main>
  );
}

export default function ProfileLoading() {
  return (
    <main
      style={{
        minHeight: "100vh",
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
    </main>
  );
}

import { ImageResponse } from "next/og";

export const size = {
  width: 512,
  height: 512,
};

export const contentType = "image/png";

export default function Icon() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background:
            "radial-gradient(circle at top left, rgba(245,107,51,0.9), transparent 34%), linear-gradient(180deg, #140f13 0%, #24181c 100%)",
          color: "white",
          fontSize: 220,
          fontWeight: 700,
          letterSpacing: "-0.08em",
        }}
      >
        <div
          style={{
            width: "78%",
            height: "78%",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            borderRadius: 140,
            border: "4px solid rgba(255,255,255,0.12)",
            background:
              "linear-gradient(135deg, rgba(255,255,255,0.06), rgba(255,255,255,0.02))",
            boxShadow: "0 30px 100px rgba(0,0,0,0.28)",
          }}
        >
          P
        </div>
      </div>
    ),
    {
      width: size.width,
      height: size.height,
    },
  );
}

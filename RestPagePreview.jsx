import { useState } from "react";

const PURPLE = "#A078FF";
const BG = "#0A0612";

function Star({ x, y, size, opacity }) {
  return (
    <div style={{
      position: "absolute", left: `${x}%`, top: `${y}%`,
      width: size, height: size, borderRadius: "50%",
      background: `rgba(255,255,255,${opacity})`,
      pointerEvents: "none"
    }} />
  );
}

const STARS = Array.from({ length: 60 }, (_, i) => ({
  x: Math.abs(Math.sin(i * 73.7) * 100),
  y: Math.abs(Math.cos(i * 47.3) * 100),
  size: Math.abs(Math.sin(i * 13.1)) * 2 + 0.5,
  opacity: Math.abs(Math.cos(i * 29.9)) * 0.5 + 0.05,
}));

const DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

export default function RestPagePreview() {
  const [nextDay, setNextDay] = useState("Monday");

  return (
    <div style={{
      background: "#1a1030", minHeight: "100vh",
      display: "flex", flexDirection: "column", alignItems: "center",
      justifyContent: "center", fontFamily: "system-ui", padding: 24, gap: 28
    }}>
      <h2 style={{ color: "rgba(255,255,255,0.35)", fontWeight: 300, margin: 0, fontSize: 11, letterSpacing: 3 }}>
        REST PAGE PREVIEW
      </h2>

      {/* Phone frame */}
      <div style={{
        width: 320, height: 620, borderRadius: 44,
        border: "2px solid rgba(255,255,255,0.12)",
        background: BG, position: "relative", overflow: "hidden",
        boxShadow: "0 32px 80px rgba(0,0,0,0.7)"
      }}>
        {STARS.map((s, i) => <Star key={i} {...s} />)}

        <div style={{
          position: "absolute", inset: 0,
          background: "rgba(10,4,26,0.55)",
          pointerEvents: "none"
        }} />

        {/* Gear */}
        <div style={{
          position: "absolute", top: 24, right: 24,
          width: 40, height: 40, borderRadius: "50%",
          background: "rgba(255,255,255,0.08)",
          border: "1px solid rgba(255,255,255,0.12)",
          display: "flex", alignItems: "center", justifyContent: "center",
          color: "rgba(255,255,255,0.85)", fontSize: 18
        }}>⚙</div>

        {/* Page dots */}
        <div style={{
          position: "absolute", bottom: 22, left: "50%", transform: "translateX(-50%)",
          display: "flex", gap: 8
        }}>
          <div style={{ width: 7, height: 7, borderRadius: "50%", background: "rgba(255,255,255,0.25)" }} />
          <div style={{ width: 7, height: 7, borderRadius: "50%", background: PURPLE }} />
        </div>

        {/* Centre content */}
        <div style={{
          position: "absolute", inset: 0,
          display: "flex", flexDirection: "column",
          alignItems: "center", justifyContent: "center",
          paddingBottom: 40
        }}>
          {/* Main text */}
          <div style={{
            fontFamily: "Georgia, serif",
            fontSize: 38, fontWeight: 300,
            color: "rgba(255,255,255,0.90)",
            textAlign: "center",
            lineHeight: 1.25,
            padding: "0 32px"
          }}>
            No Alarm tomorrow
          </div>

          <div style={{ height: 32 }} />

          {/* Divider */}
          <div style={{
            width: "calc(100% - 64px)", height: 1,
            background: "rgba(255,255,255,0.95)"
          }} />

          <div style={{ height: 28 }} />

          {/* Next alarm */}
          <div style={{
            color: "rgba(255,255,255,0.35)",
            fontSize: 14,
            fontFamily: "system-ui",
            fontWeight: 400
          }}>
            Next Alarm {nextDay}
          </div>
        </div>
      </div>

      {/* Day picker */}
      <div style={{
        background: "rgba(255,255,255,0.04)",
        border: "1px solid rgba(255,255,255,0.08)",
        borderRadius: 14, padding: "16px 20px",
        display: "flex", flexDirection: "column", gap: 12, width: 320
      }}>
        <div style={{ color: "rgba(255,255,255,0.35)", fontSize: 11, letterSpacing: 2 }}>NEXT ALARM DAY</div>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
          {DAYS.map(d => (
            <button key={d} onClick={() => setNextDay(d)} style={{
              padding: "7px 14px", borderRadius: 8, border: "none",
              background: nextDay === d ? "rgba(160,120,255,0.3)" : "rgba(255,255,255,0.06)",
              color: nextDay === d ? "#fff" : "rgba(255,255,255,0.45)",
              cursor: "pointer", fontSize: 12,
              outline: nextDay === d ? `1px solid ${PURPLE}` : "none"
            }}>{d}</button>
          ))}
        </div>
      </div>
    </div>
  );
}

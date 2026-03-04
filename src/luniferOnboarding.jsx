import { useState } from "react";

const FONT = `@import url('https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,300;0,400;1,300;1,400&family=Cormorant+Infant:ital,wght@1,300&family=DM+Sans:wght@300;400&family=Roboto:wght@300;400&display=swap');`;

const css = `
${FONT}
* { box-sizing: border-box; margin: 0; padding: 0; }

.ob-root {
  min-height: 100vh;
  background: #120e1e;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  position: relative;
  overflow: hidden;
  font-family: 'DM Sans', sans-serif;
}

/* ── Background atmosphere ── */
.bg-glow-1 {
  position: absolute;
  width: 500px; height: 500px;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(110,70,180,0.18) 0%, transparent 70%);
  top: -120px; left: 50%; transform: translateX(-50%);
  pointer-events: none;
}
.bg-glow-2 {
  position: absolute;
  width: 300px; height: 300px;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(80,50,140,0.12) 0%, transparent 70%);
  bottom: 60px; right: -60px;
  pointer-events: none;
}
.grain {
  position: absolute; inset: 0;
  background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 200 200' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)' opacity='0.04'/%3E%3C/svg%3E");
  pointer-events: none; opacity: 0.6;
}

/* ── Stars ── */
.stars { position: absolute; inset: 0; pointer-events: none; }
.star {
  position: absolute;
  background: rgba(220,210,255,var(--op));
  border-radius: 50%;
  animation: twinkle var(--dur) ease-in-out infinite alternate;
}
@keyframes twinkle { to { opacity: 0.05; } }

/* ── Screens ── */
.screen {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 48px 32px;
  transition: opacity 0.8s ease, transform 0.8s ease;
  text-align: center;
}
.screen.hidden { opacity: 0; pointer-events: none; transform: translateY(20px); }
.screen.visible { opacity: 1; transform: translateY(0); }
.screen.exit { opacity: 0; transform: translateY(-20px); }

/* ── Screen 1 — Splash ── */
.moon-wrap {
  position: relative;
  margin-bottom: 36px;
}
.moon {
  width: 80px; height: 80px;
  border-radius: 50%;
  background: linear-gradient(145deg, #c8b0f0 0%, #7a50c0 40%, #2e1a60 100%);
  box-shadow:
    0 0 60px rgba(150,100,220,0.25),
    0 0 120px rgba(100,60,180,0.15),
    inset -14px -6px 0 rgba(18,14,30,0.5);
  animation: moonFloat 6s ease-in-out infinite;
}
@keyframes moonFloat {
  0%, 100% { transform: translateY(0); }
  50% { transform: translateY(-8px); }
}
.moon-ring {
  position: absolute;
  top: 50%; left: 50%; transform: translate(-50%, -50%);
  width: 110px; height: 110px;
  border-radius: 50%;
  border: 1px solid rgba(160,120,220,0.15);
  animation: ringPulse 4s ease-in-out infinite;
}
.moon-ring-2 {
  position: absolute;
  top: 50%; left: 50%; transform: translate(-50%, -50%);
  width: 140px; height: 140px;
  border-radius: 50%;
  border: 1px solid rgba(130,90,200,0.08);
  animation: ringPulse 4s ease-in-out infinite 0.5s;
}
@keyframes ringPulse {
  0%, 100% { opacity: 1; transform: translate(-50%, -50%) scale(1); }
  50% { opacity: 0.4; transform: translate(-50%, -50%) scale(1.05); }
}

.brand {
  font-family: 'Cormorant Garamond', serif;
  font-weight: 300;
  font-style: italic;
  font-size: 62px;
  color: #e8deff;
  letter-spacing: 8px;
  line-height: 1;
  margin-bottom: 10px;
  text-shadow: 0 0 40px rgba(180,140,255,0.3);
}
.tagline {
  font-size: 12px;
  letter-spacing: 4px;
  text-transform: uppercase;
  color: rgba(180,160,220,0.4);
  font-weight: 300;
  margin-bottom: 64px;
}

/* ── Screen 2 — Problem ── */
.screen-eyebrow {
  font-size: 10px;
  letter-spacing: 4px;
  text-transform: uppercase;
  color: rgba(160,130,210,0.5);
  margin-bottom: 24px;
}
.screen-headline {
  font-family: 'Cormorant Garamond', serif;
  font-weight: 300;
  font-style: italic;
  font-size: 42px;
  color: #e0d8ff;
  line-height: 1.2;
  margin-bottom: 20px;
  letter-spacing: 1px;
}
.screen-body {
  font-size: 14px;
  color: rgba(180,160,220,0.5);
  line-height: 1.9;
  font-weight: 300;
  max-width: 280px;
  margin-bottom: 56px;
}

/* ── Screen 3 — How it works ── */
.feature-list {
  display: flex;
  flex-direction: column;
  gap: 20px;
  margin-bottom: 52px;
  width: 100%;
  max-width: 300px;
}
.feature-item {
  display: flex;
  align-items: flex-start;
  gap: 16px;
  text-align: left;
}
.feature-icon {
  width: 36px; height: 36px;
  border-radius: 12px;
  background: rgba(100,70,160,0.2);
  border: 1px solid rgba(130,100,190,0.2);
  display: flex; align-items: center; justify-content: center;
  font-size: 16px;
  flex-shrink: 0;
}
.feature-text {}
.feature-name {
  font-size: 13px;
  font-weight: 400;
  color: rgba(220,210,255,0.8);
  margin-bottom: 3px;
}
.feature-desc {
  font-size: 12px;
  color: rgba(160,140,200,0.4);
  font-weight: 300;
  line-height: 1.6;
}

/* ── Screen 4 — Get Started ── */
.big-time {
  font-family: 'Roboto', sans-serif;
  font-style: italic;
  font-weight: 300;
  font-size: 80px;
  color: #e0d4ff;
  letter-spacing: -2px;
  line-height: 1;
  margin-bottom: 8px;
  text-shadow: 0 0 60px rgba(160,120,240,0.3);
}
.big-time-label {
  font-size: 11px;
  letter-spacing: 3px;
  text-transform: uppercase;
  color: rgba(160,130,210,0.35);
  margin-bottom: 52px;
}

/* ── Buttons ── */
.btn-primary {
  width: 100%;
  max-width: 280px;
  padding: 16px 32px;
  border-radius: 50px;
  background: rgba(110,70,180,0.25);
  border: 1px solid rgba(160,120,220,0.3);
  color: rgba(220,205,255,0.9);
  font-family: 'DM Sans', sans-serif;
  font-size: 13px;
  letter-spacing: 3px;
  text-transform: uppercase;
  cursor: pointer;
  transition: all 0.3s ease;
  backdrop-filter: blur(10px);
}
.btn-primary:hover {
  background: rgba(130,90,200,0.35);
  border-color: rgba(180,140,240,0.5);
  box-shadow: 0 0 30px rgba(130,80,220,0.2);
}
.btn-ghost {
  background: transparent;
  border: none;
  color: rgba(160,140,200,0.35);
  font-family: 'DM Sans', sans-serif;
  font-size: 12px;
  letter-spacing: 2px;
  text-transform: uppercase;
  cursor: pointer;
  margin-top: 16px;
  transition: color 0.3s;
}
.btn-ghost:hover { color: rgba(180,160,220,0.6); }

/* ── Progress dots ── */
.dots {
  position: fixed;
  bottom: 40px;
  left: 50%;
  transform: translateX(-50%);
  display: flex;
  gap: 8px;
  z-index: 10;
}
.dot {
  height: 4px;
  border-radius: 2px;
  background: rgba(160,130,210,0.2);
  transition: all 0.4s ease;
  cursor: pointer;
}
.dot.active {
  background: rgba(180,150,230,0.6);
  width: 20px;
}
.dot:not(.active) { width: 4px; }
`;

const TOTAL_SCREENS = 3;

const Stars = () => {
  const stars = Array.from({ length: 60 }, (_, i) => ({
    id: i,
    top: Math.random() * 100,
    left: Math.random() * 100,
    size: Math.random() * 1.5 + 0.5,
    op: (Math.random() * 0.25 + 0.05).toFixed(2),
    dur: (Math.random() * 5 + 3).toFixed(1),
  }));
  return (
    <div className="stars">
      {stars.map(s => (
        <div key={s.id} className="star" style={{
          top: `${s.top}%`, left: `${s.left}%`,
          width: s.size, height: s.size,
          "--op": s.op, "--dur": `${s.dur}s`,
        }} />
      ))}
    </div>
  );
};

function getScreenState(current, index) {
  if (current === index) return "visible";
  if (current > index) return "exit";
  return "hidden";
}

export default function LuniferOnboarding({ onFinish }) {
  const [screen, setScreen] = useState(0);

  const next = () => setScreen(s => Math.min(s + 1, TOTAL_SCREENS - 1));
  const goTo = (i) => setScreen(i);

  return (
    <>
      <style>{css}</style>
      <div className="ob-root">
        <div className="bg-glow-1" />
        <div className="bg-glow-2" />
        <div className="grain" />
        <Stars />

        {/* ── SCREEN 0 — Splash ── */}
        <div className={`screen ${getScreenState(screen, 0)}`}>
          <div className="moon-wrap">
            <div className="moon-ring-2" />
            <div className="moon-ring" />
            <div className="moon" />
          </div>
          <div className="brand">Lunifer</div>
          <button className="btn-primary" style={{ marginTop: "15px" }} onClick={next}>Begin</button>
        </div>

        {/* ── SCREEN 1 — The Problem ── */}
        <div className={`screen ${getScreenState(screen, 1)}`}>
          <div className="screen-headline">
            The last thing you need before<br />bed is one more thing to do
          </div>
          <div className="screen-body">
            After a long day, setting your alarm should be the least of your worries.
            Lunifer takes care of it — quietly and intelligently.
          </div>
          <button className="btn-primary" onClick={next}>Continue</button>
        </div>

        {/* ── SCREEN 2 — How It Works ── */}
        <div className={`screen ${getScreenState(screen, 2)}`}>
          <div className="screen-headline" style={{ fontSize: 34, marginBottom: 28 }}>
            Lunifer learns
          </div>
          <div className="feature-list">
            {[
              { icon: "😴", name: "Optimal sleep", desc: "Learns exactly how much sleep you need to feel your best" },
              { icon: "🌙", name: "Bedtime adaptive", desc: "Went to bed late? Lunifer quietly adjusts based on your preferences" },
              { icon: "🚗", name: "Commute aware", desc: "Factors in your drive time and live traffic conditions" },
            ].map((f, i) => (
              <div className="feature-item" key={i}>
                <div className="feature-icon">{f.icon}</div>
                <div className="feature-text">
                  <div className="feature-name">{f.name}</div>
                  <div className="feature-desc">{f.desc}</div>
                </div>
              </div>
            ))}
          </div>
          <button className="btn-primary" onClick={onFinish}>Set up Lunifer</button>
        </div>

        {/* ── Progress dots ── */}
        <div className="dots">
          {Array.from({ length: TOTAL_SCREENS }).map((_, i) => (
            <div key={i} className={`dot ${screen === i ? "active" : ""}`} onClick={() => goTo(i)} />
          ))}
        </div>
      </div>
    </>
  );
}

import { useState, useEffect } from "react";

const SAMPLES_DEFAULT = [0.048, 0.051, 0.044, 0.056, 0.049];

function stdDev(arr) {
  const mean = arr.reduce((a, b) => a + b, 0) / arr.length;
  const variance = arr.reduce((a, b) => a + Math.pow(b - mean, 2), 0) / arr.length;
  return Math.sqrt(variance);
}

function conservativeRate(samples) {
  if (samples.length < 3) return 0.05 * 1.25;
  const mean = samples.reduce((a, b) => a + b, 0) / samples.length;
  const std = stdDev(samples);
  return Math.max(mean + std, 0.05);
}

function formatTime(date) {
  return date.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}

function formatPct(val) {
  return Math.round(val * 100) + "%";
}

export default function BatterySimulation() {
  const [batteryPct, setBatteryPct] = useState(35);
  const [alarmHour, setAlarmHour] = useState(7);
  const [sleepHours, setSleepHours] = useState(8);
  const [currentHour, setCurrentHour] = useState(21.5);
  const [samples, setSamples] = useState(SAMPLES_DEFAULT);
  const [newSample, setNewSample] = useState("");
  const [charging, setCharging] = useState(false);

  const now = new Date();
  now.setHours(Math.floor(currentHour), Math.round((currentHour % 1) * 60), 0, 0);

  const alarm = new Date(now);
  if (alarmHour <= Math.floor(currentHour)) alarm.setDate(alarm.getDate() + 1);
  alarm.setHours(alarmHour, 0, 0, 0);

  const hoursUntilAlarm = (alarm - now) / 3600000;
  const bedtime = new Date(alarm.getTime() - sleepHours * 3600000);
  const windowOpen = new Date(bedtime.getTime() - 2 * 3600000);

  const inWindow = now >= windowOpen;
  const rate = conservativeRate(samples);
  const mean = samples.reduce((a, b) => a + b, 0) / samples.length;
  const std = samples.length >= 3 ? stdDev(samples) : null;
  const projected = (batteryPct / 100) - rate * hoursUntilAlarm;
  const willDie = projected <= 0;
  const shouldNotify = !charging && inWindow && willDie;

  const timeUntilWindow = Math.max(0, (windowOpen - now) / 3600000);

  const barColor = (pct) => {
    if (pct > 0.5) return "#4ade80";
    if (pct > 0.2) return "#facc15";
    return "#f87171";
  };

  return (
    <div style={{ background: "#0d0d1a", minHeight: "100vh", color: "#e2e8f0", fontFamily: "system-ui, sans-serif", padding: "24px" }}>
      <div style={{ maxWidth: 680, margin: "0 auto" }}>

        {/* Header */}
        <div style={{ marginBottom: 28 }}>
          <h1 style={{ fontSize: 22, fontWeight: 600, color: "#a78bfa", margin: 0 }}>BatteryAlarmGuard — Simulation</h1>
          <p style={{ fontSize: 13, color: "#64748b", marginTop: 4 }}>Adjust the controls to see when Lunifer fires a battery warning.</p>
        </div>

        {/* Notification result */}
        <div style={{
          background: shouldNotify ? "rgba(239,68,68,0.12)" : charging ? "rgba(74,222,128,0.10)" : "rgba(255,255,255,0.04)",
          border: `1px solid ${shouldNotify ? "#ef444455" : charging ? "#4ade8055" : "#ffffff15"}`,
          borderRadius: 14, padding: "18px 20px", marginBottom: 24,
          display: "flex", alignItems: "center", gap: 14
        }}>
          <div style={{ fontSize: 32 }}>{charging ? "🔌" : shouldNotify ? "🔔" : inWindow ? "✅" : "🕐"}</div>
          <div>
            <div style={{ fontWeight: 600, fontSize: 15, color: shouldNotify ? "#f87171" : charging ? "#4ade80" : "#e2e8f0" }}>
              {charging
                ? "Charging — no risk"
                : shouldNotify
                  ? "Notification fires now"
                  : inWindow
                    ? "Battery safe — no notification"
                    : `Outside notification window — opens in ${timeUntilWindow.toFixed(1)}h`}
            </div>
            {shouldNotify && (
              <div style={{ fontSize: 13, color: "#94a3b8", marginTop: 4 }}>
                "Your phone is at {batteryPct}% and is predicted to die before your {formatTime(alarm)} alarm. Plug in before you sleep."
              </div>
            )}
            {!shouldNotify && !charging && inWindow && (
              <div style={{ fontSize: 13, color: "#64748b", marginTop: 4 }}>
                Projected battery at alarm: {formatPct(Math.max(0, projected))} — phone survives
              </div>
            )}
          </div>
        </div>

        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16, marginBottom: 16 }}>

          {/* Left controls */}
          <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>

            {/* Battery */}
            <div style={{ background: "#ffffff08", borderRadius: 12, padding: 16 }}>
              <div style={{ fontSize: 11, color: "#64748b", letterSpacing: 1, marginBottom: 10, textTransform: "uppercase" }}>Current Battery</div>
              <div style={{ fontSize: 36, fontWeight: 700, color: batteryPct < 20 ? "#f87171" : batteryPct < 40 ? "#facc15" : "#4ade80", marginBottom: 10 }}>
                {batteryPct}%
              </div>
              <div style={{ background: "#ffffff10", borderRadius: 4, height: 8, marginBottom: 10 }}>
                <div style={{ background: barColor(batteryPct / 100), borderRadius: 4, height: "100%", width: `${batteryPct}%`, transition: "all 0.2s" }} />
              </div>
              <input type="range" min={1} max={100} value={batteryPct}
                onChange={e => setBatteryPct(+e.target.value)}
                style={{ width: "100%", accentColor: "#a78bfa" }} />

              <label style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 10, fontSize: 13, cursor: "pointer" }}>
                <input type="checkbox" checked={charging} onChange={e => setCharging(e.target.checked)}
                  style={{ accentColor: "#4ade80" }} />
                <span style={{ color: "#94a3b8" }}>Charging</span>
              </label>
            </div>

            {/* Current time */}
            <div style={{ background: "#ffffff08", borderRadius: 12, padding: 16 }}>
              <div style={{ fontSize: 11, color: "#64748b", letterSpacing: 1, marginBottom: 10, textTransform: "uppercase" }}>Current Time</div>
              <div style={{ fontSize: 24, fontWeight: 600, marginBottom: 8 }}>{formatTime(now)}</div>
              <input type="range" min={0} max={23.9} step={0.25} value={currentHour}
                onChange={e => setCurrentHour(+e.target.value)}
                style={{ width: "100%", accentColor: "#a78bfa" }} />
            </div>

            {/* Alarm time */}
            <div style={{ background: "#ffffff08", borderRadius: 12, padding: 16 }}>
              <div style={{ fontSize: 11, color: "#64748b", letterSpacing: 1, marginBottom: 10, textTransform: "uppercase" }}>Alarm Time</div>
              <div style={{ fontSize: 24, fontWeight: 600, marginBottom: 8 }}>{formatTime(alarm)}</div>
              <input type="range" min={1} max={12} step={0.5} value={alarmHour}
                onChange={e => setAlarmHour(+e.target.value)}
                style={{ width: "100%", accentColor: "#a78bfa" }} />
            </div>

            {/* Sleep duration */}
            <div style={{ background: "#ffffff08", borderRadius: 12, padding: 16 }}>
              <div style={{ fontSize: 11, color: "#64748b", letterSpacing: 1, marginBottom: 10, textTransform: "uppercase" }}>Expected Sleep</div>
              <div style={{ fontSize: 24, fontWeight: 600, marginBottom: 8 }}>{sleepHours}h</div>
              <input type="range" min={5} max={10} step={0.5} value={sleepHours}
                onChange={e => setSleepHours(+e.target.value)}
                style={{ width: "100%", accentColor: "#a78bfa" }} />
            </div>
          </div>

          {/* Right — model output */}
          <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>

            {/* Timeline */}
            <div style={{ background: "#ffffff08", borderRadius: 12, padding: 16 }}>
              <div style={{ fontSize: 11, color: "#64748b", letterSpacing: 1, marginBottom: 14, textTransform: "uppercase" }}>Notification Window</div>
              {[
                { label: "Window opens", time: windowOpen, color: "#a78bfa" },
                { label: "Est. bedtime", time: bedtime, color: "#60a5fa" },
                { label: "Alarm", time: alarm, color: "#4ade80" },
              ].map(({ label, time, color }) => (
                <div key={label} style={{ display: "flex", justifyContent: "space-between", marginBottom: 10 }}>
                  <span style={{ fontSize: 13, color: "#94a3b8" }}>{label}</span>
                  <span style={{ fontSize: 13, fontWeight: 600, color }}>{formatTime(time)}</span>
                </div>
              ))}
              <div style={{ borderTop: "1px solid #ffffff10", paddingTop: 10, marginTop: 4 }}>
                <div style={{ display: "flex", justifyContent: "space-between" }}>
                  <span style={{ fontSize: 13, color: "#94a3b8" }}>Now in window?</span>
                  <span style={{ fontSize: 13, fontWeight: 600, color: inWindow ? "#4ade80" : "#f87171" }}>
                    {inWindow ? "Yes" : "No"}
                  </span>
                </div>
              </div>
            </div>

            {/* Prediction model */}
            <div style={{ background: "#ffffff08", borderRadius: 12, padding: 16 }}>
              <div style={{ fontSize: 11, color: "#64748b", letterSpacing: 1, marginBottom: 14, textTransform: "uppercase" }}>Drain Prediction</div>
              {[
                { label: "Mean drain rate", value: formatPct(mean) + "/hr" },
                { label: "Std deviation", value: std !== null ? formatPct(std) + "/hr" : "< 3 samples" },
                { label: "Conservative rate", value: formatPct(rate) + "/hr", highlight: true },
                { label: "Hours until alarm", value: hoursUntilAlarm.toFixed(1) + "h" },
                { label: "Expected drain", value: formatPct(rate * hoursUntilAlarm) },
                { label: "Projected at alarm", value: projected <= 0 ? "DEAD" : formatPct(projected), color: projected <= 0 ? "#f87171" : projected < 0.15 ? "#facc15" : "#4ade80" },
              ].map(({ label, value, highlight, color }) => (
                <div key={label} style={{ display: "flex", justifyContent: "space-between", marginBottom: 8 }}>
                  <span style={{ fontSize: 13, color: highlight ? "#e2e8f0" : "#94a3b8", fontWeight: highlight ? 600 : 400 }}>{label}</span>
                  <span style={{ fontSize: 13, fontWeight: 600, color: color || (highlight ? "#a78bfa" : "#e2e8f0") }}>{value}</span>
                </div>
              ))}
            </div>

            {/* Drain samples */}
            <div style={{ background: "#ffffff08", borderRadius: 12, padding: 16 }}>
              <div style={{ fontSize: 11, color: "#64748b", letterSpacing: 1, marginBottom: 12, textTransform: "uppercase" }}>
                Drain Samples ({samples.length}/10)
              </div>
              <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginBottom: 12 }}>
                {samples.map((s, i) => (
                  <div key={i} style={{
                    background: "#ffffff0a", border: "1px solid #ffffff15", borderRadius: 6,
                    padding: "4px 8px", fontSize: 12, color: "#94a3b8",
                    display: "flex", alignItems: "center", gap: 6
                  }}>
                    {formatPct(s)}/hr
                    <button onClick={() => setSamples(samples.filter((_, j) => j !== i))}
                      style={{ background: "none", border: "none", color: "#ef4444", cursor: "pointer", padding: 0, fontSize: 12, lineHeight: 1 }}>×</button>
                  </div>
                ))}
              </div>
              <div style={{ display: "flex", gap: 8 }}>
                <input
                  type="number" placeholder="e.g. 0.06" step="0.001" min="0.005" max="0.25"
                  value={newSample}
                  onChange={e => setNewSample(e.target.value)}
                  style={{ flex: 1, background: "#ffffff08", border: "1px solid #ffffff15", borderRadius: 8, padding: "6px 10px", color: "#e2e8f0", fontSize: 13 }}
                />
                <button
                  onClick={() => {
                    const v = parseFloat(newSample);
                    if (v >= 0.005 && v <= 0.25 && samples.length < 10) {
                      setSamples([...samples, v]);
                      setNewSample("");
                    }
                  }}
                  style={{ background: "#a78bfa22", border: "1px solid #a78bfa55", borderRadius: 8, padding: "6px 12px", color: "#a78bfa", cursor: "pointer", fontSize: 13 }}>
                  Add
                </button>
              </div>
              <p style={{ fontSize: 11, color: "#475569", marginTop: 8 }}>Enter as a decimal — 0.05 = 5%/hr</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

import { useState } from "react";
import { FaApple } from "react-icons/fa";
import { SiMicrosoftoutlook } from "react-icons/si";

function GoogleCalendarIcon({ size = 22 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
      <rect width="24" height="24" rx="2.5" fill="white"/>
      <path d="M0 2.5A2.5 2.5 0 012.5 0h19A2.5 2.5 0 0124 2.5V8H0V2.5z" fill="#1A73E8"/>
      <rect x="7" y="0" width="2" height="5" rx="1" fill="#185ABC"/>
      <rect x="15" y="0" width="2" height="5" rx="1" fill="#185ABC"/>
      <text x="12" y="19.5" textAnchor="middle" fontSize="10" fontWeight="700" fill="#1A73E8" fontFamily="Arial, sans-serif">31</text>
    </svg>
  );
}

const CALENDAR_APPS = [
  { id: "apple", name: "Apple Calendar", icon: <FaApple size={22} color="white" /> },
  { id: "google", name: "Google Calendar", icon: <GoogleCalendarIcon size={22} /> },
  { id: "outlook", name: "Outlook", icon: <SiMicrosoftoutlook size={22} color="#0078D4" /> },
  { id: "none", name: "I don't use one", icon: "—" },
];

const styles = `
  @import url('https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,300;0,400;1,300;1,400&family=DM+Sans:wght@300;400;500&family=Roboto:wght@300;400&display=swap');
  * { box-sizing: border-box; margin: 0; padding: 0; }
  .survey-root {
    min-height: 100vh; width: 100%;
    background: #0d0a18;
    display: flex; align-items: center; justify-content: center;
    font-family: 'DM Sans', sans-serif;
    position: relative; overflow: hidden;
  }
  .bg-glow { position: fixed; border-radius: 50%; filter: blur(80px); pointer-events: none; z-index: 0; }
  .bg-glow-1 { width: 500px; height: 500px; background: rgba(110,60,220,0.15); top: -100px; left: -100px; }
  .bg-glow-2 { width: 400px; height: 400px; background: rgba(60,30,160,0.12); bottom: -80px; right: -80px; }
  .stars { position: fixed; top: 0; left: 0; width: 100%; height: 100%; z-index: 0; pointer-events: none; }
  .star { position: absolute; background: white; border-radius: 50%; animation: twinkle var(--dur, 3s) ease-in-out infinite; animation-delay: var(--delay, 0s); }
  @keyframes twinkle { 0%, 100% { opacity: 0.1; } 50% { opacity: 0.7; } }
  .card { position: relative; z-index: 10; width: 100%; max-width: 480px; padding: 48px 40px; animation: fadeSlideIn 0.5s ease forwards; }
  @keyframes fadeSlideIn { from { opacity: 0; transform: translateY(24px); } to { opacity: 1; transform: translateY(0); } }
  .step-indicator { display: flex; gap: 6px; margin-bottom: 40px; justify-content: center; }
  .step-dot { width: 28px; height: 3px; border-radius: 2px; background: rgba(255,255,255,0.15); transition: all 0.4s ease; }
  .step-dot.active { background: rgba(160,120,255,0.9); width: 40px; }
  .step-dot.done { background: rgba(160,120,255,0.4); }
  .question-label { font-size: 11px; font-weight: 500; letter-spacing: 0.15em; text-transform: uppercase; color: rgba(160,120,255,0.8); margin-bottom: 12px; }
  .question-title { font-family: 'Cormorant Garamond', serif; font-size: 32px; font-weight: 300; line-height: 1.25; color: rgba(255,255,255,0.95); margin-bottom: 10px; }
  .question-sub { font-size: 14px; color: rgba(255,255,255,0.4); line-height: 1.6; margin-bottom: 36px; }
  .cal-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-bottom: 36px; }
  .cal-option { display: flex; align-items: center; gap: 12px; padding: 14px 16px; border-radius: 12px; border: 1.5px solid rgba(255,255,255,0.08); background: rgba(255,255,255,0.03); cursor: pointer; transition: all 0.2s ease; color: rgba(255,255,255,0.7); font-size: 14px; }
  .cal-option:hover { border-color: rgba(160,120,255,0.4); background: rgba(160,120,255,0.06); color: rgba(255,255,255,0.9); }
  .cal-option.selected { border-color: rgba(160,120,255,0.8); background: rgba(160,120,255,0.12); color: rgba(255,255,255,0.95); }
  .cal-icon { font-size: 20px; width: 28px; text-align: center; flex-shrink: 0; display: flex; align-items: center; justify-content: center; }
  .time-picker { display: flex; align-items: center; gap: 16px; margin-bottom: 20px; }
  .time-unit { display: flex; flex-direction: column; align-items: center; gap: 10px; }
  .time-unit-label { font-size: 11px; letter-spacing: 0.1em; text-transform: uppercase; color: rgba(255,255,255,0.3); }
  .time-display { font-family: 'Roboto', sans-serif; font-size: 64px; font-weight: 300; color: rgba(255,255,255,0.95); line-height: 1; min-width: 90px; text-align: center; }
  .time-sep { font-family: 'Roboto', sans-serif; font-size: 48px; font-weight: 300; color: rgba(255,255,255,0.2); margin-top: -8px; }
  .time-btn-group { display: flex; flex-direction: column; gap: 6px; }
  .time-btn { width: 36px; height: 36px; border-radius: 10px; border: 1.5px solid rgba(255,255,255,0.1); background: rgba(255,255,255,0.04); color: rgba(255,255,255,0.6); font-size: 18px; cursor: pointer; display: flex; align-items: center; justify-content: center; transition: all 0.15s ease; user-select: none; }
  .time-btn:hover { border-color: rgba(160,120,255,0.5); background: rgba(160,120,255,0.1); color: white; }
  .time-btn:active { transform: scale(0.92); }
  .auto-toggle { display: flex; align-items: center; gap: 12px; padding: 14px 18px; border-radius: 12px; border: 1.5px solid rgba(255,255,255,0.06); background: rgba(255,255,255,0.02); cursor: pointer; transition: all 0.2s ease; margin-bottom: 36px; }
  .auto-toggle:hover { border-color: rgba(160,120,255,0.3); background: rgba(160,120,255,0.05); }
  .auto-toggle.active { border-color: rgba(160,120,255,0.6); background: rgba(160,120,255,0.08); }
  .toggle-pill { width: 40px; height: 22px; border-radius: 11px; background: rgba(255,255,255,0.1); position: relative; transition: background 0.2s; flex-shrink: 0; }
  .toggle-pill.on { background: rgba(160,120,255,0.8); }
  .toggle-knob { position: absolute; top: 3px; left: 3px; width: 16px; height: 16px; border-radius: 50%; background: white; transition: transform 0.2s; }
  .toggle-pill.on .toggle-knob { transform: translateX(18px); }
  .toggle-text { font-size: 14px; color: rgba(255,255,255,0.5); transition: color 0.2s; }
  .auto-toggle.active .toggle-text { color: rgba(255,255,255,0.85); }
  .btn-next { width: 100%; padding: 16px; border-radius: 14px; border: none; background: linear-gradient(135deg, rgba(120,80,220,0.9), rgba(80,50,180,0.9)); color: white; font-family: 'DM Sans', sans-serif; font-size: 15px; font-weight: 500; cursor: pointer; transition: all 0.2s ease; }
  .btn-next:hover { transform: translateY(-1px); box-shadow: 0 8px 30px rgba(100,60,200,0.35); }
  .btn-next:disabled { opacity: 0.35; cursor: not-allowed; transform: none; box-shadow: none; }
  .btn-back { background: none; border: none; color: rgba(255,255,255,0.3); font-family: 'DM Sans', sans-serif; font-size: 14px; cursor: pointer; padding: 12px 0; display: block; margin: 0 auto; transition: color 0.2s; }
  .btn-back:hover { color: rgba(255,255,255,0.6); }
  .time-hint { font-size: 13px; color: rgba(255,255,255,0.25); margin-bottom: 28px; margin-top: -4px; }
  .complete-screen { text-align: center; padding: 48px 40px; max-width: 420px; animation: fadeSlideIn 0.5s ease forwards; position: relative; z-index: 10; }
  .moon-complete { font-size: 64px; display: block; margin-bottom: 28px; animation: float 3s ease-in-out infinite; }
  @keyframes float { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-10px); } }
  .complete-title { font-family: 'Cormorant Garamond', serif; font-size: 40px; font-weight: 300; color: rgba(255,255,255,0.95); margin-bottom: 12px; }
  .complete-sub { font-size: 15px; color: rgba(255,255,255,0.4); line-height: 1.7; margin-bottom: 40px; }
  .summary-pills { margin-bottom: 36px; }
  .summary-pill { display: inline-flex; align-items: center; gap: 8px; padding: 8px 16px; border-radius: 30px; border: 1px solid rgba(160,120,255,0.25); background: rgba(160,120,255,0.07); font-size: 13px; color: rgba(255,255,255,0.6); margin: 4px; }
  .age-input { width: 140px; padding: 16px 20px; border-radius: 14px; border: 1.5px solid rgba(255,255,255,0.1); background: rgba(255,255,255,0.04); color: rgba(255,255,255,0.95); font-family: 'Roboto', sans-serif; font-size: 40px; font-weight: 300; text-align: center; outline: none; transition: all 0.2s ease; -moz-appearance: textfield; }
  .age-input::-webkit-outer-spin-button, .age-input::-webkit-inner-spin-button { -webkit-appearance: none; }
  .age-input:focus { border-color: rgba(160,120,255,0.6); background: rgba(160,120,255,0.06); }
  .age-wrap { display: flex; justify-content: center; margin-bottom: 36px; }
`;

const stars = Array.from({ length: 60 }, (_, i) => ({   //code to generate random stars for the background
  id: i,
  top: `${Math.random() * 100}%`,
  left: `${Math.random() * 100}%`,
  size: Math.random() * 2 + 0.5,
  dur: `${Math.random() * 4 + 2}s`,
  delay: `${Math.random() * 5}s`,
}));

function TimeScalePicker({ value, onChange, autoLabel }) { //code to create a time scale picker component for the survey
  const { hours, minutes, auto } = value;

  const update = (field, delta) => {
    if (field === "hours") {
      onChange({ ...value, hours: Math.max(0, Math.min(23, hours + delta)) });
    } else {
      onChange({ ...value, minutes: Math.max(0, Math.min(55, minutes + delta * 5)) });
    }
  };

  const toggleAuto = () => onChange({ ...value, auto: !auto });

  return (
    <div>
      <div className={`auto-toggle ${auto ? "active" : ""}`} onClick={toggleAuto}>
        <div className={`toggle-pill ${auto ? "on" : ""}`}>
          <div className="toggle-knob" />
        </div>
        <span className="toggle-text">{autoLabel}</span>
      </div>
      {!auto && (
        <div className="time-picker">
          <div className="time-unit">
            <span className="time-unit-label">Hours</span>
            <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
              <div className="time-btn-group">
                <button className="time-btn" onClick={() => update("hours", 1)}>↑</button>
                <button className="time-btn" onClick={() => update("hours", -1)}>↓</button>
              </div>
              <div className="time-display">{String(hours).padStart(2, "0")}</div>
            </div>
          </div>
          <div className="time-sep">:</div>
          <div className="time-unit">
            <span className="time-unit-label">Minutes</span>
            <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
              <div className="time-display">{String(minutes).padStart(2, "0")}</div>
              <div className="time-btn-group">
                <button className="time-btn" onClick={() => update("minutes", 1)}>↑</button>
                <button className="time-btn" onClick={() => update("minutes", -1)}>↓</button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default function LuniferSurvey() {
  const [step, setStep] = useState(0);
  const [answers, setAnswers] = useState({
    age: "",
    lifestyle: null,
    calendar: null,
    sleep: { hours: 8, minutes: 0, auto: false },
    routine: { hours: 1, minutes: 0, auto: false },
    commute: { hours: 0, minutes: 30, auto: false },
  });

  const totalSteps = 6;
  const canNext = () => {
    if (step === 0) return answers.age !== "" && Number(answers.age) > 0;
    if (step === 1) return answers.lifestyle !== null;
    if (step === 2) return answers.calendar !== null;
    return true;
  };

  return (
    <>
      <style>{styles}</style>
      <div className="survey-root">
        <div className="bg-glow bg-glow-1" />
        <div className="bg-glow bg-glow-2" />
        <div className="stars">
          {stars.map((s) => (
            <div key={s.id} className="star" style={{ top: s.top, left: s.left, width: s.size, height: s.size, "--dur": s.dur, "--delay": s.delay }} />
          ))}
        </div>

        {step < totalSteps && (
          <div className="card">
            <div className="step-indicator">
              {Array.from({ length: totalSteps }).map((_, i) => (
                <div key={i} className={`step-dot ${i === step ? "active" : i < step ? "done" : ""}`} />
              ))}
            </div>

            {step === 0 && (
              <>

                <h2 className="question-title" style={{ textAlign: "center" }}>How old are you?</h2>
                <div className="age-wrap">
                  <input
                    className="age-input"
                    type="number"
                    min="1"
                    max="120"
                    placeholder="—"
                    value={answers.age}
                    onChange={(e) => setAnswers({ ...answers, age: e.target.value })}
                  />
                </div>
              </>
            )}

            {step === 1 && (
              <>
                <h2 className="question-title">Which of these best describes you?</h2>
                <div style={{ display: "flex", flexDirection: "column", gap: 10, marginBottom: 36 }}>
                  {[
                    { id: "student", label: "I am a student" },
                    { id: "wfh", label: "I work from home" },
                    { id: "commuter", label: "I commute to work sometimes or most days" },
                    { id: "not_working", label: "I'm not working right now" },
                  ].map((opt) => (
                    <div
                      key={opt.id}
                      className={`cal-option ${answers.lifestyle === opt.id ? "selected" : ""}`}
                      style={{ gridColumn: "span 2" }}
                      onClick={() => setAnswers({ ...answers, lifestyle: opt.id })}
                    >
                      <span>{opt.label}</span>
                    </div>
                  ))}
                </div>
              </>
            )}

            {step === 2 && (
              <>

                <h2 className="question-title">Which calendar do you use?</h2>
                <p className="question-sub">Lunifer will sync with your calendar to automatically adapt your alarm around early meetings, late nights, and days off.</p>
                <div className="cal-grid">
                  {CALENDAR_APPS.map((app) => (
                    <div key={app.id} className={`cal-option ${answers.calendar === app.id ? "selected" : ""}`} onClick={() => setAnswers({ ...answers, calendar: app.id })}>
                      <span className="cal-icon">{app.icon}</span>
                      <span>{app.name}</span>
                    </div>
                  ))}
                </div>
              </>
            )}

            {step === 3 && (
              <>

                <h2 className="question-title">How long do you sleep to feel your best?</h2>
                <p className="question-sub">Lunifer will protect this number every night.</p>
                <TimeScalePicker value={answers.sleep} onChange={(v) => setAnswers({ ...answers, sleep: v })} autoLabel="I'm not sure — let Lunifer learn this" />
              </>
            )}

            {step === 4 && (
              <>

                <h2 className="question-title">How long does your morning routine take?</h2>
                <p className="question-sub">Shower, coffee, getting dressed — everything before you leave. Lunifer can trim this slightly when you're running late.</p>

                <TimeScalePicker value={answers.routine} onChange={(v) => setAnswers({ ...answers, routine: v })} autoLabel="Not sure — let Lunifer figure this out" />
              </>
            )}

            {step === 5 && (
              <>

                <h2 className="question-title">How long is your commute?</h2>
                <TimeScalePicker value={answers.commute} onChange={(v) => setAnswers({ ...answers, commute: v })} autoLabel="Let Lunifer calculate this from my location" />
              </>
            )}

            <button className="btn-next" onClick={() => setStep(step + 1)} disabled={!canNext()}>
              {step === totalSteps - 1 ? "Finish Setup →" : "Continue →"}
            </button>
            {step > 0 && <button className="btn-back" onClick={() => setStep(step - 1)}>← Back</button>}
          </div>
        )}
      </div>
    </>
  );
}

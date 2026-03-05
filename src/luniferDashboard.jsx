const styles = `
  @import url('https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,300;1,300&family=DM+Sans:wght@300;400;500&family=Roboto:wght@300&display=swap');
  * { box-sizing: border-box; margin: 0; padding: 0; }
  .dash-root {
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
  .dash-center {
    position: relative; z-index: 10;
    display: flex; flex-direction: column; align-items: center;
    animation: fadeSlideIn 0.6s ease forwards;
  }
  @keyframes fadeSlideIn { from { opacity: 0; transform: translateY(28px); } to { opacity: 1; transform: translateY(0); } }
  .dash-greeting {
    font-size: 12px;
    letter-spacing: 0.2em;
    text-transform: uppercase;
    color: rgba(160,120,255,0.6);
    margin-bottom: 36px;
    font-weight: 400;
  }
  .dash-alarm {
    font-family: 'Roboto', sans-serif;
    font-weight: 300;
    font-size: 96px;
    color: rgba(235,225,255,0.95);
    letter-spacing: -3px;
    line-height: 1;
    text-shadow: 0 0 80px rgba(160,100,255,0.25);
  }
  .dash-sublabel {
    margin-top: 18px;
    font-size: 13px;
    color: rgba(255,255,255,0.3);
    letter-spacing: 0.06em;
    font-weight: 300;
  }
`;

import { generateStars } from "./utils";

const starField = generateStars();

function getGreeting() {
  const h = new Date().getHours();
  if (h >= 5 && h < 12) return "Good morning";
  if (h >= 12 && h < 17) return "Good afternoon";
  if (h >= 17 && h < 22) return "Good evening";
  return "Good night";
}

// Calculates tonight's alarm: assumes first commitment at 9:00 AM,
// backs off by routine + commute. Returns "H:MM AM/PM" string.
function calcAlarm(answers) {
  const routineMin = answers.routine.auto ? 60 : answers.routine.hours * 60 + answers.routine.minutes;
  const commuteMin = answers.commute.auto ? 30 : answers.commute.hours * 60 + answers.commute.minutes;
  const bufferMin = routineMin + commuteMin;

  // 9:00 AM = 540 minutes from midnight
  const wakeMinutes = 540 - bufferMin;
  const h = Math.floor(((wakeMinutes % 1440) + 1440) % 1440 / 60);
  const m = ((wakeMinutes % 60) + 60) % 60;
  const ampm = h >= 12 ? "PM" : "AM";
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}:${String(m).padStart(2, "0")} ${ampm}`;
}

function getSleepLabel(answers) {
  if (answers.sleep.auto) return "learning your sleep pattern";
  const h = answers.sleep.hours;
  const m = answers.sleep.minutes;
  return `protecting ${h}h${m > 0 ? ` ${m}m` : ""} of sleep`;
}

export default function LuniferDashboard({ answers }) {
  const alarmTime = calcAlarm(answers);
  const sublabel = getSleepLabel(answers);

  return (
    <>
      <style>{styles}</style>
      <div className="dash-root">
        <div className="bg-glow bg-glow-1" />
        <div className="bg-glow bg-glow-2" />
        <div className="stars">
          {starField.map((s) => (
            <div key={s.id} className="star" style={{ top: s.top, left: s.left, width: s.size, height: s.size, "--dur": s.dur, "--delay": s.delay }} />
          ))}
        </div>

        <div className="dash-center">
          <p className="dash-greeting">{getGreeting()}</p>
          <div className="dash-alarm">{alarmTime}</div>
          <p className="dash-sublabel">{sublabel}</p>
        </div>
      </div>
    </>
  );
}

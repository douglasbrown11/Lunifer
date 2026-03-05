import { useState } from "react";
import { auth } from "./firebase";
import {
  createUserWithEmailAndPassword,
  signInWithEmailAndPassword,
  GoogleAuthProvider,
  signInWithPopup,
} from "firebase/auth";

const styles = `
  @import url('https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,300;0,400;1,300;1,400&family=DM+Sans:wght@300;400;500&display=swap');
  * { box-sizing: border-box; margin: 0; padding: 0; }
  .auth-root {
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

  .auth-card {
    position: relative; z-index: 10;
    width: 100%; max-width: 420px;
    padding: 52px 44px;
    animation: fadeSlideIn 0.5s ease forwards;
  }
  @keyframes fadeSlideIn { from { opacity: 0; transform: translateY(24px); } to { opacity: 1; transform: translateY(0); } }

  .auth-moon {
    font-size: 40px;
    display: block;
    text-align: center;
    margin-bottom: 20px;
    animation: float 3s ease-in-out infinite;
  }
  @keyframes float { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-8px); } }

  .auth-title {
    font-family: 'Cormorant Garamond', serif;
    font-size: 38px;
    font-weight: 300;
    color: rgba(255,255,255,0.95);
    text-align: center;
    margin-bottom: 6px;
  }

  .auth-subtitle {
    font-size: 14px;
    color: rgba(255,255,255,0.35);
    text-align: center;
    margin-bottom: 40px;
    line-height: 1.6;
  }

  .auth-input {
    width: 100%;
    padding: 14px 18px;
    border-radius: 12px;
    border: 1.5px solid rgba(255,255,255,0.08);
    background: rgba(255,255,255,0.04);
    color: rgba(255,255,255,0.9);
    font-family: 'DM Sans', sans-serif;
    font-size: 15px;
    outline: none;
    transition: all 0.2s ease;
    margin-bottom: 12px;
  }
  .auth-input::placeholder { color: rgba(255,255,255,0.25); }
  .auth-input:focus { border-color: rgba(160,120,255,0.6); background: rgba(160,120,255,0.06); }

  .btn-primary {
    width: 100%;
    padding: 15px;
    border-radius: 12px;
    border: none;
    background: linear-gradient(135deg, rgba(120,80,220,0.9), rgba(80,50,180,0.9));
    color: white;
    font-family: 'DM Sans', sans-serif;
    font-size: 15px;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.2s ease;
    margin-top: 4px;
  }
  .btn-primary:hover { transform: translateY(-1px); box-shadow: 0 8px 30px rgba(100,60,200,0.35); }
  .btn-primary:active { transform: translateY(0); }
  .btn-primary:disabled { opacity: 0.4; cursor: not-allowed; transform: none; box-shadow: none; }

  .divider {
    display: flex;
    align-items: center;
    gap: 12px;
    margin: 20px 0;
  }
  .divider-line { flex: 1; height: 1px; background: rgba(255,255,255,0.08); }
  .divider-text { font-size: 12px; color: rgba(255,255,255,0.25); letter-spacing: 0.05em; }

  .btn-google {
    width: 100%;
    padding: 14px;
    border-radius: 12px;
    border: 1.5px solid rgba(255,255,255,0.1);
    background: rgba(255,255,255,0.04);
    color: rgba(255,255,255,0.8);
    font-family: 'DM Sans', sans-serif;
    font-size: 15px;
    font-weight: 400;
    cursor: pointer;
    transition: all 0.2s ease;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
  }
  .btn-google:hover { border-color: rgba(255,255,255,0.2); background: rgba(255,255,255,0.07); color: white; }
  .btn-google:active { transform: scale(0.98); }

  .google-icon {
    width: 18px; height: 18px; flex-shrink: 0;
  }

  .toggle-mode {
    text-align: center;
    margin-top: 24px;
    font-size: 14px;
    color: rgba(255,255,255,0.3);
  }
  .toggle-mode span {
    color: rgba(160,120,255,0.9);
    cursor: pointer;
    transition: color 0.2s;
  }
  .toggle-mode span:hover { color: rgba(180,150,255,1); }

  .error-text {
    font-size: 13px;
    color: rgba(255,100,100,0.85);
    text-align: center;
    margin-bottom: 14px;
    padding: 10px 14px;
    border-radius: 8px;
    background: rgba(255,80,80,0.08);
    border: 1px solid rgba(255,80,80,0.15);
  }
`;

import { generateStars } from "./utils";

const stars = generateStars();

// Maps Firebase error codes to friendly messages
function getFriendlyError(code) {
  switch (code) {
    case "auth/email-already-in-use": return "An account with this email already exists.";
    case "auth/invalid-email": return "Please enter a valid email address.";
    case "auth/weak-password": return "Password must be at least 6 characters.";
    case "auth/user-not-found": return "No account found with this email.";
    case "auth/wrong-password": return "Incorrect password. Please try again.";
    case "auth/too-many-requests": return "Too many attempts. Please try again later.";
    case "auth/popup-closed-by-user": return "Sign in was cancelled.";
    default: return "Something went wrong. Please try again.";
  }
}

export default function LuniferAuth({ onSignedIn }) {
  const [mode, setMode] = useState("signin"); // "signin" or "create"
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const handleEmailAuth = async () => {
    setLoading(true);
    setError(null);
    try {
      if (mode === "create") {
        await createUserWithEmailAndPassword(auth, email, password);
      } else {
        await signInWithEmailAndPassword(auth, email, password);
      }
      onSignedIn(); // Tell parent component the user is signed in
    } catch (err) {
      setError(getFriendlyError(err.code));
    } finally {
      setLoading(false);
    }
  };

  const handleGoogle = async () => {
    setLoading(true);
    setError(null);
    try {
      const provider = new GoogleAuthProvider();
      await signInWithPopup(auth, provider);
      onSignedIn(); // Tell parent component the user is signed in
    } catch (err) {
      setError(getFriendlyError(err.code));
    } finally {
      setLoading(false);
    }
  };

  const canSubmit = email.length > 0 && password.length >= 6;

  return (
    <>
      <style>{styles}</style>
      <div className="auth-root">
        <div className="bg-glow bg-glow-1" />
        <div className="bg-glow bg-glow-2" />
        <div className="stars">
          {stars.map((s) => (
            <div key={s.id} className="star" style={{ top: s.top, left: s.left, width: s.size, height: s.size, "--dur": s.dur, "--delay": s.delay }} />
          ))}
        </div>

        <div className="auth-card">
          <span className="auth-moon">🌙</span>
          <h1 className="auth-title">Lunifer</h1>
          <p className="auth-subtitle">
            {mode === "signin" ? "Welcome back. Sleep is waiting." : "Create your account to get started."}
          </p>

          {error && <p className="error-text">{error}</p>}

          <input
            className="auth-input"
            type="email"
            placeholder="Email address"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
          <input
            className="auth-input"
            type="password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && canSubmit && handleEmailAuth()}
          />

          <button className="btn-primary" onClick={handleEmailAuth} disabled={!canSubmit || loading}>
            {loading ? "Please wait..." : mode === "signin" ? "Sign In" : "Create Account"}
          </button>

          <div className="divider">
            <div className="divider-line" />
            <span className="divider-text">or</span>
            <div className="divider-line" />
          </div>

          <button className="btn-google" onClick={handleGoogle} disabled={loading}>
            {/* Google SVG icon */}
            <svg className="google-icon" viewBox="0 0 24 24">
              <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
              <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
              <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l3.66-2.84z"/>
              <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
            </svg>
            Continue with Google
          </button>

          <div className="toggle-mode">
            {mode === "signin" ? (
              <>Don't have an account? <span onClick={() => { setMode("create"); setError(null); }}>Create one</span></>
            ) : (
              <>Already have an account? <span onClick={() => { setMode("signin"); setError(null); }}>Sign in</span></>
            )}
          </div>
        </div>
      </div>
    </>
  );
}

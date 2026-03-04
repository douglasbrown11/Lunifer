import { useState } from "react";
import LuniferOnboarding from "./luniferOnboarding";
import LuniferSurvey from "./luniferSurvey";

export default function App() {
  const [screen, setScreen] = useState("onboarding");

  if (screen === "onboarding") return <LuniferOnboarding onFinish={() => setScreen("survey")} />;
  if (screen === "survey") return <LuniferSurvey />;
}
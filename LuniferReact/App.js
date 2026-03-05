import { useState } from "react";
import LuniferIntro from "./luniferIntro";
import LuniferAuth from "./luniferAuth";
import LuniferSurvey from "./luniferSurvey";
import LuniferDashboard from "./luniferDashboard";

export default function App() {
  const [screen, setScreen] = useState("intro");
  const [surveyAnswers, setSurveyAnswers] = useState(null);

  if (screen === "intro") return <LuniferIntro onFinish={() => setScreen("auth")} />;
  if (screen === "auth") return <LuniferAuth onSignedIn={() => setScreen("survey")} />;
  if (screen === "survey") return <LuniferSurvey onFinish={(answers) => { setSurveyAnswers(answers); setScreen("dashboard"); }} />;
  if (screen === "dashboard") return <LuniferDashboard answers={surveyAnswers} />;
}

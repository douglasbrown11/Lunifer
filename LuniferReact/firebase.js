// ============================================
// LUNIFER FIREBASE CONFIG
// Initializes Firebase connection and exports
// the services Lunifer needs
// ============================================

import { initializeApp } from "firebase/app";
import { getFirestore } from "firebase/firestore";
import { getAuth } from "firebase/auth";
import { getAnalytics } from "firebase/analytics";

// Your Firebase project credentials
const firebaseConfig = {
  apiKey: "AIzaSyCkfQRzM5o2SxmK6L6gNCeORfR8GFPIN50",
  authDomain: "lunifer-ce086.firebaseapp.com",
  projectId: "lunifer-ce086",
  storageBucket: "lunifer-ce086.firebasestorage.app",
  messagingSenderId: "7167900619",
  appId: "1:7167900619:web:0c6d0d85bb97d9b7d4d44e",
  measurementId: "G-99V0MG866J"
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);

// Services Lunifer will use
export const db = getFirestore(app);   // Database — stores user profiles and survey answers
export const auth = getAuth(app);      // Authentication — handles user login
export const analytics = getAnalytics(app); // Analytics — tracks app usage

export default app;
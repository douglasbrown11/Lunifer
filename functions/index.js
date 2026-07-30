const {beforeUserDeleted} = require("firebase-functions/v2/identity");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

initializeApp();

exports.deleteUserData = beforeUserDeleted(async (event) => {
  // Wrapped in try/catch so a Firestore cleanup failure never blocks the
  // account deletion itself — a thrown error in a beforeUserDeleted blocking
  // function aborts the deletion. The client also performs a best-effort
  // cleanup, so swallowing errors here is safe.
  try {
    const userId = event.data.uid;
    const db = getFirestore();
    const userDoc = db.collection("users").doc(userId);

    // Every subcollection written under users/{uid}. `adaptiveData` holds the
    // bandit training outcomes (users/{uid}/adaptiveData/outcomes) and MUST be
    // listed here — deleting the parent doc does NOT remove subcollections.
    const subcollections = [
      "sleepHistory",
      "alarmInferences",
      "adaptiveData",
      "private",
    ];

    for (const sub of subcollections) {
      const snap = await userDoc.collection(sub).get();
      const deletes = snap.docs.map((doc) => doc.ref.delete());
      await Promise.all(deletes);
    }

    await userDoc.delete();
  } catch (err) {
    console.error("deleteUserData cleanup failed (deletion allowed):", err);
  }
});

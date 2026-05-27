const { beforeUserDeleted } = require("firebase-functions/v2/identity");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

initializeApp();

exports.deleteUserData = beforeUserDeleted(async (event) => {
    const userId = event.data.uid;
    const db = getFirestore();
    const userDoc = db.collection("users").doc(userId);

    const subcollections = ["sleepHistory", "alarmInferences", "private"];

    for (const sub of subcollections) {
        const snap = await userDoc.collection(sub).get();
        const deletes = snap.docs.map((doc) => doc.ref.delete());
        await Promise.all(deletes);
    }

    await userDoc.delete();
});
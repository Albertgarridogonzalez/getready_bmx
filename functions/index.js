// functions/index.js
const functions = require("firebase-functions/v2/https");
const { onRequest } = functions;
const admin = require("firebase-admin");
admin.initializeApp();

exports.ingestRfid = onRequest({ cors: true }, async (req, res) => {
  try {
    // Seguridad simple (cámbiala por algo tuyo)
    const key = req.get("x-ingest-key");
    if (key !== process.env.INGEST_KEY) return res.status(401).send("unauthorized");

    // Body esperado: { start_ts, deviceId, items: [{ epc, t_ms, rssi }] }
    const { start_ts, deviceId, items } = req.body || {};
    if (!Array.isArray(items) || !start_ts) return res.status(400).send("bad payload");

    const metaRef = admin.firestore().doc("meta/activeSession");
    const metaSnap = await metaRef.get();
    if (!metaSnap.exists) return res.status(404).send("no active session");

    const sessionId = metaSnap.get("id");
    const sessionRef = admin.firestore().doc(`sessions/${sessionId}`);
    const sessionSnap = await sessionRef.get();
    if (!sessionSnap.exists) return res.status(404).send("session not found");

    const session = sessionSnap.data();
    const pilots = Array.isArray(session.pilots) ? session.pilots : [];

    // Resolver EPC -> userId via rfidIndex (rápido). Si no existe, caer a users-by-rfid (más lento).
    const epcToUser = async (epc) => {
      const idxSnap = await admin.firestore().doc(`rfidIndex/${epc}`).get();
      if (idxSnap.exists) return idxSnap.data().userId;

      const usersSnap = await admin.firestore()
        .collection("users")
        .where("rfid", "==", epc)
        .limit(1).get();
      if (!usersSnap.empty) return usersSnap.docs[0].id;

      return null;
    };

    // Construir mapa userId -> tiempos a agregar
    const toAppend = {}; // { userId: [t_ms, ...] }
    for (const it of items) {
      const userId = await epcToUser(it.epc);
      if (!userId) continue;
      if (!toAppend[userId]) toAppend[userId] = [];
      toAppend[userId].push(Math.max(0, Math.floor(it.t_ms)));
    }

    // Aplicar los append en el array de cada piloto
    let changed = false;
    for (const [userId, times] of Object.entries(toAppend)) {
      const idx = pilots.findIndex((p) => p.id === userId);
      if (idx >= 0) {
        const cur = Array.isArray(pilots[idx].times) ? pilots[idx].times : [];
        pilots[idx].times = cur.concat(times);
        changed = true;
      }
    }

    if (changed) {
      await sessionRef.update({
        pilots,
        lastIngestAt: admin.firestore.FieldValue.serverTimestamp(),
        lastDeviceId: deviceId || null,
        lastStartTs: start_ts,
      });
    }

    return res.status(200).send({ ok: true, appended: Object.keys(toAppend).length });
  } catch (e) {
    console.error(e);
    return res.status(500).send("server error");
  }
});

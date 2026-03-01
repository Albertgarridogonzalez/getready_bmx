// functions/index.js
const functions = require("firebase-functions/v2/https");
const { onRequest } = functions;
const admin = require("firebase-admin");
admin.initializeApp();

exports.ingestRfid = onRequest({ cors: true }, async (req, res) => {
  try {
    const key = req.get("x-ingest-key");
    if (key !== process.env.INGEST_KEY) return res.status(401).send("unauthorized");

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

    const toAppend = {};
    for (const it of items) {
      const userId = await epcToUser(it.epc);
      if (!userId) continue;
      if (!toAppend[userId]) toAppend[userId] = [];
      toAppend[userId].push(Math.max(0, Math.floor(it.t_ms)));
    }

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

exports.bmxRaceTiming = onRequest({ cors: true }, async (req, res) => {
  try {
    const { rfid, t_ms, rssi, deviceId } = req.body || {};
    console.log(`📥 Recibido: RFID=${rfid}, T=${t_ms}, RSSI=${rssi}, Dev=${deviceId}`);

    if (!rfid || t_ms === undefined) {
      return res.status(400).send("Faltan datos (rfid o t_ms)");
    }

    // 1. Buscar Piloto por RFID
    let userId = null;
    let pilotName = "Desconocido";

    const idxRef = admin.firestore().doc(`rfidIndex/${rfid}`);
    const idxSnap = await idxRef.get();

    if (idxSnap.exists) {
      const data = idxSnap.data();
      userId = data.userId;
      pilotName = data.pilotName;
      console.log(`✅ Piloto encontrado en índice: ${pilotName} (${userId})`);
    } else {
      console.log(`🔍 RFID ${rfid} no en índice. Escaneando usuarios...`);
      const usersSnap = await admin.firestore().collection("users").get();
      let userDoc = null;

      for (const doc of usersSnap.docs) {
        const data = doc.data();
        // Verificar rfid directo o en array de pilotos
        if (data.rfid === rfid) {
          userDoc = doc;
          pilotName = data.pilotName || data.name || "Piloto";
          break;
        }
        if (Array.isArray(data.pilots)) {
          const p = data.pilots.find(x => x && x.rfid === rfid);
          if (p) {
            userDoc = doc;
            pilotName = p.name || data.pilotName || "Piloto";
            break;
          }
        }
      }

      if (userDoc) {
        userId = userDoc.id;
        await idxRef.set({
          userId: userId,
          pilotName: pilotName,
          rfid: rfid,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        console.log(`📝 Índice creado para ${pilotName}`);
      } else {
        console.warn(`❌ RFID ${rfid} no encontrado.`);
        return res.status(404).send(`Corredor con RFID ${rfid} no identificado`);
      }
    }

    // 2. Buscar Sesión Activa (Sin dependencias de índice compuesto)
    const sessionsQuery = await admin.firestore().collection("sessions")
      .where("location", "==", deviceId || "Mataró Gates")
      .limit(10)
      .get();

    const now = Date.now();
    const twentyFourHours = 24 * 60 * 60 * 1000;

    let sessionSnap = sessionsQuery.docs
      .map(d => ({ id: d.id, ref: d.ref, data: d.data() }))
      .filter(s => {
        const sDate = s.data.date ? (s.data.date.toDate ? s.data.date.toDate().getTime() : 0) : 0;
        return (now - sDate) < twentyFourHours;
      })
      .sort((a, b) => (b.data.date?.seconds || 0) - (a.data.date?.seconds || 0))[0];

    let sessionRef, sessionData;
    if (sessionSnap) {
      sessionRef = sessionSnap.ref;
      sessionData = sessionSnap.data;
      console.log(`📍 Sesión encontrada: ${sessionSnap.id}`);
    } else {
      console.log(`🆕 Nueva sesión automática para: ${deviceId || "Mataró Gates"}`);
      sessionData = {
        location: deviceId || "Mataró Gates",
        distance: 0,
        date: admin.firestore.FieldValue.serverTimestamp(),
        pilots: [],
        active: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      };
      sessionRef = await admin.firestore().collection("sessions").add(sessionData);
    }

    // 3. Actualizar Piloto en Sesión
    const pilots = Array.isArray(sessionData.pilots) ? sessionData.pilots : [];
    const pIdx = pilots.findIndex((p) => p.id === userId || p.id === `auto_${userId}`);

    if (pIdx < 0) {
      pilots.push({
        id: `auto_${userId}`,
        name: pilotName,
        times: [t_ms],
        active: true
      });
    } else {
      if (!Array.isArray(pilots[pIdx].times)) pilots[pIdx].times = [];
      pilots[pIdx].times.push(t_ms);
    }

    await sessionRef.update({
      pilots,
      lastIngestAt: admin.firestore.FieldValue.serverTimestamp(),
      lastDeviceId: deviceId || "unknown"
    });

    return res.status(200).send({ ok: true, pilot: pilotName, time_added: t_ms });

  } catch (error) {
    console.error("❌ Error en bmxRaceTiming:", error);
    return res.status(500).send("Error: " + error.message);
  }
});

exports.startBmxSession = onRequest({ cors: true }, async (req, res) => {
  try {
    const { deviceName } = req.body || {};
    if (!deviceName) return res.status(400).send("Falta deviceName");

    const db = admin.firestore();
    const now = Date.now();
    const twelveHours = 12 * 60 * 60 * 1000;

    // Buscar sesión reciente por dispositivo (sin índice compuesto)
    const sessionsQuery = await db.collection("sessions")
      .where("location", "==", deviceName)
      .limit(5)
      .get();

    const existingSession = sessionsQuery.docs
      .map(d => ({ id: d.id, ref: d.ref, data: d.data() }))
      .filter(s => {
        const sDate = s.data.date ? (s.data.date.toDate ? s.data.date.toDate().getTime() : 0) : 0;
        return (now - sDate) < twelveHours;
      })[0];

    if (existingSession) {
      console.log(`♻️ Reutilizando sesión: ${existingSession.id}`);
      // Asegurar que solo esta esté activa
      const allActive = await db.collection("sessions").where("active", "==", true).get();
      const batch = db.batch();
      for (const doc of allActive.docs) {
        if (doc.id !== existingSession.id) batch.update(doc.ref, { active: false });
      }
      batch.update(existingSession.ref, { active: true });
      await batch.commit();

      return res.status(200).send({ ok: true, sessionId: existingSession.id, message: "Sesión existente" });
    }

    console.log(`🆕 Creando nueva sesión para ${deviceName}`);
    const allActive = await db.collection("sessions").where("active", "==", true).get();
    const batch = db.batch();
    for (const doc of allActive.docs) batch.update(doc.ref, { active: false });
    await batch.commit();

    const newSessionRef = await db.collection("sessions").add({
      location: deviceName,
      distance: 0,
      date: admin.firestore.FieldValue.serverTimestamp(),
      pilots: [],
      active: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });

    return res.status(200).send({ ok: true, sessionId: newSessionRef.id });

  } catch (error) {
    console.error("❌ Error en startBmxSession:", error);
    return res.status(500).send("Error: " + error.message);
  }
});


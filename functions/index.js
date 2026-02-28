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
    const idxSnap = await admin.firestore().doc(`rfidIndex/${rfid}`).get();
    if (!idxSnap.exists) {
      console.warn(`⚠️ RFID no registrado: ${rfid}`);
      return res.status(404).send(`Corredor con RFID ${rfid} no identificado`);
    }

    const { userId, pilotName } = idxSnap.data();

    // 2. Buscar Sesión Activa o por nombre
    // Ahora usamos el deviceName enviado para buscar la sesión de hoy.
    // Si no se envía deviceName o no se encuentra la sesión, fall back a la sesión con active=true
    let sessionSnap = null;
    let sessionId = null;
    let sessionRef = null;

    if (deviceId) {
      // Buscar una sesión de hoy con este location (deviceName)
      const now = new Date();
      const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      const endOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);

      const sessionsQuery = await admin.firestore().collection("sessions")
        .where("location", "==", deviceId) // usamos el nombre configurado como location
        .where("date", ">=", startOfDay)
        .where("date", "<", endOfDay)
        .limit(1).get();

      if (!sessionsQuery.empty) {
        sessionSnap = sessionsQuery.docs[0];
        sessionId = sessionSnap.id;
        sessionRef = sessionSnap.ref;
      }
    }

    if (!sessionSnap) {
      // Intentar encontrar sesión activa global
      const activeSessionsQuery = await admin.firestore().collection("sessions")
        .where("active", "==", true).limit(1).get();
      if (!activeSessionsQuery.empty) {
        sessionSnap = activeSessionsQuery.docs[0];
        sessionId = sessionSnap.id;
        sessionRef = sessionSnap.ref;
      }
    }

    if (!sessionSnap) {
      return res.status(404).send("No hay ninguna sesión activa en el sistema para registrar el tiempo");
    }

    const session = sessionSnap.data();
    const pilots = Array.isArray(session.pilots) ? session.pilots : [];

    // 3. Buscar el piloto en la sesión
    const pIdx = pilots.findIndex((p) => p.id === userId || p.id.endsWith(`_${userId}`));

    if (pIdx < 0) {
      // NO RETORNAR 404, AÑADIR AUTOMATICAMENTE
      console.log(`El piloto ${pilotName} no estaba en la sesión. Añadiendo...`);
      pilots.push({
        id: `auto_${userId}`,
        name: pilotName,
        times: [t_ms],
        active: true
      });
    } else {
      // 4. Agregar el tiempo (ms)
      if (!Array.isArray(pilots[pIdx].times)) {
        pilots[pIdx].times = [];
      }
      pilots[pIdx].times.push(t_ms);
    }

    await sessionRef.update({
      pilots,
      lastIngestAt: admin.firestore.FieldValue.serverTimestamp(),
      lastDeviceId: deviceId || "unknown"
    });

    return res.status(200).send({
      ok: true,
      pilot: pilotName,
      time_added: t_ms
    });

  } catch (error) {
    console.error("❌ Error en bmxRaceTiming:", error);
    return res.status(500).send("Error interno del servidor");
  }
});

exports.startBmxSession = onRequest({ cors: true }, async (req, res) => {
  try {
    const { deviceName } = req.body || {};
    if (!deviceName) return res.status(400).send("Falta deviceName");

    const now = new Date();
    const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const endOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);

    const db = admin.firestore();

    // Buscar si ya existe hoy para este deviceName
    const sessionsQuery = await db.collection("sessions")
      .where("location", "==", deviceName)
      .where("date", ">=", startOfDay)
      .where("date", "<", endOfDay)
      .limit(1).get();

    if (!sessionsQuery.empty) {
      // Desactivar las demás y activar esta? 
      // Si la app usa 'active', la marcamos
      const sessionId = sessionsQuery.docs[0].id;

      const allActive = await db.collection("sessions").where("active", "==", true).get();
      const batch = db.batch();
      for (const doc of allActive.docs) {
        if (doc.id !== sessionId) {
          batch.update(doc.ref, { active: false });
        }
      }
      batch.update(sessionsQuery.docs[0].ref, { active: true });
      await batch.commit();

      return res.status(200).send({ ok: true, sessionId, message: "Sesión existente cargada" });
    }

    // Crear nueva
    const allActive = await db.collection("sessions").where("active", "==", true).get();
    const batch = db.batch();
    for (const doc of allActive.docs) {
      batch.update(doc.ref, { active: false });
    }
    await batch.commit();

    const newSessionRef = await db.collection("sessions").add({
      location: deviceName,
      distance: 0,
      date: admin.firestore.FieldValue.serverTimestamp(),
      pilots: [],
      active: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });

    return res.status(200).send({ ok: true, sessionId: newSessionRef.id, message: "Nueva sesión creada" });

  } catch (error) {
    console.error("❌ Error en startBmxSession:", error);
    return res.status(500).send("Error interno del servidor");
  }
});

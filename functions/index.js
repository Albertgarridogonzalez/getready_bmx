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

    const idxSnap = await admin.firestore().doc(`rfidIndex/${rfid}`).get();
    if (idxSnap.exists) {
      const data = idxSnap.data();
      userId = data.userId;
      pilotName = data.pilotName;
      console.log(`✅ Piloto encontrado en índice: ${pilotName} (${userId})`);
    } else {
      // Fallback: Buscar en la colección de usuarios
      console.log(`🔍 RFID ${rfid} no en índice. Buscando en todos los usuarios (dentro de pilots[])...`);
      const usersSnap = await admin.firestore().collection("users").get();

      let userDoc = null;
      for (const doc of usersSnap.docs) {
        const data = doc.data();
        // Tu esquema tiene el rfid dentro de users -> pilots[] -> rfid
        if (Array.isArray(data.pilots)) {
          const p = data.pilots.find(x => x.rfid === rfid);
          if (p) {
            userDoc = doc;
            pilotName = p.name || data.pilotName || "Piloto";
            break;
          }
        }
        // Por si acaso estuviera fuera
        if (data.rfid === rfid) {
          userDoc = doc;
          pilotName = data.pilotName || data.name || "Piloto";
          break;
        }
      }

      if (userDoc) {
        userId = userDoc.id;
        console.log(`✅ Usuario encontrado en DB: ${userId} (${pilotName})`);

        // Crear el índice para la próxima vez
        await admin.firestore().doc(`rfidIndex/${rfid}`).set({
          userId: userId,
          pilotName: pilotName,
          rfid: rfid,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        console.log(`📝 Índice rfidIndex/${rfid} creado para ${pilotName}`);
      } else {
        console.warn(`❌ RFID ${rfid} no encontrado en ningún usuario (ni en el array de pilotos).`);
        return res.status(404).send(`Corredor con RFID ${rfid} no identificado en la base de datos de pilotos`);
      }
    }

    // 2. Buscar Sesión Activa o por nombre
    let sessionSnap = null;
    let sessionId = null;
    let sessionRef = null;

    if (deviceId) {
      const now = new Date();
      // Buscamos sesiones en las últimas 24 horas para este dispositivo
      const yesterday = new Date(now.getTime() - (24 * 60 * 60 * 1000));

      const sessionsQuery = await admin.firestore().collection("sessions")
        .where("location", "==", deviceId)
        .where("date", ">=", yesterday)
        .limit(1).get();

      if (!sessionsQuery.empty) {
        sessionSnap = sessionsQuery.docs[0];
        sessionId = sessionSnap.id;
        sessionRef = sessionSnap.ref;
        console.log(`📍 Sesión encontrada por ubicación (${deviceId}): ${sessionId}`);
      }
    }

    let sessionData = null;
    if (sessionSnap) {
      sessionData = sessionSnap.data();
    } else {
      console.log(`🆕 No hay sesión activa. Creando sesión de emergencia para: ${deviceId || "Mataró Gates"}`);
      sessionData = {
        location: deviceId || "Mataró Gates",
        distance: 0,
        date: admin.firestore.FieldValue.serverTimestamp(),
        pilots: [],
        active: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      };
      sessionRef = await admin.firestore().collection("sessions").add(sessionData);
      sessionId = sessionRef.id;
    }

    const pilots = Array.isArray(sessionData.pilots) ? sessionData.pilots : [];

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

    // Buscar si ya existe recientemente para este deviceName (últimas 12 horas)
    const twelveHoursAgo = new Date(now.getTime() - (12 * 60 * 60 * 1000));

    const sessionsQuery = await db.collection("sessions")
      .where("location", "==", deviceName)
      .where("date", ">=", twelveHoursAgo)
      .limit(1).get();

    if (!sessionsQuery.empty) {
      const sessionId = sessionsQuery.docs[0].id;
      console.log(`♻️ Reutilizando sesión: ${sessionId}`);

      // Desactivar las demás y activar esta
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

    console.log(`🆕 Creando nueva sesión para ${deviceName}`);
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

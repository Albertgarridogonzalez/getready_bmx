// functions/index.js
const functions = require("firebase-functions/v2/https");
const { onRequest } = functions;
const admin = require("firebase-admin");
admin.initializeApp();

exports.ingestRfid = onRequest({ cors: true }, async (req, res) => {
  try {
    const { deviceId, items } = req.body || {};
    const location = deviceId || "Mataró Gates";

    console.log(`📥 Ingest Masiva: ${items?.length} items desde ${location}`);
    if (!Array.isArray(items) || items.length === 0) {
      return res.status(400).send("Faltan items o formato incorrecto");
    }

    // 1. Buscar o Crear Sesión (Lógica idéntica a bmxRaceTiming)
    const sessionsQuery = await admin.firestore().collection("sessions")
      .where("location", "==", location)
      .limit(10).get();

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
    } else {
      sessionData = {
        location: location,
        distance: 0,
        date: admin.firestore.FieldValue.serverTimestamp(),
        pilots: [],
        active: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      };
      sessionRef = await admin.firestore().collection("sessions").add(sessionData);
    }

    const pilotsInSession = Array.isArray(sessionData.pilots) ? sessionData.pilots : [];

    // 2. Procesar cada item del lote
    for (const item of items) {
      const { epc, t_ms } = item;
      if (!epc || t_ms === undefined) continue;

      // Buscar Piloto por los últimos 6 dígitos
      const rfid6 = epc.length >= 6 ? epc.slice(-6).toUpperCase() : epc.toUpperCase();
      let userId = null;
      let pilotName = "Desconocido";
      const idxRef = admin.firestore().doc(`rfidIndex/${rfid6}`);
      const idxSnap = await idxRef.get();

      if (idxSnap.exists) {
        const d = idxSnap.data();
        userId = d.userId;
        pilotName = d.pilotName;
      } else {
        const usersSnap = await admin.firestore().collection("users").get();
        let userDoc = null;
        for (const doc of usersSnap.docs) {
          const data = doc.data();
          if (data.rfid && data.rfid.toUpperCase() === rfid6) { userDoc = doc; pilotName = data.pilotName || data.name || "Piloto"; break; }
          if (Array.isArray(data.pilots)) {
            const p = data.pilots.find(x => x && x.rfid && x.rfid.toUpperCase() === rfid6);
            if (p) { userDoc = doc; pilotName = p.name || data.pilotName || "Piloto"; break; }
          }
        }
        if (userDoc) {
          userId = userDoc.id;
          await idxRef.set({ userId, pilotName, rfid: rfid6, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
        }
      }

      if (!userId) continue;

      // Actualizar en array de pilotos de la sesión
      // BUG FIX: Diferenciar pilotos del mismo padre por nombre
      let pIdx = pilotsInSession.findIndex(p => 
        (p.id === userId || p.id === `auto_${userId}` || p.id === `auto_${userId}_${pilotName.replace(/\s+/g, '_')}`) && 
        p.name === pilotName
      );

      if (pIdx < 0) {
        // Crear un ID único para el piloto (Padre + Nombre)
        const pilotId = `auto_${userId}_${pilotName.replace(/\s+/g, '_')}`;
        pilotsInSession.push({ id: pilotId, name: pilotName, times: [t_ms], active: true });
      } else {
        if (!Array.isArray(pilotsInSession[pIdx].times)) pilotsInSession[pIdx].times = [];
        pilotsInSession[pIdx].times.push(t_ms);
        pilotsInSession[pIdx].name = pilotName;
      }

      // 3. Actualizar Leaderboard (Ranking)
      const docId = location.toLowerCase().trim().replace(/\s+/g, '_');
      const leaderboardRef = admin.firestore().collection("leaderboards").doc(docId);
      try {
        await admin.firestore().runTransaction(async (transaction) => {
          const lbSnap = await transaction.get(leaderboardRef);
          let records = lbSnap.exists ? (lbSnap.data().records || []) : [];
          const rIdx = records.findIndex(r => r.name === pilotName);
          if (rIdx >= 0) {
            if (t_ms < records[rIdx].time) {
              records[rIdx].time = t_ms;
              records[rIdx].updatedAt = Date.now();
            } else return;
          } else {
            records.push({ name: pilotName, time: t_ms, updatedAt: Date.now() });
          }
          records.sort((a, b) => a.time - b.time);
          if (records.length > 20) records = records.slice(0, 20);
          transaction.set(leaderboardRef, { location, records, lastUpdate: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
        });
      } catch (e) { console.error("Error Leaderboard batch:", e); }
    }

    // 4. Guardar Sesión una sola vez
    await sessionRef.update({
      pilots: pilotsInSession,
      lastIngestAt: admin.firestore.FieldValue.serverTimestamp(),
      lastDeviceId: location
    });

    return res.status(200).send({ ok: true, processed: items.length });
  } catch (e) {
    console.error("Error ingestRfid:", e);
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

    // 1. Buscar Piloto por los últimos 6 dígitos del RFID
    let userId = null;
    let pilotName = "Desconocido";
    const rfid6 = rfid.length >= 6 ? rfid.slice(-6).toUpperCase() : rfid.toUpperCase();

    const idxRef = admin.firestore().doc(`rfidIndex/${rfid6}`);
    const idxSnap = await idxRef.get();

    if (idxSnap.exists) {
      const data = idxSnap.data();
      userId = data.userId;
      pilotName = data.pilotName;
      console.log(`✅ Piloto encontrado en índice: ${pilotName} (${userId})`);
    } else {
      console.log(`🔍 RFID ${rfid6} no en índice. Escaneando usuarios...`);
      const usersSnap = await admin.firestore().collection("users").get();
      let userDoc = null;

      for (const doc of usersSnap.docs) {
        const data = doc.data();
        // Verificar rfid directo o en array de pilotos
        if (data.rfid && data.rfid.toUpperCase() === rfid6) {
          userDoc = doc;
          pilotName = data.pilotName || data.name || "Piloto";
          break;
        }
        if (Array.isArray(data.pilots)) {
          const p = data.pilots.find(x => x && x.rfid && x.rfid.toUpperCase() === rfid6);
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
          rfid: rfid6,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        console.log(`📝 Índice creado para ${pilotName}`);
      } else {
        console.warn(`❌ RFID ${rfid6} no encontrado.`);
        return res.status(404).send(`Corredor con RFID ${rfid6} no identificado`);
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

    // BUG FIX: Diferenciar pilotos del mismo padre por nombre
    // Buscamos concordancia de ID Y de nombre
    let pIdx = pilots.findIndex((p) => 
      (p.id === userId || p.id === `auto_${userId}` || p.id === `auto_${userId}_${pilotName.replace(/\s+/g, '_')}`) && 
      p.name === pilotName
    );

    if (pIdx < 0) {
      // Si no se encuentra con la combinación exacta, creamos uno nuevo único
      const newId = `auto_${userId}_${pilotName.replace(/\s+/g, '_')}`;
      pilots.push({
        id: newId,
        name: pilotName,
        times: [t_ms],
        active: true
      });
    } else {
      // Si se encuentra, añadimos el tiempo
      if (!Array.isArray(pilots[pIdx].times)) pilots[pIdx].times = [];
      pilots[pIdx].times.push(t_ms);
      pilots[pIdx].name = pilotName;
    }

    await sessionRef.update({
      pilots,
      lastIngestAt: admin.firestore.FieldValue.serverTimestamp(),
      lastDeviceId: deviceId || "unknown"
    });

    // 4. Actualizar Leaderboard (Ranking Histórico)
    const location = deviceId || "Mataró Gates";
    const docId = location.toLowerCase().trim().replace(/\s+/g, '_');
    console.log(`🏆 Intentando actualizar leaderboard: ${docId} (Pista: ${location})`);

    const leaderboardRef = admin.firestore().collection("leaderboards").doc(docId);

    try {
      await admin.firestore().runTransaction(async (transaction) => {
        const lbSnap = await transaction.get(leaderboardRef);
        let records = [];

        if (lbSnap.exists) {
          records = lbSnap.data().records || [];
          console.log(`📊 Leaderboard existente encontrado con ${records.length} registros`);
        } else {
          console.log(`🆕 Creando nuevo leaderboard para ${docId}`);
        }

        const rIdx = records.findIndex(r => r.name === pilotName);
        if (rIdx >= 0) {
          if (t_ms < records[rIdx].time) {
            console.log(`⭐ ¡Nuevo récord personal para ${pilotName}! ${records[rIdx].time} -> ${t_ms}`);
            records[rIdx].time = t_ms;
            records[rIdx].updatedAt = Date.now();
          } else {
            console.log(`ℹ️ El tiempo ${t_ms} no supera el récord de ${pilotName} (${records[rIdx].time})`);
            return;
          }
        } else {
          console.log(`➕ Añadiendo primer registro para ${pilotName} con ${t_ms}ms`);
          records.push({
            name: pilotName,
            time: t_ms,
            updatedAt: Date.now()
          });
        }

        records.sort((a, b) => a.time - b.time);
        if (records.length > 20) records = records.slice(0, 20);

        transaction.set(leaderboardRef, {
          location: location,
          records: records,
          lastUpdate: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });
        console.log(`✅ Leaderboard ${docId} actualizado con éxito.`);
      });
    } catch (lbError) {
      console.error("❌ Error actualizando leaderboard:", lbError);
    }

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


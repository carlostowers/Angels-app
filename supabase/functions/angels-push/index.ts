// Angels - envio de avisos por Web Push.
// Nunca se borra nada: un telefono que ya no acepta avisos se marca
// (failures = 1000) y deja de recibir; si el jugador vuelve a activar los
// avisos en ese telefono, la marca se limpia sola.
// Formas de llamarla:
//  1. pg_cron cada 15 minutos, con el encabezado x-cron-secret:
//     a) avisos del check-in a los jugadores (angels.reminders_due()).
//     b) avisos para el staff (angels.staff_alerts_due()): resumen de cada
//        sesion, seguimiento de quien sigue sin check-in y alertas de salud
//        sin nombre ni detalle.
//  2. El jugador desde la app ({ test_token }): prueba a sus telefonos.
//  3. El staff desde la app ({ staff_test: true }, con su sesion): prueba a
//     los telefonos del staff.
//  4. { public_key: true }: la llave publica para suscribirse.
//  5. Mensajes del coach (v3):
//     a) cron angels-mensajes cada 5 minutos ({ mensajes: true } con el
//        x-cron-secret): envia los programados vencidos.
//     b) el staff desde la app ({ send_message: id }, con su sesion): envio
//        inmediato del mensaje que acaba de crear.
//     Cada mensaje se toma primero en la base (staff_message_claim /
//     staff_messages_claim_due): nunca sale dos veces.
// Las llaves VAPID se generan aqui la primera vez y se guardan en
// angels.push_config (solo service_role). Nunca salen del servidor.
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const db = createClient(SUPABASE_URL, SERVICE_KEY, {
  db: { schema: "angels" },
  auth: { persistSession: false, autoRefreshToken: false },
});

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status: status,
    headers: Object.assign({ "Content-Type": "application/json" }, CORS),
  });
}

type Config = { vapid_public: string; vapid_private: string; cron_secret: string };
let config: Config | null = null;

async function loadConfig(): Promise<Config> {
  if (config) return config;
  const r = await db.from("push_config").select("vapid_public,vapid_private,cron_secret").eq("id", 1).single();
  if (r.error || !r.data) throw new Error("Sin configuracion de push");
  let row = r.data as Config;
  if (!row.vapid_public || !row.vapid_private) {
    const keys = webpush.generateVAPIDKeys();
    const up = await db.from("push_config")
      .update({ vapid_public: keys.publicKey, vapid_private: keys.privateKey, updated_at: new Date().toISOString() })
      .eq("id", 1).is("vapid_private", null)
      .select("vapid_public,vapid_private,cron_secret");
    if (up.data && up.data.length) {
      row = up.data[0] as Config;
    } else {
      const again = await db.from("push_config").select("vapid_public,vapid_private,cron_secret").eq("id", 1).single();
      row = again.data as Config;
    }
  }
  webpush.setVapidDetails("https://angelsapp.thegriit.com", row.vapid_public, row.vapid_private);
  config = row;
  return row;
}

// Marca de telefono que ya no acepta avisos.
const MUERTA = 1000;

type Sub = { id: number; endpoint: string; p256dh: string; auth: string; failures: number };

// Envia a una lista de suscripciones de la tabla indicada. Las muertas se marcan.
async function sendToSubs(table: string, subs: Sub[], payload: Record<string, string>): Promise<number> {
  let delivered = 0;
  for (const s of subs) {
    try {
      await webpush.sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
        JSON.stringify(payload),
        { TTL: 6 * 3600, urgency: "high" },
      );
      delivered++;
      await db.from(table).update({ last_ok_at: new Date().toISOString(), failures: 0 }).eq("id", s.id);
    } catch (e) {
      const code = (e && (e as { statusCode?: number }).statusCode) || 0;
      if (code === 404 || code === 410) {
        // El telefono ya no acepta avisos (desinstalo o quito el permiso).
        await db.from(table).update({ failures: MUERTA }).eq("id", s.id);
      } else {
        await db.from(table).update({ failures: (s.failures || 0) + 1 }).eq("id", s.id);
        console.error("push fallo", table, code, String((e as Error).message || e).slice(0, 200));
      }
    }
  }
  return delivered;
}

async function sendToPlayer(playerId: string, payload: Record<string, string>): Promise<number> {
  const subs = await db.from("push_subscriptions").select("id,endpoint,p256dh,auth,failures").eq("player_id", playerId).lt("failures", MUERTA);
  return sendToSubs("push_subscriptions", (subs.data || []) as Sub[], payload);
}

async function sendToStaff(payload: Record<string, string>): Promise<number> {
  const subs = await db.from("staff_push_subscriptions").select("id,endpoint,p256dh,auth,failures").lt("failures", MUERTA);
  return sendToSubs("staff_push_subscriptions", (subs.data || []) as Sub[], payload);
}

type Msg = { id: number; body: string; target: string; copy_staff: boolean };

// Envia un mensaje del coach a sus jugadores (y al staff si toca) y deja
// el resultado en staff_messages.
async function enviaMensaje(m: Msg): Promise<{ jugadores: number; telefonos: number; staff: number }> {
  let jugadores = 0, telefonos = 0, staff = 0, objetivo = 0;
  try {
    if (m.target !== "coach") {
      const rec = await db.rpc("message_recipients", { p_id: m.id });
      if (rec.error) throw rec.error;
      const lista = (rec.data || []) as { player_id: string; access_token: string }[];
      objetivo = lista.length;
      for (const r of lista) {
        const n = await sendToPlayer(r.player_id, {
          title: "Angels · Coach",
          body: m.body,
          url: "/?t=" + r.access_token + "&go=mensajes",
          tag: "coach-" + m.id,
        });
        telefonos += n;
        if (n > 0) jugadores++;
      }
    }
    if (m.target === "coach" || m.copy_staff) {
      staff = await sendToStaff({ title: "Angels · Coach", body: m.body, url: "/?go=mensajes", tag: "coach-" + m.id });
    }
  } catch (e) {
    console.error("mensaje", m.id, String((e as Error).message || e).slice(0, 300));
  } finally {
    await db.from("staff_messages").update({
      status: "enviado", sent_at: new Date().toISOString(),
      targeted: objetivo, recipients: jugadores, delivered: telefonos, staff_delivered: staff,
    }).eq("id", m.id);
  }
  return { jugadores: jugadores, telefonos: telefonos, staff: staff };
}

// La sesion del staff llega en Authorization. Se confirma el usuario y que
// su email este en staff_users.
async function staffFromRequest(req: Request): Promise<string | null> {
  const h = req.headers.get("authorization") || "";
  const jwt = h.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) return null;
  const u = await db.auth.getUser(jwt);
  const email = (u.data && u.data.user && u.data.user.email) ? u.data.user.email.toLowerCase() : "";
  if (!email) return null;
  const s = await db.from("staff_users").select("email").eq("email", email).maybeSingle();
  return s.data ? email : null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const cfg = await loadConfig();
    let body: Record<string, unknown> = {};
    try { body = await req.json(); } catch (_e) { body = {}; }

    // 1. Cron
    const secret = req.headers.get("x-cron-secret");
    if (secret && secret === cfg.cron_secret && body.mensajes === true) {
      const due = await db.rpc("staff_messages_claim_due");
      if (due.error) throw due.error;
      let n = 0;
      for (const m of (due.data || []) as Msg[]) { await enviaMensaje(m); n++; }
      return json({ ok: true, mensajes: n });
    }
    if (secret && secret === cfg.cron_secret) {
      // a) Jugadores
      const due = await db.rpc("reminders_due");
      if (due.error) throw due.error;
      let enviados = 0;
      for (const row of (due.data || [])) {
        // Primero se registra el intento: si algo falla a mitad, no se repite.
        const ins = await db.from("reminder_log")
          .insert({ player_id: row.player_id, session_date: row.session_date, attempt: row.attempt })
          .select("id").single();
        if (ins.error) continue;
        const n = await sendToPlayer(row.player_id, {
          title: "Angels",
          body: row.body,
          url: "/?t=" + row.access_token + "&go=checkin",
          tag: "checkin-" + row.session_date,
        });
        await db.from("reminder_log").update({ delivered: n }).eq("id", ins.data.id);
        if (n > 0) enviados++;
      }

      // b) Staff
      let staff = 0;
      try {
        const sd = await db.rpc("staff_alerts_due");
        if (sd.error) throw sd.error;
        for (const a of (sd.data || [])) {
          const ins = await db.from("staff_alert_log").insert({ key: a.key, kind: a.kind, body: a.body }).select("key").single();
          if (ins.error) continue;
          const n = await sendToStaff({
            title: a.kind === "salud" ? "Angels · Revisar" : "Angels · Staff",
            body: a.body,
            url: "/",
            tag: a.key,
          });
          await db.from("staff_alert_log").update({ delivered: n }).eq("key", a.key);
          if (n > 0) staff++;
        }
      } catch (e) {
        console.error("staff alerts", String((e as Error).message || e).slice(0, 300));
      }
      return json({ ok: true, candidatos: (due.data || []).length, enviados: enviados, staff: staff });
    }

    // 2. Prueba desde el telefono del jugador
    const token = typeof body.test_token === "string" ? body.test_token : "";
    if (token.length >= 32) {
      const p = await db.from("players").select("id,access_token,status").eq("access_token", token).maybeSingle();
      if (!p.data) return json({ ok: false, error: "Enlace no valido" }, 403);
      const n = await sendToPlayer(p.data.id, {
        title: "Angels",
        body: "Así te van a llegar los recordatorios del check-in.",
        url: "/?t=" + p.data.access_token,
        tag: "prueba",
      });
      return json({ ok: true, delivered: n });
    }

    // 3. Prueba del staff
    if (body.staff_test === true) {
      const email = await staffFromRequest(req);
      if (!email) return json({ ok: false, error: "Solo staff" }, 403);
      const n = await sendToStaff({
        title: "Angels · Staff",
        body: "Así te van a llegar los resúmenes de práctica y las alertas.",
        url: "/",
        tag: "prueba-staff",
      });
      return json({ ok: true, delivered: n });
    }

    // 5b. Mensaje del coach, envio inmediato
    if (typeof body.send_message === "number") {
      const email = await staffFromRequest(req);
      if (!email) return json({ ok: false, error: "Solo staff" }, 403);
      const c = await db.rpc("staff_message_claim", { p_id: body.send_message });
      if (c.error) throw c.error;
      const m = ((c.data || []) as Msg[])[0];
      if (!m) return json({ ok: false, error: "Ese mensaje ya salio o todavia no le toca" }, 409);
      const r = await enviaMensaje(m);
      return json({ ok: true, jugadores: r.jugadores, telefonos: r.telefonos, staff: r.staff });
    }

    // 4. Llave publica (no es secreta): la app la pide para suscribirse.
    if (body.public_key === true) {
      return json({ ok: true, public_key: cfg.vapid_public });
    }

    return json({ ok: false, error: "No autorizado" }, 401);
  } catch (e) {
    console.error("angels-push", String((e as Error).message || e).slice(0, 300));
    return json({ ok: false, error: "Error del servidor" }, 500);
  }
});

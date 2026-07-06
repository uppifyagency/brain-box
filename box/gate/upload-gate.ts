// upload-gate — l'ingresso file del brain (SPIKE-S1: file_upload di gbrain è localOnly).
// POST /upload?dept=<reparto>  body = file binario (stream)
//   header: Authorization: Bearer <token dipendente>  ·  X-Filename: <nome>  ·  X-Employee: <chi>
// Valida il token CHIAMANDO GBRAIN (una sola fonte di verità: 401 da gbrain = 401 qui),
// poi scrive in /inbox/<reparto>/ + sidecar .meta.json (provenance). Da lì pipeline 09/10.
import { mkdirSync, renameSync, existsSync, unlinkSync } from "fs";

const PORT = Number(process.env.GATE_PORT || 3134);
const GBRAIN = process.env.GBRAIN_URL || "http://gbrain:3131";
const DEPTS = (process.env.DELERA_DEPTS || "generale").trim().split(/\s+/);
const MAX_BYTES = Number(process.env.GATE_MAX_MB || 200) * 1024 * 1024;

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

// nome file sicuro: solo basename, niente dotfile, charset ristretto
function safeName(raw: string | null): string | null {
  if (!raw) return null;
  const base = raw.split(/[\\/]/).pop()!.trim();
  if (!base || base.startsWith(".")) return null;
  const clean = base.replace(/[^\w.\- àèéìòùÀÈÉÌÒÙ]/g, "_");
  return clean.length > 1 && clean.length < 200 ? clean : null;
}

// il token è valido se gbrain NON risponde 401/403 a una richiesta MCP autenticata
async function tokenOk(auth: string): Promise<boolean> {
  const r = await fetch(`${GBRAIN}/mcp`, {
    method: "POST",
    headers: { authorization: auth, "content-type": "application/json", accept: "application/json, text/event-stream" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "ping" }),
  });
  return r.status !== 401 && r.status !== 403;
}

Bun.serve({
  port: PORT,
  hostname: "0.0.0.0",
  maxRequestBodySize: MAX_BYTES,
  async fetch(req) {
    const url = new URL(req.url);
    if (req.method === "GET" && url.pathname === "/health") return json(200, { ok: true });
    // /status: JSON per il dashboard live (scritto da ops/status-collector.sh sull'host,
    // bind-mount ro). SOLO tailnet (serve, MAI funnel). CORS aperto: il dashboard è un
    // file locale (origin null) e i dati sono già protetti dalla rete.
    if (req.method === "GET" && url.pathname === "/status") {
      const f = Bun.file("/status/status.json");
      if (!(await f.exists())) return json(503, { error: "collector non ancora attivo" });
      return new Response(f, { headers: { "content-type": "application/json", "access-control-allow-origin": "*", "cache-control": "no-store" } });
    }
    if (req.method !== "POST" || url.pathname !== "/upload") return json(404, { error: "not found" });

    const auth = req.headers.get("authorization");
    if (!auth) return json(401, { error: "manca Authorization: Bearer <token>" });
    try {
      if (!(await tokenOk(auth))) return json(401, { error: "token non valido o revocato" });
    } catch {
      return json(502, { error: "gbrain non raggiungibile, riprova" });
    }

    const dept = url.searchParams.get("dept") || "";
    if (!DEPTS.includes(dept)) return json(400, { error: `reparto sconosciuto: "${dept}"`, reparti: DEPTS });

    const fname = safeName(req.headers.get("x-filename"));
    if (!fname) return json(400, { error: "manca o non è valido X-Filename" });

    const len = Number(req.headers.get("content-length") || 0);
    if (len > MAX_BYTES) return json(413, { error: `file oltre il cap (${MAX_BYTES / 1024 / 1024}MB): usa inbox/ via scp` });

    const dir = `/inbox/${dept}`;
    mkdirSync(dir, { recursive: true });
    const staging = `${dir}/.staging-${crypto.randomUUID()}`;
    try {
      const written = await Bun.write(staging, req);   // streaming: niente file in RAM
      const meta = {
        employee: req.headers.get("x-employee") || null,
        uploaded_at: new Date().toISOString(),
        size_bytes: written,
        // provenance verificabile senza custodire il token in chiaro
        token_hint: new Bun.CryptoHasher("sha256").update(auth).digest("hex").slice(0, 12),
      };
      await Bun.write(`${dir}/${fname}.meta.json`, JSON.stringify(meta));
      renameSync(staging, `${dir}/${fname}`);          // atomico: l'ingest non vede file a metà
      return json(200, { status: "accepted", path: `${dept}/${fname}`, size_bytes: written });
    } catch (e) {
      if (existsSync(staging)) try { unlinkSync(staging); } catch {}
      return json(500, { error: `scrittura fallita: ${e instanceof Error ? e.message : e}` });
    }
  },
});

console.log(`upload-gate su :${PORT} → inbox per reparti: ${DEPTS.join(", ")} (cap ${MAX_BYTES / 1024 / 1024}MB)`);

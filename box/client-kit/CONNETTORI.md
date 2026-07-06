# Connettori — come ogni agente si collega al brain

Prerequisito: token personale coniato dall'admin (`./client-kit/register-employee.sh <nome>`),
URL base del box (es. `https://box.<tailnet>.ts.net`). Il dispositivo deve stare nel tailnet
aziendale — TRANNE claude.ai, che richiede `expose: public` (Funnel), vedi GO-LIVE.md.

## Claude Code (validato in 10)
```bash
claude mcp add brain --transport http "https://<box>/mcp" \
  --header "Authorization: Bearer <token>"
```

## claude.ai — web, desktop, telefono (richiede expose: public)
Settings → Connectors → Add custom connector → URL: `https://<box>/mcp`.
gbrain espone OAuth 2.1: il login avviene nel browser (flusso validato in 09 via SSE).
Per un accesso READ-ONLY vero (consulenti): l'admin crea un client OAuth con scope `read`.

## Codex CLI (da validare — M2/S2)
In `~/.codex/config.toml`:
```toml
[mcp_servers.brain]
url = "https://<box>/mcp"
http_headers = { "Authorization" = "Bearer <token>" }
```

## Gemini CLI (da validare — M2)
In `~/.gemini/settings.json`:
```json
{ "mcpServers": { "brain": {
    "httpUrl": "https://<box>/mcp",
    "headers": { "Authorization": "Bearer <token>" } } } }
```

## Cosa può fare l'agente una volta collegato
`search` / `query` (risposte con citazioni `[reparto:pagina]`) · `get_page` · `put_page`
(scrive: il server marca la provenienza col token) · `graph-query`. Il perimetro dei
reparti lo decide il token, non l'agente.

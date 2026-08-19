# Atlassian Data Center ops

Minimální ops repo pro práci s **self-hosted Jira Data Center a Confluence
Data Center** z Claude Code. Všechno jde přes MCP server
[mcp-atlassian](https://github.com/sooperset/mcp-atlassian); repo drží jen to,
co MCP neumí — dokázat, že přístup funguje, a připnout specifikaci API.

Změřená fakta a pasti Data Center jsou ve skillu `atlassian-dc`, který si Claude
načte sám.

## Nastavení

```bash
cp .env.example .env && chmod 600 .env             # doplň URL a tokeny
cp .mcp.example.json .mcp.json                     # nahraď cestu k .env absolutní cestou
cp config/pins.example.json config/pins.json       # doplň verze své instance
bin/atl-check                                      # musí dát rc=0
bin/atl-spec fetch                                 # stáhne OpenAPI specifikace
```

`.mcp.json` nemá `--enabled-tools` schválně — všech 98 nástrojů je k dispozici.
Ruční allowlist se neudržuje, protože tichá absence nástroje je horší než širší
kontext (zjištěno dvakrát tvrdě: vyřazený nástroj vedl k tomu, že se jeho funkce
znovu postavila ručně).

Personal Access Token si vytvoř ve webovém UI (v DC má povinnou expiraci):
`<JIRA_URL>/secure/ViewProfile.jspa` a
`<CONFLUENCE_URL>/users/viewmyprofile.action` → *Personal access tokens*.

Po změně `.env` nebo `.mcp.json` restartuj Claude Code. `rc=2` z `atl-check`
znamená, že se nic neověřilo — **není to úspěch**.

## Příkazy

```bash
bin/atl-check                                  # přístup, verze, shoda s config/pins.json
bin/atl-spec fetch                             # stáhne specifikace, ověří sha256
bin/atl-spec jira createmeta                   # dotaz do specifikace
bin/atl-spec jira --show '/api/2/serverInfo'
```

Proměnné: `ATL_TIMEOUT` (default 30 s), `ATL_ENV_FILE`.

## Co se necommituje

`.env` (tokeny), `config/pins.json` (verze instance), `spec/` (specifikace jsou
Atlassianova díla — repo drží jen URL a sha256), `probe/`.

## Oficiální `acli` tady nefunguje

Je Cloud-only: jede nad `/rest/api/3`, které Data Center nemá. Ověřeno probem
i Atlassianovou vlastní specifikací (0 cest pod `/api/3`, 252 pod `/api/2`).

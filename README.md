# E.ON Atlassian ops

Pracoviště pro Jira Data Center (https://track.eon.cz, v10.3.23) a Confluence
Data Center (https://dory.eon.cz, v9.2.22). Hlavní projekt
[AIC](https://track.eon.cz/projects/AIC).

## Obnova po expiraci PAT

Jediná věc, která se tady opakuje. PAT má v Data Center povinnou expiraci
(default 90 dní); až vyprší, začne všechno vracet 401.

1. Nový token: [Jira](https://track.eon.cz/secure/ViewProfile.jspa) →
   *Personal access tokens*, [Confluence](https://dory.eon.cz/users/viewmyprofile.action)
   → *Personal access tokens*
2. Přepiš `JIRA_PERSONAL_TOKEN` / `CONFLUENCE_PERSONAL_TOKEN` v `.env`
3. `bin/atl-auth-check` — musí dát `rc=0`
4. Restart Claude Code (MCP čte `.env` při startu)

`rc=2` znamená, že se nic neověřilo, protože chybí token. To není úspěch.

## Práce

**MCP `atlassian-eon` je default** — 23 nástrojů, čtení i zápis pro obě
instance, včetně metadat schématu. V Claude Code prostě řekni, co chceš.

**REST obálky** jen na to, co MCP neumí: `serverInfo`, `remotelink`, CSV export,
`totalSize` z Confluence, bulk a přesné payloady.

```bash
bin/jira-api GET /issue/AIC-1
bin/jira-api GET '/search?jql=project=AIC&maxResults=0' | jq .total
bin/jira-api GET @agile/board          # prefix @agile/ přepne na Agile API
bin/conf-api GET '/space?limit=100&expand=homepage'
```

Proměnné: `ATL_TIMEOUT` (default 30 s), `ATL_ENV_FILE`.

Postupy a odchylky Data Center drží skill `eon-atlassian` — Claude si ho načte
sám.

## Struktura

```
.mcp.json                    MCP atlassian-eon, allowlist 23 nástrojů
.env / .env.example          tokeny (gitignored, 600) / šablona
bin/atl-auth-check           ověření PAT proti oběma instancím
bin/jira-api / bin/conf-api  REST klienti
bin/_common.sh               auth + atl_curl (token mimo argv, kontrola statusu)
.claude/skills/eon-atlassian/  skill + reference odchylek DC
```

## Dvě věci, na které se naráží

**Oficiální Atlassian `acli` tady nefunguje** — je Cloud-only, jede nad
`/rest/api/3`, které Data Center nemá. Nainstalovaný je, nepoužívej ho.

**Zápisy nebyly nikdy ověřené.** Čtení ano, proti oběma instancím. Zápis
(zakládání, komentáře, přechody stavů, stránky) je zatím jen návrh.

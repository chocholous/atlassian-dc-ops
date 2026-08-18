# E.ON Atlassian ops

Jira Data Center [track.eon.cz](https://track.eon.cz) (10.3.23) a Confluence
Data Center [dory.eon.cz](https://dory.eon.cz) (9.2.22), projekt
[AIC](https://track.eon.cz/projects/AIC). Práce jde přes MCP `atlassian-eon`;
fakta a pasti drží skill `eon-atlassian`, který si Claude načte sám.

## Obnova po expiraci PAT

Jediné, co se tady opakuje — PAT má v Data Center povinnou expiraci.

1. Nový token: [Jira](https://track.eon.cz/secure/ViewProfile.jspa) a
   [Confluence](https://dory.eon.cz/users/viewmyprofile.action) → *Personal access tokens*
2. Přepiš `JIRA_PERSONAL_TOKEN` / `CONFLUENCE_PERSONAL_TOKEN` v `.env`
3. `bin/atl-check` — musí dát `rc=0` (`rc=2` znamená, že se nic neověřilo)
4. Restart Claude Code

## Příkazy

```bash
bin/atl-check                                  # přístup, verze, shoda s config/pins.json
bin/atl-spec fetch                             # stáhne OpenAPI specifikace, ověří sha256
bin/atl-spec jira createmeta                   # dotaz do specifikace
bin/atl-spec jira --show '/api/2/serverInfo'
```

Proměnné: `ATL_TIMEOUT` (default 30 s), `ATL_ENV_FILE`.

Specifikace se necommitují (Atlassianova díla) — jdou do gitignorovaného `spec/`,
repo drží jen URL, verzi a sha256 v `config/pins.json`.

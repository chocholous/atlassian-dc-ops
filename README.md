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
3. `bin/atl-check` — musí dát `rc=0`
4. Restart Claude Code (MCP čte `.env` při startu)

`rc=2` znamená, že se nic neověřilo, protože chybí token. To není úspěch.

## Práce

**Všechno jde přes MCP `atlassian-eon`** — čtení i zápis pro obě instance.
V Claude Code prostě řekni, co chceš. Seznam nástrojů je v `.mcp.json`.

**`bin/atl-check`** ověří přístup, vypíše verze obou instancí a porovná je
s `config/pins.json`. Existuje proto, že MCP se hlásí jako „connected" i
s prázdnými tokeny a selže až první volání.

**`bin/atl-spec`** drží připnutou OpenAPI specifikaci obou API — autoritativní
tvar každého endpointu, místo hádání:

```bash
bin/atl-spec fetch                 # stáhne a ověří sha256 podle pinů
bin/atl-spec jira createmeta       # které cesty existují a jaké metody mají
bin/atl-spec conf 'content/.*child'
bin/atl-spec jira --show '/api/2/serverInfo'   # celý popis jedné cesty
```

Specifikace se **necommitují** — jsou to Atlassianova díla. Repo drží jen URL,
verzi a sha256 v `config/pins.json`; soubory jdou do gitignorovaného `spec/`.

**Piny:** Confluence má specifikaci pro naši přesnou verzi (9.2.22). Jira ne —
Atlassian publikuje jen řadu 10.0.x, takže připnutá je **10.0.5**, zatímco
instance běží 10.3.23. Jádro `/rest/api/2` je stabilní, ale novější endpointy
v tom specu chybět mohou. `bin/atl-check` hlásí drift, kdyby se instance
bumpnula pod rukama.

Na ad-hoc dotaz nebo smyčku použij curl přímo — ale **token posílej na stdin,
nikdy přes `-H`**, protože argumenty procesu čte každý lokální proces přes `ps`:

```bash
set -a; . .env; set +a
printf 'header = "Authorization: Bearer %s"\n' "$JIRA_PERSONAL_TOKEN" \
  | curl -sS -K - --fail-with-body "$JIRA_URL/rest/api/2/serverInfo" | jq .
```

Nikdy k tomu nepřidávej `-v`, `-sv`, `--trace` ani `--libcurl` — vypsaly by token.

Proměnné: `ATL_TIMEOUT` (default 30 s), `ATL_ENV_FILE`.

Postupy a odchylky Data Center drží skill `eon-atlassian` — Claude si ho načte
sám.

## Struktura

```
.mcp.json                    MCP atlassian-eon, allowlist 23 nástrojů
.env / .env.example          tokeny (gitignored, 600) / šablona
bin/atl-check                ověření přístupu, verzí a shody s piny
bin/atl-spec                 připnutá OpenAPI specifikace: stažení a dotazy
config/pins.json             verze instancí, API basey, URL a sha256 specifikací
spec/                        stažené specifikace (gitignorované)
.claude/skills/eon-atlassian/  skill + reference odchylek DC
```

## Pozor

**Oficiální Atlassian `acli` tady nefunguje** — je Cloud-only. Nainstalovaný je,
nepoužívej ho.

**Zápisy nebyly nikdy ověřené.** Čtení ano, proti oběma instancím.

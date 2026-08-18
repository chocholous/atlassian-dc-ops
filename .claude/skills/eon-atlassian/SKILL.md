---
name: eon-atlassian
description: Práce s E.ON Jira Data Center (track.eon.cz) a Confluence Data Center (dory.eon.cz) — issues, JQL, sprinty, boardy, stránky, CQL, komentáře. Použij vždy, když jde o E.ON Jiru nebo Confluence, o projekt AIC, o ticket ve tvaru AIC-123, o odkaz na track.eon.cz nebo dory.eon.cz, nebo když se řeší autentizace, PAT tokeny či REST API těchto instancí. NEPOUŽÍVEJ pro Atlassian Cloud (*.atlassian.net) — tam platí jiné API a jiný nástroj.
---

# E.ON Atlassian Data Center

Všechno jde přes MCP `atlassian-eon` (98 nástrojů). Tokeny jsou v `.env`
(gitignored) — **nikdy je nevypisuj** do transkriptu, commitů ani souborů.

## Fakta

Změřeno 2026-08-18 proti živým instancím. Kde je fakt neověřený, je to napsané.

| | |
|---|---|
| Jira | **10.3.23**, API `/rest/api/2`, Agile `/rest/agile/1.0` |
| Confluence | **9.2.22**, API `/rest/api` (ne `/wiki/rest/api` jako Cloud) |
| Hlavní projekt | **AIC** — dnes 1 issue (Epic AIC-1), boardy 1372 a 1373, 0 komponent, 0 verzí |
| `/rest/api/3` | **neexistuje** (302 na login); spec má 0 cest pod `/api/3`, 252 pod `/api/2` |
| Confluence `serverInfo` | **neexistuje** (404); verze jen z `/rest/applinks/1.0/manifest` |
| `createmeta` v Jiře 10 | `/issue/createmeta/{key}/issuetypes/{typeId}`; starý `?projectKeys=` dává 404 |
| Epic | vyžaduje `customfield_10002` (Epic Name), jinak 400 |
| Ostatní typy | povinné jen `summary`, `issuetype`, `reporter`, `project`; Sub-task navíc `parent` |
| Globální seznamy lžou | `/priority` má 27 hodnot, ale AIC/Task jen 5 → ber `allowedValues` z `jira_get_create_fields` |
| `jira_search` | vrací `total` přímo v odpovědi |
| `confluence_search` | strop 50, **nestránkuje**, počet nevrací → při 50 výsledcích říkej „nejméně 50" |
| `jira_get_comments` | **neexistuje**; komentáře přes `jira_get_issue` + `comment_limit`. Neověřeno — AIC nemá ani jeden komentář, absenci klíče `comments` neber za „issue je nemá" |
| `expand="changelog"` | v odpovědi je klíč **`changelogs`** (množné číslo) |
| Náš token | běžný uživatel, ne admin. **65 čtecích cest vrací 403**: schémata, skupiny, `application-properties`, `monitoring`, `cluster`, `audit`, `backup-restore`, `webhooks`, `screens`, `settings`, `upgrade`. 403 není chyba konfigurace, je to odpověď |
| 404 rozlišuj podle **těla** | `{"message":"HTTP 404 Not Found","sub-code":-1}` = endpoint chybí; `errorMessages` nebo konkrétní věta = endpoint je, chybí objekt. Kontrast 403 vs 404 spolehlivý **není** |
| `required` u query parametrů | ve specu prakticky nepoužitý (Jira 2 %, Confluence 0 %) — nevěř mu. Při 400 doplň sémanticky zřejmý parametr (`username`, `cql`, `query`, `projectKey`) |
| Confluence + špatný typ id | vrací **500**, ne 400 — chyba je na vstupu |
| Připnuté specifikace | Jira **10.0.5** (Atlassian publikuje jen řadu `.0.x`; platí pro 10.3.23, ověřeno 117/117 cest), Confluence **9.2.22** přesně. Nepokrývají plugin API (`/rest/pat/latest`, `/rest/applinks/1.0`) — když spec cestu nezná a instance ji přijme, **věř instanci** |
| Těžké endpointy | `/api/2/worklog/deleted` a `/updated` (chybí `since`), `/rest/api/label/recent` (chybí `limit`) — bez parametrů timeout |
| MCP „connected" | **není důkaz** — server startuje i s prázdnými tokeny a selže až první volání |
| PAT | povinná expirace → náhlé 401 napříč vším je vypršelý token, ne rozbitá konfigurace |
| Destruktivní nástroje | `jira_delete_issue`, `confluence_delete_page`, `confluence_delete_attachment`, `jira_remove_issue_link`, `jira_remove_watcher` |
| `acli` | Cloud-only, proti těmto instancím nefunguje (je nainstalovaný) |
| Zápisy | **nikdy neproběhly** — zakládání, komentář, přechod stavu, stránka. První zápis každého druhu je první běh |

## Příkazy

```bash
bin/atl-check                                  # přístup, verze, shoda s piny; rc=2 není úspěch
bin/atl-spec fetch                             # stáhne specifikace, ověří sha256
bin/atl-spec jira createmeta                   # které cesty existují + metody
bin/atl-spec jira --show '/api/2/serverInfo'   # parametry a odpovědi
bin/atl-spec conf 'content/.*child'
```

Vzor je case-insensitive regex. Jira cesty jsou relativní k `/rest` (`/api/2/…`),
Confluence je už obsahují (`/rest/api/…`).

Endpoint mimo MCP (smyčka, bulk, `remotelink`, CSV export) — **token na stdin,
nikdy přes `-H`**, a nikdy `-v`/`-sv`/`--trace*`/`--libcurl`:

```bash
set -a; . .env; set +a
printf 'header = "Authorization: Bearer %s"\n' "$JIRA_PERSONAL_TOKEN" \
  | curl -sS -K - --fail-with-body -H "Accept: application/json" \
    "$JIRA_URL/rest/api/2/issue/AIC-1/remotelink" | jq .
```

## Zápisy

Před **každým** zápisem vypiš přesné volání se všemi parametry (u Confluence i `id`,
`title`, `space`, `version`) a čekej na potvrzení v chatu; souhlas platí na jedno
volání, ne na dávku. Po zápisu objekt přečti zpět a cituj změněnou hodnotu —
prázdná odpověď ani `rc=0` nejsou důkaz.

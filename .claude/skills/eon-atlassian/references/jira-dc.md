# Jira Data Center — REST API v2

Base: `https://track.eon.cz/rest/api/2` · Agile: `/rest/agile/1.0`
Auth: `Authorization: Bearer <PAT>`

Přes `bin/jira-api <METODA> <cesta>` se base připojuje automaticky;
prefix `@agile/` přepne na Agile API.

## Čtení

```bash
# Kdo jsem
bin/jira-api GET /myself

# Verze a typ nasazení
bin/jira-api GET /serverInfo

# Konkrétní issue
bin/jira-api GET /issue/AIC-1
bin/jira-api GET '/issue/AIC-1?fields=summary,status,assignee,description'

# Metadata projektu
bin/jira-api GET /project/AIC
bin/jira-api GET /project/AIC/statuses      # typy úkolů + jejich stavy
bin/jira-api GET /field                     # všechna pole včetně customfield_*
```

## Hledání (JQL)

```bash
bin/jira-api GET '/search?jql=project=AIC+AND+statusCategory!=Done&maxResults=50'
bin/jira-api GET '/search?jql=project=AIC+AND+assignee=currentUser()&fields=key,summary,status'
bin/jira-api GET '/search?jql=project=AIC+AND+updated>=-7d+ORDER+BY+updated+DESC'
```

**Stránkování je past.** `/search` má default `maxResults` (typicky 50) a
odpověď obsahuje `total`, `startAt`, `maxResults`. Než řekneš „víc jich není",
přečti `total`:

```bash
bin/jira-api GET '/search?jql=project=AIC&maxResults=0' | jq '.total'
```

Další stránka: `&startAt=50`. Pro velké výběry iteruj, dokud
`startAt + maxResults < total`.

JQL v URL musí být URL-encoded. Mezery jako `+` nebo `%20`, uvozovky jako `%22`.
Pro složitější JQL je bezpečnější POST:

```bash
bin/jira-api POST /search -d '{"jql":"project = AIC AND text ~ \"hledaný výraz\"","maxResults":50,"fields":["key","summary","status"]}'
```

## Zápis — vyžaduje potvrzení uživatele

```bash
# Založení issue. Typy v AIC jsou anglické (Task/Sub-task/Story/Bug/Epic),
# ale id je jednoznačné a nezávislé na přejmenování.
# Epic vyžaduje navíc customfield_10002 (Epic Name).
# Skutečná id vezmi z config/instances.json (vyplní bin/atl-discover):
jq -r '.jira.issue_types[] | "\(.id)\t\(.name)"' config/instances.json

bin/jira-api POST /issue -d '{
  "fields": {
    "project": {"key": "AIC"},
    "summary": "Souhrn",
    "description": "Popis",
    "issuetype": {"id": "ZDE_ID_Z_CONFIGU"}
  }
}'

# Komentář
bin/jira-api POST /issue/AIC-1/comment -d '{"body":"Text komentáře"}'

# Úprava polí
bin/jira-api PUT /issue/AIC-1 -d '{"fields":{"summary":"Nový souhrn"}}'

# Přechod stavu — nejdřív zjisti dostupné přechody
bin/jira-api GET /issue/AIC-1/transitions | jq '.transitions[] | {id, name}'
# id přechodu je per-workflow, NIKDY ho nehádej — vezmi ho z výpisu výše
bin/jira-api POST /issue/AIC-1/transitions -d '{"transition":{"id":"ZDE_ID_Z_VYPISU"}}'
```

`PUT /issue` a `POST /transitions` vracejí **204 bez těla** při úspěchu.
Prázdná odpověď tady tedy znamená úspěch — ale ověř si to čtením issue zpět.

## Endpointy, které MCP nemá

```bash
# Historie změn — nutná pro cycle/lead time a pro "co se změnilo za noc".
# MCP nástroj na tohle není, jira_batch_get_changelogs je Cloud-only.
bin/jira-api GET '/issue/AIC-1?expand=changelog' | jq '.changelog.histories[]
  | {created, author: .author.name, items: [.items[] | {field, fromString, toString}]}'

# Odkazy na Confluence stránky NEJSOU v issuelinks, ale tady:
bin/jira-api GET /issue/AIC-1/remotelink

# Povinná pole obrazovky pro zakládání — bez toho první POST spadne na 400.
# Jira 10 zrušila tvar s ?projectKeys= (404), platné je toto:
bin/jira-api GET '/issue/createmeta/AIC/issuetypes'
bin/jira-api GET '/issue/createmeta/AIC/issuetypes/10003' \
  | jq '[.values[] | select(.required) | .fieldId]'

# CSV export celého výběru (není REST, je to view — vrací CSV, ne JSON)
#   /sr/jira.issueviews:searchrequest-csv-all-fields/temp/SearchRequest.csv?jqlQuery=<JQL>
```

`config/instances.json` má z `bin/atl-discover` předpočítané `required_fields`
per typ úkolu, takže createmeta nemusíš volat při každém zakládání.

## Agile (boardy, sprinty)

```bash
bin/jira-api GET @agile/board
bin/jira-api GET '@agile/board?projectKeyOrId=AIC'
bin/jira-api GET @agile/board/123/sprint
bin/jira-api GET '@agile/sprint/456/issue?maxResults=100'
```

## Časté chyby

| Symptom | Příčina |
|---|---|
| 302 na `/login.jsp` | použil jsi `/rest/api/3` — na DC neexistuje |
| 401 napříč vším | vypršelý PAT (default expirace 90 dní) |
| 403 s platným tokenem | chybí oprávnění v projektu, token je OK |
| 400 při zakládání Epicu | chybí `customfield_10002` (Epic Name) |
| 404 na `/issue/createmeta?projectKeys=` | Jira 10 tvar zrušila, viz výše |
| Chybí očekávané issues | default `maxResults` ticho zkrátil výsledek |

## Míra ověření

Ověřeno proti `track.eon.cz` s platným tokenem (2026-08-18): Jira **10.3.23**,
`/myself`, `/serverInfo`, `/search` (včetně `maxResults=0` → `total`),
`/project/AIC/statuses`, `/field`, `/issue/createmeta/AIC/issuetypes[/{id}]`,
`@agile/board` — všechno 200. `/rest/api/3` **neexistuje** (302 na login).
**Zápisové endpointy ověřeny NEBYLY** (`POST /issue`, `/comment`,
`/transitions`, `PUT /issue`) — payloady jsou z dokumentace. Id typů úkolů
a customfieldů v příkladech vezmi z `config/instances.json`, ne odsud.

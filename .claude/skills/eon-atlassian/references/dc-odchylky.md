# Odchylky Data Center — co v dokumentaci Atlassianu nenajdeš

Jen věci, které se nedají uhodnout z obecné znalosti API nebo které jsou
specifické pro tyhle instance. Payloady a JQL syntaxi si dohledej u Atlassianu
nebo je nech na MCP nástrojích, které mají vlastní schémata.

## API se liší od Cloudu

| | Data Center | Cloud (neplatí tady) |
|---|---|---|
| Jira | `/rest/api/2`, `/rest/api/latest` | `/rest/api/3` — **na DC vrací 302 na login** |
| Confluence | `/rest/api` | `/wiki/rest/api` |
| Auth | `Authorization: Bearer <PAT>` | e-mail + API token |

`bin/jira-api` připojuje base sám; prefix `@agile/` přepne na `/rest/agile/1.0`.

## Jira 10 zrušila starý createmeta

```bash
# 404 — tenhle tvar v Jiře 10 neexistuje
/issue/createmeta?projectKeys=AIC

# platné:
/issue/createmeta/AIC/issuetypes
/issue/createmeta/AIC/issuetypes/{typeId}
```

Přes MCP je to `jira_get_create_fields(project_key, issue_type_id)` — kratší
cesta a vrací `allowedValues`.

## Globální seznamy nejsou pravda o projektu

`/priority` vrací **27** hodnot a `/resolution` **13** za celou instanci,
`/field` má **326** polí. Pro AIC/Task platí **14 polí a 5 priorit**. Vždy ber
`allowedValues` z `jira_get_create_fields`, nikdy z globálního endpointu.

**Epic vyžaduje `customfield_10002` (Epic Name)**, jinak `POST` spadne na 400.
Ostatní typy vyžadují jen `summary`, `issuetype`, `reporter`, `project`;
Sub-task navíc `parent`.

`components` a `versions` jsou v AIC prázdné — pole existují, hodnoty ne.

## Počty: čtyři různé limity

| Zdroj | Default | Jak získat celkový počet |
|---|---|---|
| MCP `jira_search` | 10 (popis říká max 50) | vrací `total` přímo v odpovědi |
| MCP `confluence_search` | 10, **strop 50** | `totalSize` NEVRACÍ → musíš přes REST |
| REST Jira `/search` | 50 | `&maxResults=0` → `.total` |
| REST Confluence | 25 | `/search?limit=1` → `.totalSize` (`/content/search` vrací jen `size`) |

## Endpointy, které MCP nemá

```bash
bin/jira-api GET /serverInfo
bin/jira-api GET /issue/AIC-1/remotelink     # odkazy na Confluence NEJSOU v issuelinks
bin/conf-api GET '/search?cql=type=page&limit=1'   # kvůli totalSize
# CSV export celého výběru (vrací CSV, ne JSON):
#   /sr/jira.issueviews:searchrequest-csv-all-fields/temp/SearchRequest.csv?jqlQuery=<JQL>
```

Historii změn MCP **umí**: `jira_get_issue` s `expand="changelog"`.

## Confluence: zápis

Tělo je **storage XHTML**, ne Markdown. `PUT /content/{id}` přepíše **celé**
tělo (není to patch) a vyžaduje `version.number` o 1 vyšší, jinak 409.

Preferuj `confluence_update_page_section` — mění jen sekci pod nadpisem a nechá
zbytek včetně maker na pokoji. Cíl pro nové stránky je `homepage_id` space
(`/space?expand=homepage`).

## Provozní pasti

- **PAT má povinnou expiraci.** Náhlé 401 napříč vším = vypršelý token, ne
  rozbitá konfigurace. `bin/atl-auth-check`.
- **Oficiální `acli` je Cloud-only** a proti těmto instancím nefunguje, i když
  je nainstalovaný.
- **`--toolsets` s neplatným jménem shodí MCP na 0 nástrojů**, tiše. Proto je
  v `.mcp.json` explicitní `--enabled-tools`.
- **MCP nastartuje i s prázdnými tokeny** a Claude Code ho ohlásí jako
  connected. Selže až první volání.
- **`-v` je v `bin/*-api` zakázané** — vypsalo by token na výstup.

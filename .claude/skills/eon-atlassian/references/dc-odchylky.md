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

Agile API (boardy, sprinty) je pod `/rest/agile/1.0` — ale to všechno pokrývá MCP
(`jira_get_agile_boards`, `jira_get_sprints_from_board`, `jira_get_sprint_issues`).

Potvrzeno dvěma nezávislými zdroji: probe instance vrací na `/rest/api/3` 302,
a Atlassianova vlastní specifikace pro DC má **0 cest** pod `/api/3` a 252 pod
`/api/2` (`bin/atl-spec jira '^/api/3'`).

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

## Počty a limity

| Zdroj | Default | Strop | Celkový počet |
|---|---|---|---|
| `jira_search` | 10 | 50 | **vrací `total`** — u Jiry počet znáš |
| `confluence_search` | 10 | 50 | **nevrací nic a NEUMÍ stránkovat** |

U Confluence to znamená: přes 50 výsledků se nedostaneš a jejich počet nezjistíš.
Když dostaneš 50, řekni „nejméně 50" — ne „to je všechno". Znát číslo by nepomohlo,
protože zbytek stejně nevytáhneš.

Kdybys opravdu potřeboval projít víc, je to REST se stránkováním
(`/rest/api/search?cql=…&limit=50&start=N`) — tedy smyčka, viz recept níž.

## Endpointy, které MCP nemá — a jak k nim bezpečně

V repu nejsou žádné obálky. Volej curl přímo, ale **token posílej na stdin**:
argumenty procesu čte každý lokální proces přes `ps`, takže
`-H "Authorization: Bearer …"` token vystaví (změřeno).

```bash
set -a; . .env; set +a

q() {   # q <url> — GET s tokenem mimo argv
  printf 'header = "Authorization: Bearer %s"\n' "$JIRA_PERSONAL_TOKEN" \
    | curl -sS -K - --fail-with-body -H "Accept: application/json" "$1"
}

q "$JIRA_URL/rest/api/2/issue/AIC-1/remotelink"   # odkazy na Confluence NEJSOU v issuelinks
q "$JIRA_URL/rest/api/2/serverInfo"                # verzi hlásí i bin/atl-check
```

**Nikdy nepřidávej `-v`, `-sv`, `--trace*` ani `--libcurl`** — vypsaly by
hlavičku Authorization, tedy token, na výstup nebo do souboru.

Confluence má verzi jen v applinks manifestu, tedy pod jiným basem než
`/rest/api`: `"$CONFLUENCE_URL/rest/applinks/1.0/manifest"`. `serverInfo` na
Confluence **neexistuje** (404).

CSV export celého výběru (vrací CSV, ne JSON):
`/sr/jira.issueviews:searchrequest-csv-all-fields/temp/SearchRequest.csv?jqlQuery=<JQL>`

Historii změn MCP **umí**: `jira_get_issue` s `expand="changelog"`.

## Confluence: zápis

Tělo je **storage XHTML**, ne Markdown. `PUT /content/{id}` přepíše **celé**
tělo (není to patch) a vyžaduje `version.number` o 1 vyšší, jinak 409.

Preferuj `confluence_update_page_section` — mění jen sekci pod nadpisem a nechá
zbytek včetně maker na pokoji. Cíl pro nové stránky je `homepage_id` space
(`/space?expand=homepage`).

## Provozní pasti

- **PAT má povinnou expiraci.** Náhlé 401 napříč vším = vypršelý token, ne
  rozbitá konfigurace. Ověř `bin/atl-check`.
- **Oficiální `acli` je Cloud-only** a proti těmto instancím nefunguje, i když
  je nainstalovaný.
- **`--toolsets` s neplatným jménem shodí MCP na 0 nástrojů**, tiše. Proto je
  v `.mcp.json` explicitní `--enabled-tools`.
- **MCP nastartuje i s prázdnými tokeny** a Claude Code ho ohlásí jako
  connected. Selže až první volání.
- **`-v` je v `bin/*-api` zakázané** — vypsalo by token na výstup.

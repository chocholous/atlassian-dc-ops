# Volba nástrojů — co bylo měřeno a proč to tak je

Datum: 2026-08-18.

**Rozsah ověření (aktualizováno 2026-08-18 po vložení tokenů).**

Ověřeno ostře proti živým instancím: auth na obou (`bin/atl-auth-check` → `rc=0`),
Jira **10.3.23**, Confluence **9.2.22**, discovery všech metadat
(`bin/atl-discover` → 5 typů úkolů, 2 boardy, 6 spaces, povinná pole per typ),
čtení přes REST (`/search` + `total`), čtení přes MCP (`jira_search`,
`confluence_search` → 18 nástrojů, obojí 200), a `jira-cli` (`init` + objemný
výpis). Dále změřeno: počty MCP nástrojů, chování skriptů (rc, timeout, únik
tokenu do `ps`).

**NEOVĚŘENO: veškerý ZÁPIS.** Zakládání issue, komentář, přechod stavu, zápis
a úprava Confluence stránky nebyly zkoušeny — payloady jsou z dokumentace.

**Dvě tvrzení, která živá data vyvrátila:**

1. „Jira je česky, zakládání podle jména typu úkolu selhává" — **REFUTED**.
   Typy v AIC jsou anglické (`Task`, `Sub-task`, `Story`, `Bug`, `Epic`).
   Dokumentace opravena.
2. `/issue/createmeta?projectKeys=AIC` — **REFUTED**, v Jiře 10 vrací 404.
   Platný tvar je `/issue/createmeta/{KLIC}/issuetypes/{typeId}`. `atl-discover`
   opraven, aby volal jeden dotaz na typ úkolu.

## Oficiální Atlassian `acli` — REFUTED pro Data Center

Nainstalováno (`brew tap atlassian/homebrew-acli && brew install acli`,
v1.3.23-stable, binárky z `acli.atlassian.com`). Proti E.ON instancím
**nepoužitelné**:

- `acli --help` uvádí doslova `jira  Jira **Cloud** commands` a
  `confluence  Confluence **Cloud** commands`
- `acli jira auth login --help` přijímá jen `--site "mysite.atlassian.net"`
  + `--email` + API token, případně OAuth přes prohlížeč
- Je klient nad REST API v3, které Data Center nemá:

  | endpoint na track.eon.cz | HTTP |
  |---|---|
  | `/rest/api/2/myself` | 401 (existuje, chce auth) |
  | `/rest/api/latest/myself` | 401 (existuje) |
  | `/rest/api/3/myself` | **302 na login** (neexistuje) |

- Empirický test `acli jira auth login --site track.eon.cz` → `authentication failed`

Binárka na stroji zůstává (neškodí, může se hodit na Cloud instance jiných
zadání), ale v tomhle repu se nepoužívá.

## Appfire ACLI (dřív Bob Swift) — zamítnuto

Jediné CLI, které oficiálně pokrývá Jira DC i Confluence DC v jednom. Zamítnuto,
protože je to **platený Marketplace app** — vyžaduje licenci a nákup, u DC
typicky i schválení. Nedá se prostě nainstalovat a začít pracovat.

## Zvolená sestava

### `mcp-atlassian` 0.23.0 (sooperset) — primární vrstva

5 759 stars, aktivní vývoj (commit v den měření). Ověřená podpora DC:

- kompatibilita: Jira Server/DC **v8.14+** (naše 10.3.23 ✓), Confluence Server/DC **v6.0+**
- auth: `JIRA_PERSONAL_TOKEN` / `CONFLUENCE_PERSONAL_TOKEN` (PAT, Bearer)
- `--help` potvrzuje `--jira-personal-token`, `--confluence-personal-token`,
  `--jira-projects-filter`, `--confluence-spaces-filter`, `--read-only`, `--env-file`
- běží lokálně přes `uvx`, takže dosáhne i na instance za VPN
- pokrývá **obě** produkty — Confluence žádná jiná bezplatná CLI cesta nemá

Verze je v `.mcp.json` **připnutá na 0.23.0** záměrně: MCP server se spouští
automaticky při startu Claude Code a `@latest` by znamenal, že se konfigurace
může rozbít bez tvého zásahu. Bump je vědomý krok.

### `jira-cli` 1.7.0 (ankitpokhrel) — interaktivní vrstva

5 905 stars, MIT, v homebrew-core. `jira init --installation local
--auth-type bearer` = ověřená podpora DC s PAT. Silné na průzkum (TUI, boardy,
sprinty). **Confluence neumí** — proto sám nestačí.

Známé omezení u české Jiry: zakládání issues může selhat, protože staré API
nevrací nepřeložený `issuetype.name`. Obchází se REST cestou s číselným
`issuetype.id`.

### `bin/*-api` — REST vrstva

Tenké obálky nad curl s PAT. Existují proto, aby vždy byla cesta k libovolnému
endpointu bez závislosti na tom, co MCP nebo jira-cli implementují — a aby se
auth dala funkčně otestovat (`bin/atl-auth-check`).

## Měřená konfigurace MCP

JSON-RPC sonda proti `uvx mcp-atlassian@0.23.0` s dummy tokeny:

| Konfigurace | Nástrojů | Schémata |
|---|---|---|
| bez filtru (výchozí) | 98 | 117 kB (~30 k tokenů) |
| `--read-only` | 58 | 63 kB |
| `--toolsets default` | 35 | 48 kB |
| `--toolsets jira` | **0** | 0 kB |
| zvolený allowlist 18 nástrojů | 18 | 27 kB |

Dvě zjištění, která rozhodla:

1. **`--toolsets jira` je neplatné jméno a server fail-closed spadne na 0
   nástrojů**, tiše a bez chyby. Proto je v `.mcp.json` explicitní
   `--enabled-tools` allowlist, ne toolsety.
2. **`--read-only` zamítnuto jako default.** Měřením blokuje přesně těch 7
   nástrojů, které tvoří denní práci (`jira_add_comment`,
   `jira_transition_issue`, `jira_update_issue`, `jira_create_issue`,
   `confluence_add_comment`, `confluence_create_page`,
   `confluence_update_page_section`). Allowlist plní cíl bezpečnosti lépe:
   vyhazuje ~80 nástrojů včetně mazacích a Cloud-only (`jira_move_issue`,
   `jira_batch_get_changelogs` na DC nefungují), a přesto zápis nechává.
   Zápis chrání potvrzovací režim ve skillu.

Všech 18 názvů v allowlistu bylo ověřeno proti reálnému výpisu `tools/list`.
Potvrzeno také, že `jira_get_comments` **neexistuje** (komentáře jdou přes
`jira_get_issue` s `include="comments"`) a že `confluence_update_page_section`
existuje — je to bezpečnější cesta než plný přepis stránky.

## Bezpečnostní opravy nalezené kritikou

Čtyři nezávislí posuzovatelé s mandátem zamítat. Potvrzené a opravené vady
vlastního kódu:

| Vada | Ověření | Oprava |
|---|---|---|
| `curl -sS` vracel `rc=0` na 401/403 | měřeno: rc=0 → teď rc=22 | `--fail-with-body` |
| 302 (neexistující endpoint) prošlo jako úspěch | měřeno | kontrola statusu, rc=22 |
| Bez timeoutu — bez VPN by viselo navěky | měřeno | `--max-time ${ATL_TIMEOUT:-30}` |
| Token v argv, čitelný přes `ps` | měřeno: 1 proces → 0 | `curl -K -` ze stdin |
| `curl -v` vypsal hlavičku Authorization | potvrzeno 2 kritiky | guard, rc=2 |
| `set -e` zabíjelo diagnostiku před výpisem | nalezeno při testu | `\|\| rc=$?` |

## Rozdělení vrstev

`bin/atl-jira` (jira-cli) zůstává **jako nástroj pro agenta na objemné čtení** —
kompaktní tabulka místo kilobajtů MCP JSON u desítek issues. Dva kritici ho
chtěli zrušit nebo agentovi zakázat; zadavatel rozhodl jinak a mandát je
konkrétnější: použít ho tam, kde by MCP zanesl kontext.

## Zvážené a nezvolené

| Nástroj | Stars | Proč ne |
|---|---|---|
| `pycontribs/jira` | 2 128 | knihovna, ne CLI; jen Jira |
| `atlassian-python-api` | 1 667 | knihovna, ne CLI (dobrá volba, kdyby přišlo bulk skriptování v Pythonu) |
| `go-jira/jira` | 2 744 | poslední commit 2025-11, jen Jira, kolize binárky s jira-cli |

## Konfigurační hodnoty

Hostnames (`track.eon.cz`, `dory.eon.cz`) a klíč projektu (`AIC`) zadal
uživatel. Nejsou hardcoded v kódu — žijí v `config/instances.json` a `.env`.
Verze `mcp-atlassian@0.23.0` je jediný záměrný pin, důvod výše.

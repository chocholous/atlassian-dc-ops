---
name: eon-atlassian
description: Práce s E.ON Jira Data Center (track.eon.cz) a Confluence Data Center (dory.eon.cz) — issues, JQL, sprinty, boardy, stránky, CQL, komentáře. Použij vždy, když jde o E.ON Jiru nebo Confluence, o projekt AIC, o ticket ve tvaru AIC-123, o odkaz na track.eon.cz nebo dory.eon.cz, nebo když se řeší autentizace, PAT tokeny či REST API těchto instancí. NEPOUŽÍVEJ pro Atlassian Cloud (*.atlassian.net) — tam platí jiné API a jiný nástroj.
---

# E.ON Atlassian Data Center

| | Instance | Nasazení | API |
|---|---|---|---|
| Jira | https://track.eon.cz | Data Center 10.3.23 | `/rest/api/2`, `/rest/agile/1.0` |
| Confluence | https://dory.eon.cz | Data Center | `/rest/api` (v1) |

Hlavní projekt **AIC**. Tokeny jsou v `.env` (gitignored) — **nikdy je nevypisuj**
do transkriptu, commitů ani souborů.

## Discovery je cache, která pozná, že je neplatná

`config/instances.json` drží ověřená metadata: id typů úkolů, povinná pole a
`allowedValues` per typ (z `createmeta`), editovatelná pole (z `editmeta`),
board id, typy linků, klíče spaces i jejich `homepage_id`. Generuje to
`bin/atl-discover`, po sekcích — každá sekce nese vlastní `_discovered` a
`_sources`.

**Ber hodnoty odsud, nedohledávej je po jedné.** Zejména `issuetype.id`,
povinná pole a `allowedValues` (globální `/priority` má 27 hodnot, ale AIC/Task
jen 5 — globální seznamy nejsou pravda o projektu).

```bash
bin/atl-discover --check              # nic nezapíše; rc=3 = drift, vypíše diff
bin/atl-discover --section jira       # obnoví jen tuhle sekci, ostatní zachová
bin/atl-discover                      # obnoví vše
```

Když si nejsi jistý svěžestí, spusť `--check` — je bezpečný, nic nemění.

**Co se ZÁMĚRNĚ neukládá** a musíš zjistit živě:
- `transition.id` — závisí na *aktuálním* stavu issue, uložená hodnota by lhala
- `sprint.id` — mění se každé dva týdny (board id uložený je)
- počty issues — to je dotaz, ne konfigurace

## Když zápis selže, schéma se obnoví samo

`atl_curl` klasifikuje selhání a podle druhu jedná:

| HTTP | Druh | Co se stane |
|---|---|---|
| 400 s `"errors"` u polí | `schema` | **discovery se samo obnoví** a vypíše diff povinných polí |
| 400 bez chyb polí | `request` | neléčí — chyba je v JQL/CQL nebo syntaxi |
| 401 | `auth` | neléčí — vypršelý PAT, spusť `bin/atl-auth-check` |
| 403 | `perm` | neléčí — chybí oprávnění, discovery to nespraví |
| 409 | `conflict` | neléčí — načti Confluence stránku znovu kvůli `version` |
| 3xx / 404 | `endpoint` | neléčí — endpoint v této verzi neexistuje, tělo NEJSOU data |

**Zápis se po obnovení schématu NEZKOUŠÍ automaticky znovu.** Nové povinné pole
by znamenalo vymyslet hodnotu — to je rozhodnutí uživatele, ne tvoje. Přečti
`.jira.create` v configu, doplň payload, ukaž ho uživateli a zavolej znovu.

Když léčení řekne „povinná pole se nezměnila", je chyba ve tvém payloadu, ne ve
schématu — nehádej dál, porovnej payload s `.jira.create`.

## Kterou vrstvu použít — tvrdé pravidlo

**1. MCP `atlassian-eon` je default.** 18 nástrojů, čtení i zápis.

**2. `bin/atl-jira` (jira-cli) použij na objemné čtení,** kde by ti MCP JSON
zanesl kontext — desítky issues, průchod boardem, přehled sprintu. Kompaktní
tabulka místo kilobajtů JSON:
```bash
bin/atl-jira issue list -q 'project=AIC AND statusCategory != Done' --plain --no-headers --columns key,status,summary
```
Pro jeden nebo pár ticketů ho nepoužívej — tam je MCP kratší cesta.

**3. `bin/jira-api` / `bin/conf-api` (REST) použij jen při jedné z podmínek:**
- potřebuješ **`total` / `totalSize`** nebo stránku za hranicí limitu MCP
- **bulk** nad ~20 objektů, nebo přesný payload (např. `issuetype.id`)
- endpoint, který MCP nemá (`changelog`, `remotelink`, `createmeta`, CSV export)

Jinak REST nesahej.

## Tři fakty, které bez znalosti způsobí chybu

0. **Globální seznamy nejsou pravda o projektu.** `/priority` vrací 27 hodnot,
   `/resolution` 13, `/field` 326 polí. Pro AIC platí jen to, co je v
   `createmeta` — 14 polí a 5 priorit. Ber `allowedValues`, ne globální endpoint.
1. **`jira_search` vrací default 10 výsledků, max 50.** `confluence_search`
   default 25. REST `/search` default 50. Tři různé limity — proto se počty
   ověřují REST cestou, viz „Než řekneš nic/všechno" níž.
2. **`jira_get_comments` NEEXISTUJE.** Komentáře se čtou
   `jira_get_issue` s `include="comments"`.
3. **Úpravu Confluence stránky dělej `confluence_update_page_section`**, ne
   plným přepisem. Mění jen sekci pod daným nadpisem a nechá zbytek včetně
   maker na pokoji. Plný `confluence_update_page` nebo `PUT /content/{id}` použij
   jen když sekce nestačí — a pak podle postupu v `references/confluence-dc.md`.

## Pasti Data Center

1. **`/rest/api/3` neexistuje** — vrátí 302 na login, ne JSON. Vždy `v2` nebo
   `latest`. Confluence má API na `/rest/api`, ne `/wiki/rest/api` jako Cloud.
2. **Oficiální Atlassian `acli` je Cloud-only** a proti těmto instancím
   nefunguje, i když je na stroji nainstalovaný. Nepoužívej ho tady.
3. **Auth je PAT** (`Authorization: Bearer`), ne basic auth. PAT má povinnou
   expiraci → náhlé 401 napříč vším je nejčastěji vypršelý token. Ověř
   `bin/atl-auth-check`.
4. **Typy úkolů v AIC jsou ANGLICKÉ** — `Task`, `Sub-task`, `Story`, `Bug`,
   `Epic` (ověřeno proti instanci 2026-08-18). Obecná past „česká Jira neumí
   zakládat podle jména typu" se tady tedy **neuplatní**. Přesto ber `issuetype.id`
   z `config/instances.json` — je to jednoznačné a nezávislé na přejmenování.
   **Epic navíc vyžaduje `customfield_10002` (Epic Name)**, jinak POST spadne
   na 400; povinná pole pro každý typ jsou v configu v `jira.required_fields`.
5. **`/issue/createmeta?projectKeys=` je v Jiře 10 zrušené** (404). Platný tvar
   je `/issue/createmeta/{KLIC}/issuetypes/{typeId}`.
6. **MCP nastartuje i s prázdnými tokeny** a Claude Code ho ohlásí jako
   connected. Selže až první volání. „Server je connected" tedy není důkaz
   funkčního přístupu — tím je `bin/atl-auth-check` s `rc=0`.
7. **`--toolsets` s neplatným jménem shodí MCP na 0 nástrojů,** tiše. Jména sad
   se needitují naslepo.

## Před zápisem se zastav

Před **každým** zápisem (komentář, přechod stavu, úprava či založení issue,
zápis do Confluence) vypiš přesné volání: nástroj a všechny parametry, u
Confluence navíc `id`, `title`, `space` a `version` cílové stránky. Pak se
zastav a čekej na odpověď uživatele v chatu. **Souhlas platí na jedno volání,
ne na dávku** — u hromadné úpravy si nech potvrdit seznam klíčů, kterých se to
dotkne, a pak jeď s `ATL_DRY_RUN=1` na kontrolu, než pustíš ostrou smyčku.

Komentář rozešle notifikace kolegům a přechod stavu může spustit post-funkce
(přeřazení, uzavření rodiče) — obojí je sociálně nevratné, i když technicky ano.

## Po zápisu si to přečti zpět

Přečti změněný objekt (`jira_get_issue`, resp. `confluence_get_page`) a **cituj
konkrétní hodnotu, kterou jsi měnil**. `204 No Content`, prázdná odpověď ani
`rc=0` nejsou důkaz. Skripty `bin/*-api` vracejí nenulový rc na HTTP ≥400 i na
3xx, takže jejich rc směrodatný je — ale MCP odpověď „ok" ověř čtením.

## Než řekneš „nic tam není" nebo „to je všechno"

Ověř počet druhou cestou, ne uříznutým výpisem:
```bash
bin/jira-api GET '/search?jql=…&maxResults=0' | jq .total
bin/conf-api GET '/search?cql=…&limit=1' | jq .totalSize
```

## Detailní recepty

- `references/jira-dc.md` — JQL, payloady, transitions, Agile, changelog
- `references/confluence-dc.md` — CQL, storage formát, bezpečná úprava stránky
- `references/jira-cli.md` — objemné čtení kompaktním výstupem

**Míra ověření (2026-08-18).** Ověřeno proti živým instancím s platnými tokeny:
auth na obou (`rc=0`), Jira 10.3.23, Confluence 9.2.22, discovery všech metadat,
čtení přes REST (`/search`, `total`) i přes MCP (`jira_search`,
`confluence_search`), `createmeta` per typ úkolu. **Neověřeno: jakýkoli ZÁPIS** —
zakládání issue, komentář, přechod stavu, zápis stránky. Payloady zápisů jsou
z dokumentace. První zápis každého druhu ber jako první běh a přečti si výsledek
zpět.

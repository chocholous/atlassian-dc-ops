---
name: eon-atlassian
description: Práce s E.ON Jira Data Center (track.eon.cz) a Confluence Data Center (dory.eon.cz) — issues, JQL, sprinty, boardy, stránky, CQL, komentáře. Použij vždy, když jde o E.ON Jiru nebo Confluence, o projekt AIC, o ticket ve tvaru AIC-123, o odkaz na track.eon.cz nebo dory.eon.cz, nebo když se řeší autentizace, PAT tokeny či REST API těchto instancí. NEPOUŽÍVEJ pro Atlassian Cloud (*.atlassian.net) — tam platí jiné API a jiný nástroj.
---

# E.ON Atlassian Data Center

| | Instance | Verze |
|---|---|---|
| Jira | https://track.eon.cz | Data Center 10.3.23 |
| Confluence | https://dory.eon.cz | Data Center 9.2.22 |

Hlavní projekt **AIC**. Tokeny jsou v `.env` (gitignored) — **nikdy je nevypisuj**
do transkriptu, commitů ani souborů.

## Jedna vrstva

**MCP `atlassian-eon` je default** — 19 nástrojů, čtení i zápis pro Jiru
i Confluence, včetně metadat schématu (`jira_get_create_fields`,
`jira_get_project_issue_types`). Přesný seznam je v `.mcp.json`.

Linkování issues v allowlistu **není** — kdybys ho potřeboval, musí se přidat
`jira_create_issue_link` i `jira_get_link_types` naráz, jinak jedno bez druhého
nedává smysl.

**MCP je jediná cesta.** REST obálky v repu nejsou — jejich jediné unikátní
odůvodnění (`totalSize` z Confluence) padlo, protože `confluence_search` neumí
stránkovat: víc než 50 výsledků nedostaneš ani tak, a znát jejich počet ti
k ničemu není.

Když opravdu potřebuješ endpoint mimo MCP (smyčka, bulk, `remotelink`, CSV
export), volej curl přímo podle receptu v `references/dc-odchylky.md` —
**token na stdin, nikdy přes `-H`**.

**Tvar endpointu nehádej — vytáhni ho z připnuté specifikace:**

```bash
bin/atl-spec jira createmeta          # cesty + metody
bin/atl-spec jira --show '<cesta>'    # parametry a odpovědi
bin/atl-spec conf '<vzor>'
```

Pozor na míru přesnosti: Confluence spec je pro naši verzi (9.2.22), **Jira spec
je 10.0.5, ale instance běží 10.3.23** — Atlassian pro 10.3.x nic nepublikuje.
Jádro v2 je stabilní, novější endpointy v tom specu ale chybět mohou. Když spec
cestu nezná a instance ji přijme, věř instanci.

Přístup ověříš `bin/atl-check`. `rc=2` znamená, že se nic nebo jen část
ověřila — **to není úspěch**. Že se MCP hlásí jako „connected", důkaz není.

## Než začneš zakládat nebo měnit

Povinná pole a povolené hodnoty si vytáhni **živě**, ne z paměti:

```
jira_get_create_fields(project_key="AIC", issue_type_id="10003")
```

Trvá to ~250 ms a je to jediný zdroj pravdy. **Globální endpointy jako
`/priority` lžou o projektu** — proč a o kolik, viz `references/dc-odchylky.md`.

**`transition.id` a `sprint.id` nikdy nehádej ani nepamatuj** — transition závisí
na aktuálním stavu issue, sprint se mění každé dva týdny. Vždy živě
(`jira_get_transitions`, `jira_get_sprints_from_board`).

## Před zápisem se zastav

Před **každým** zápisem (komentář, přechod stavu, úprava či založení issue,
zápis do Confluence) vypiš přesné volání: nástroj a všechny parametry, u
Confluence navíc `id`, `title`, `space` a `version` cílové stránky. Pak čekej na
odpověď uživatele v chatu. **Souhlas platí na jedno volání, ne na dávku.**

Komentář rozešle notifikace a přechod stavu může spustit post-funkce (přeřazení,
uzavření rodiče) — sociálně nevratné, i když technicky ne.

Úprava Confluence stránky je nejrizikovější operace: špatné `id` přepíše cizí
stránku. Ověř `id`, `title` a `space` čtením, než zapíšeš.

## Po zápisu si to přečti zpět

Přečti změněný objekt (`jira_get_issue`, `confluence_get_page`) a **cituj
konkrétní hodnotu, kterou jsi měnil**. `204 No Content`, prázdná odpověď ani
`rc=0` nejsou důkaz.

Skripty `bin/*-api` vracejí nenulový rc na HTTP ≥400 i na 3xx, takže jejich rc
směrodatný je. MCP odpověď „ok" ověř čtením.

## Než řekneš „nic tam není" nebo „to je všechno"

`jira_search` vrací `total` přímo v odpovědi, takže u Jiry to poznáš.
**U Confluence to poznat nejde** — `confluence_search` má strop 50, nestránkuje
a počet nevrací. Pokud dostaneš 50 výsledků, řekni „nejméně 50", ne „to je vše".

## Zápisy nejsou ověřené

Čtení je proti oběma instancím ověřené měřením. **Žádný zápis nikdy neproběhl** —
zakládání issue, komentář, přechod stavu, zápis stránky. AIC je reálný projekt.
První zápis každého druhu ber jako první běh.


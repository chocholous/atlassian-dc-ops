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

**MCP `atlassian-eon` je default a má všech 98 nástrojů** — čtení, zápis,
metadata schématu, linkování, boardy, sprinty. Žádný allowlist, takže žádná
tichá absence: když nástroj neznáš, hledej ho v `tools/list`, ne v configu.

Mezi nimi je pět **destruktivních**: `jira_delete_issue`, `confluence_delete_page`,
`confluence_delete_attachment`, `jira_remove_issue_link`, `jira_remove_watcher`.
Nic je technicky neblokuje — platí na ně potvrzovací pravidlo níž, a u mazání
si nech potvrdit i to, že jde opravdu o mazání, ne o úpravu.

**MCP je jediná cesta.** REST obálky v repu nejsou — jejich jediné unikátní
odůvodnění (`totalSize` z Confluence) padlo, protože `confluence_search` neumí
stránkovat: víc než 50 výsledků nedostaneš ani tak, a znát jejich počet ti
k ničemu není.

Když opravdu potřebuješ endpoint mimo MCP (smyčka, bulk, `remotelink`, CSV
export), volej curl přímo podle receptu v `references/dc-odchylky.md` —
**token na stdin, nikdy přes `-H`**.

**Tvar endpointu nehádej — vytáhni ho z připnuté specifikace.** Tři příkazy,
víc nepotřebuješ:

```bash
bin/atl-spec jira createmeta                   # které cesty existují + metody
bin/atl-spec jira --show '/api/2/serverInfo'   # parametry, povinnost, odpovědi
bin/atl-spec conf 'content/.*child'            # totéž pro Confluence
```

Vzor je regulární výraz, case-insensitive. Jira cesty jsou relativní k `/rest`
(`/api/2/...`, `/agile/1.0/...`), Confluence cesty už `/rest/api/...` obsahují.
Když `spec/` chybí, spusť `bin/atl-spec fetch`.

Spec **je platný pro naši verzi** — empiricky ověřeno, 24 z 24 vzorkovaných cest
na instanci existuje. Ale je **nekompletní**: plugin API jako `/rest/pat/latest`
nebo `/rest/applinks/1.0` v něm nejsou, i když na instanci fungují. Když spec
cestu nezná a instance ji přijme, **věř instanci**.

Pro zápisy je `jira_get_create_fields` lepší zdroj než spec: je živý, z naší
přesné verze, per projekt a typ úkolu, a vrací `allowedValues`.

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


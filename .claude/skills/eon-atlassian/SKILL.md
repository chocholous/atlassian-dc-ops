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

## Dvě vrstvy, jednoduché pravidlo

**MCP `atlassian-eon` je default** — 23 nástrojů, čtení i zápis pro Jiru
i Confluence, včetně metadat schématu (`jira_get_create_fields`,
`jira_get_link_types`, `jira_get_project_components`, `jira_get_project_versions`,
`jira_get_field_options`).

**`bin/jira-api` / `bin/conf-api` (REST) použij jen ve třech případech:**

1. endpoint, který MCP nemá — `serverInfo`, `remotelink`, CSV export
2. `totalSize` z Confluence (MCP `confluence_search` ho nevrací)
3. bulk nad ~20 objektů, nebo když potřebuješ přesný payload

Jinak REST nesahej. `bin/atl-auth-check` ověří přístup k oběma instancím.

## Než začneš zakládat nebo měnit

Povinná pole a povolené hodnoty si vytáhni **živě**, ne z paměti:

```
jira_get_create_fields(project_key="AIC", issue_type_id="10003")
```

Trvá to ~250 ms a je to jediný zdroj pravdy. Globální `/priority` má 27 hodnot,
ale pro AIC/Task platí 5 — viz `references/dc-odchylky.md`.

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
stránku. Použij `confluence_update_page_section`, ne plný přepis.

## Po zápisu si to přečti zpět

Přečti změněný objekt (`jira_get_issue`, `confluence_get_page`) a **cituj
konkrétní hodnotu, kterou jsi měnil**. `204 No Content`, prázdná odpověď ani
`rc=0` nejsou důkaz.

Skripty `bin/*-api` vracejí nenulový rc na HTTP ≥400 i na 3xx, takže jejich rc
směrodatný je. MCP odpověď „ok" ověř čtením.

## Než řekneš „nic tam není" nebo „to je všechno"

Tři vrstvy mají tři různé default limity. `jira_search` vrací `total` přímo.
Confluence počty jen přes REST:

```bash
bin/conf-api GET '/search?cql=…&limit=1' | jq .totalSize
```

## Zápisy nejsou ověřené

Čtení je proti oběma instancím ověřené měřením. **Žádný zápis nikdy neproběhl** —
zakládání issue, komentář, přechod stavu, zápis stránky. AIC je reálný projekt.
První zápis každého druhu ber jako první běh.

Odchylky DC, které nejdou uhodnout: `references/dc-odchylky.md`.

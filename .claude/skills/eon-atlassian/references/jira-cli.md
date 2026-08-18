# jira-cli — objemné čtení kompaktním výstupem

`jira-cli` v1.7.0, přes wrapper **`bin/atl-jira`** (dodá PAT z `.env` a nasměruje
config do repa, takže nepřepíše globální `~/.config/.jira/.config.yml`).

## K čemu tady je

Jediný důvod: **kompaktní tabulkový výstup u objemného čtení.** Když potřebuješ
desítky issues, přehled boardu nebo sprintu, MCP vrátí kilobajty JSON a zanese
kontext. Tabulka dá totéž na zlomku místa.

Pro jeden nebo pár ticketů ho nepoužívej — tam je MCP kratší.

## Jednorázová inicializace

Vyžaduje token v `.env`. `--login` je **Jira username**, ne macOS login a ne
e-mail; vezmi ho z `config/instances.json` (`.me.jira_name`), který vyplní
`bin/atl-discover`:

```bash
bin/atl-jira init --installation local --server https://track.eon.cz \
    --login "$(jq -r .me.jira_name config/instances.json)" \
    --auth-type bearer --project AIC
```

- `--installation local` — bez toho jde na Cloud API a selže
- `--auth-type bearer` — PAT; `basic` by čekal heslo

Config skončí v `config/jira-cli.yml` (gitignorovaný, obsahuje login a cache
schématu). Po změně schématu v Jiře spusť `init --force`.

## Objemné čtení

Vždy s `--plain --no-headers` a explicitními `--columns` — bez toho leze TUI
nebo zbytečné sloupce:

```bash
bin/atl-jira issue list -q 'project=AIC AND statusCategory != Done' \
    --plain --no-headers --columns key,status,assignee,summary

bin/atl-jira issue list -q 'project=AIC AND updated >= -7d' \
    --plain --no-headers --columns key,updated,summary

bin/atl-jira sprint list --current --plain --no-headers
bin/atl-jira board list --plain --no-headers
bin/atl-jira epic list --plain --no-headers
```

`--raw` dá surové JSON — tím se ale ruší celý smysl (kompaktnost), použij jen
když potřebuješ pole, které tabulka neumí.

## Co přes jira-cli NEDĚLAT

- **Zápis.** Zakládání a úpravy dělej přes MCP nebo `bin/jira-api` — jednotná
  cesta a přesná kontrola payloadu. (Známé omezení jira-cli pro ne-anglické
  instance se na AIC nejspíš neuplatní, typy úkolů jsou anglické, ale
  netestovali jsme to.)
- **Confluence.** jira-cli ji neumí vůbec.
- **Zjišťování počtů.** `total` dá jen REST (`maxResults=0`).

## Míra ověření

Příkazy jsou z `jira init --help` a `jira --help` nainstalované binárky
(ověřeno). **`init` ani `issue list` proti track.eon.cz spuštěny nebyly** —
tahle vrstva je jediná v repu, která zatím neproběhla ostře. První běh ber jako
první běh.

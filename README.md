# E.ON Atlassian ops

Pracovní repo pro Jira Data Center a Confluence Data Center v E.ONu.

| | Instance | Nasazení |
|---|---|---|
| Jira | https://track.eon.cz | Data Center 10.3.23 |
| Confluence | https://dory.eon.cz | Data Center |

Hlavní projekt: [AIC](https://track.eon.cz/projects/AIC)

## Nastavení

**1. Vytvoř Personal Access Tokeny** (ručně ve UI, vyžaduje tvoje přihlášení):

- Jira: https://track.eon.cz/secure/ViewProfile.jspa → *Personal Access Tokens*
- Confluence: https://dory.eon.cz/users/viewmyprofile.action → *Personal access tokens*

PAT má v Data Center **povinnou expiraci** (default 90 dní). Až vyprší, začne
všechno vracet 401.

**2. Vlož je do `.env`:**

```bash
cp .env.example .env && chmod 600 .env
```

**3. Ověř přístup** — musí skončit `rc=0`:

```bash
bin/atl-auth-check
```

`rc=2` znamená, že se nic neověřilo (chybí token). To není úspěch.

**4. Zjisti metadata instancí** (id typů úkolů, board id, customfieldy, spaces):

```bash
bin/atl-discover
```

Zapíše `config/instances.json` po sekcích, každou s vlastním datem a seznamem
endpointů, ze kterých vznikla.

```bash
bin/atl-discover --check          # nic nezapíše, jen nahlásí drift (rc=3) s diffem
bin/atl-discover --section jira   # obnoví jednu sekci, ostatní zachová
bin/atl-discover --dry-run        # vypíše výsledek, nezapíše
```

**Samoléčení:** když zápis selže na 400 s chybami polí (typicky nové povinné
pole), skripty obnoví schéma samy a vypíšou, co se změnilo. Zápis pak
**nezkoušejí znovu** — doplnit hodnotu nového pole je tvoje rozhodnutí.
Na 401, 403, 409 ani 404 se neléčí, protože tam by to nepomohlo.

**5. Restartuj Claude Code** — MCP server čte konfiguraci při startu.

**6. Volitelně inicializuj jira-cli** (potřebuje krok 4):

```bash
bin/atl-jira init --installation local --server https://track.eon.cz \
    --login "$(jq -r .me.jira_name config/instances.json)" \
    --auth-type bearer --project AIC
```

## Jak s tím pracovat

| Vrstva | K čemu |
|---|---|
| MCP `atlassian-eon` | **default** — čtení i zápis, 18 nástrojů |
| `bin/atl-jira` | objemné čtení kompaktní tabulkou (desítky issues, boardy, sprinty) |
| `bin/jira-api`, `bin/conf-api` | `total`, bulk, přesný payload, endpointy které MCP nemá |

MCP je zúžený na 18 nástrojů z 98 (`--enabled-tools` v `.mcp.json`): 27 kB
schémat místo 117 kB, tedy ~25 k tokenů úspora na session. Mazací a Cloud-only
nástroje jsou vynechané. **Neplatné jméno v `--toolsets` shodí server na 0
nástrojů, tiše** — proto je použitý explicitní allowlist, ne toolsety.

```bash
bin/jira-api GET /issue/AIC-1
bin/jira-api GET '/search?jql=project=AIC+AND+statusCategory!=Done&maxResults=20'
bin/conf-api GET '/space?limit=100'
ATL_DRY_RUN=1 bin/jira-api POST /issue -d @payload.json   # nic nezapíše
```

Proměnné: `ATL_TIMEOUT` (default 30 s), `ATL_DRY_RUN=1`, `ATL_ENV_FILE`,
`ATL_PROJECT` (default AIC).

Postupy a pasti drží skill `eon-atlassian` — Claude si ho načte sám.

## Struktura

```
.mcp.json                       MCP atlassian-eon, allowlist 18 nástrojů
.env / .env.example             tokeny (gitignored, 600) / šablona
config/instances.json           generuje bin/atl-discover
bin/atl-auth-check              ověření PAT proti oběma instancím
bin/atl-discover                jednorázové zjištění metadat
bin/atl-jira                    wrapper nad jira-cli
bin/jira-api / bin/conf-api     REST klienti
bin/_common.sh                  sdílené funkce (auth, HTTP kontrola, dry-run)
docs/rozhodnuti-nastroje.md     proč tyhle nástroje a ne oficiální acli
.claude/skills/eon-atlassian/   skill + 3 reference
```

## Důležité

**Oficiální Atlassian `acli` tady nefunguje** — je Cloud-only. Nainstalovaný je,
ale proti E.ON instancím ho nepoužívej: [docs/rozhodnuti-nastroje.md](docs/rozhodnuti-nastroje.md).

**Míra ověření:** dostupnost obou instancí, verze Jiry, chování auth a chování
skriptů jsou ověřené měřením. Recepty v referencích skillu jsou z dokumentace a
proti živým instancím **nikdy neproběhly** — dokud `bin/atl-auth-check` nedá
`rc=0`, je to neověřený návrh.

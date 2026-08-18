# Confluence Data Center — REST API v1

Base: `https://dory.eon.cz/rest/api`
Auth: `Authorization: Bearer <PAT>`

**Pozor na rozdíl proti Cloudu:** DC má API na `/rest/api`, Cloud na
`/wiki/rest/api`. Cloudové návody z internetu tady bez úpravy nefungují.

## Čtení

```bash
bin/conf-api GET /user/current

# Spaces
bin/conf-api GET '/space?limit=100'
bin/conf-api GET '/space?limit=100' | jq -r '.results[] | "\(.key)\t\(.name)"'
bin/conf-api GET /space/SPACEKEY

# Stránka podle id, včetně těla a verze
bin/conf-api GET '/content/123456?expand=body.storage,version,space,ancestors'

# Stránka podle názvu ve space
bin/conf-api GET '/content?spaceKey=SPACEKEY&title=Název%20stránky&expand=version'

# Potomci stránky
bin/conf-api GET '/content/123456/child/page?limit=100'

# Přílohy
bin/conf-api GET '/content/123456/child/attachment?limit=100'
```

`expand` je klíčový — bez něj nedostaneš tělo ani číslo verze. Nejčastější
kombinace: `body.storage,version`.

## Hledání (CQL)

```bash
bin/conf-api GET '/content/search?cql=text~"AIC"&limit=25'
bin/conf-api GET '/content/search?cql=space=SPACEKEY+AND+type=page&limit=25'
bin/conf-api GET '/content/search?cql=lastmodified>=now("-7d")&limit=25'
bin/conf-api GET '/content/search?cql=title~"release"&expand=version&limit=25'
```

Stejná past jako u Jiry: odpověď má `size`, `limit`, `start` a `_links.next`.
`limit` má default 25. Než tvrdíš, že něco neexistuje, ověř počet.

Pozor na dva různé endpointy: **`/content/search` vrací `size`** (počet
na stránce), zatímco **`/search` vrací i `totalSize`** (celkový počet). Na počty
tedy `/search`:

```bash
bin/conf-api GET '/search?cql=text~"AIC"&limit=1' | jq '.totalSize'
```

Další stránka: `&start=25`, nebo následuj `_links.next`.

## Zápis — vyžaduje potvrzení uživatele

Tělo se posílá ve **storage formátu** (Confluence XHTML), ne v Markdownu.

```bash
# Nová stránka
bin/conf-api POST /content -d '{
  "type": "page",
  "title": "Název stránky",
  "space": {"key": "SPACEKEY"},
  "ancestors": [{"id": "123456"}],
  "body": {"storage": {"value": "<p>Obsah</p>", "representation": "storage"}}
}'
```

### Úprava stránky — nejdřív zvaž sekční úpravu

**Preferovaná cesta je MCP `confluence_update_page_section`** — mění jen sekci
pod daným nadpisem a nechá zbytek stránky včetně maker na pokoji. Plný přepis
níže použij jen tehdy, když sekce nestačí (mění se struktura, přidává se nová
sekce, přepisuje se celá stránka).

**Plný přepis je nejrizikovější operace v celém repu.** Vyžaduje `version.number`
o 1 vyšší než aktuální. Špatné `id` = přepsaná cizí stránka; špatná verze = 409.

```bash
# 1) Přečti aktuální verzi a POTVRĎ, že id patří té stránce, kterou chceš měnit
bin/conf-api GET '/content/123456?expand=version,space' | jq '{id, title, space: .space.key, version: .version.number}'

# 2) Teprve pak zapiš s inkrementovanou verzí
bin/conf-api PUT /content/123456 -d '{
  "type": "page",
  "title": "Název stránky",
  "version": {"number": 8},
  "body": {"storage": {"value": "<p>Nový obsah</p>", "representation": "storage"}}
}'
```

`PUT` **přepíše celé tělo** — není to patch. Vždy si nejdřív načti stávající
obsah, uprav ho, a pak pošli celek.

Před přepisem si stávající tělo ulož, aby byla cesta zpět:

```bash
bin/conf-api GET '/content/123456?expand=body.storage,version' \
  > "zaloha-123456-v$(date +%F-%H%M).json"
```

```bash
# Komentář ke stránce
bin/conf-api POST /content -d '{
  "type": "comment",
  "container": {"id": "123456", "type": "page"},
  "body": {"storage": {"value": "<p>Komentář</p>", "representation": "storage"}}
}'
```

## Konverze Markdown → storage

Confluence DC neumí přijmout Markdown. Možnosti:
- jednoduchý obsah napsat rovnou ve storage XHTML (`<p>`, `<ul>`, `<h2>`, `<table>`)
- makro pro kód: `<ac:structured-macro ac:name="code">` s `<ac:plain-text-body><![CDATA[...]]></ac:plain-text-body>`
- MCP nástroje (`atlassian-eon`) konverzi řeší samy — u delšího obsahu jsou
  spolehlivější než ruční skládání XHTML

## Časté chyby

| Symptom | Příčina |
|---|---|
| 401 | vypršelý PAT |
| 404 na `/wiki/rest/api/...` | cloudová cesta; na DC je `/rest/api/...` |
| 409 při PUT | `version.number` není aktuální + 1 |
| Prázdné `body` v odpovědi | chybí `?expand=body.storage` |
| Rozbité formátování | poslán Markdown místo storage XHTML |

## Míra ověření

Ověřeno proti `dory.eon.cz` s platným tokenem (2026-08-18): Confluence DC
**9.2.22**, `/user/current`, `/space?limit=100&start=N` (stránkování),
`/search?cql=…` včetně `totalSize` (256 stránek), MCP `confluence_search` —
všechno 200. Klíče spaces a `serverId` jsou v `config/instances.json`.
**Zápisové endpointy ověřeny NEBYLY** (`POST /content`, `PUT /content/{id}`)
— payloady jsou z dokumentace. U prvního zápisu postupuj podle bezpečného
postupu výše a výsledek si přečti zpět.

#!/usr/bin/env bash
# Sdílené funkce pro atl-* skripty. Není určeno ke spuštění samostatně.
#
# Tady NENÍ `set -e`, protože `bin/atl-auth-check` chce běžet bez něj (sbírá
# výsledky všech kontrol, neskončí na první selhané). `set -uo pipefail`
# errexit volajícího nijak nemění — ověřeno, přidat sem `-e` by ho ale
# volajícímu vnutilo, což dřív dělalo.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ATL_ENV_FILE:-$REPO_ROOT/.env}"

load_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "CHYBA: chybí $ENV_FILE" >&2
    echo "Vytvoř ho:  cp $REPO_ROOT/.env.example $REPO_ROOT/.env && chmod 600 $REPO_ROOT/.env" >&2
    return 1
  fi
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
}

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "CHYBA: $name není nastavená v $ENV_FILE" >&2
    return 1
  fi
}

# Vypíše úvodní blok komentářů skriptu jako nápovědu.
# Bez fixních čísel řádků — ta se rozejdou při první editaci.
usage_from_header() {
  awk 'NR==1 {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$1"
}

# atl_curl <base_url> <token> <method> <path> [curl args...]
#
# Token jde curlu konfigurací na stdin (-K -), NE přes -H v argv: argumenty
# procesu čte každý lokální proces přes `ps`. Ověřeno měřením — před opravou
# 1 proces curl s tokenem v argv, po opravě 0.
# Důsledek: stdin je obsazený → data posílej `-d @soubor`, ne `-d @-`.
#
# Návratový kód JE směrodatný: `--fail-with-body` dá nenulový rc na HTTP >=400
# (tělo přesto vypíše), 3xx se kontroluje zvlášť. Bez toho vracel `curl -sS`
# na 401 rc=0, takže selhání vypadalo jako úspěch.
#
# ATL_TIMEOUT — timeout requestu v sekundách (default 30)
atl_curl() {
  local base="$1" token="$2" method="$3" path="$4"
  shift 4

  # ALLOWLIST propouštěných přepínačů, ne blacklist zakázaných.
  # Blacklist tady dřív byl a byl prostupný — změřeno: slepené `-sv` se
  # nerovná `-v`, takže prošlo a vypsalo hlavičku Authorization s tokenem;
  # `--libcurl soubor.c` token zapsal na disk. Cokoli, co umí vypsat nebo
  # uložit požadavek, token vystaví, a vyjmenovat všechny takové přepínače
  # dopředu nelze. Proto: co není povolené, neprojde.
  local a
  for a in "$@"; do
    case "$a" in
      -d|--data|--data-binary|--data-raw|--data-urlencode) ;;
      -H|--header|-o|--output|-G|--get|--url-query) ;;
      -) ;;
      -*)
        echo "CHYBA: přepínač $a není povolený." >&2
        echo "       Propouští se jen: -d/--data*, -H/--header, -o/--output," >&2
        echo "       -G/--get, --url-query. Ostatní (-v, -sv, --trace*, --libcurl)" >&2
        echo "       by vypsaly nebo uložily hlavičku Authorization s tokenem." >&2
        return 2 ;;
      *) ;;   # hodnota předchozího přepínače
    esac
  done

  local hdr rc status
  hdr="$(mktemp -t atl_hdr)" || return 1

  # `|| rc=$?` je nutné: volající běží se `set -e`, které by ho při nenulovém
  # rc ukončilo ještě před vyhodnocením statusu níž.
  rc=0
  printf 'header = "Authorization: Bearer %s"\n' "$token" | curl -sS -K - \
    --fail-with-body \
    --max-time "${ATL_TIMEOUT:-30}" \
    -D "$hdr" \
    -X "$method" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    "$@" \
    "${base}${path}" || rc=$?

  # Druhé pole první řádky ("HTTP/1.1 200 OK"). Bash read místo awk — ušetří
  # proces na každém volání a dělá totéž.
  read -r _ status _ < "$hdr" || status=""
  rm -f "$hdr"

  if [[ $rc -eq 0 && "${status:-}" == 2* ]]; then
    return 0
  fi

  printf 'CHYBA: %s %s — HTTP %s, curl rc=%s\n' \
    "$method" "$path" "${status:-neznámý}" "$rc" >&2
  case "${status:-}" in
    401) echo "        PAT neplatný nebo vypršel. Ověř: bin/atl-auth-check" >&2 ;;
    403) echo "        Token platný, chybí oprávnění." >&2 ;;
    409) echo "        Confluence: version.number musí být aktuální + 1. Načti stránku znovu." >&2 ;;
    400) echo "        Payload nebo JQL/CQL odmítnuty — přečti tělo odpovědi." >&2 ;;
    3*)  echo "        Přesměrování: endpoint v této verzi neexistuje (na DC typicky" >&2
         echo "        /rest/api/3 nebo starý tvar createmeta). Tělo NEJSOU data." >&2 ;;
  esac

  # 3xx: curl uspěl (rc=0), ale tělo nejsou data. Vracíme 22, tedy stejný kód,
  # jaký dává curl pro chybový HTTP status (CURLE_HTTP_RETURNED_ERROR).
  (( rc )) || rc=22
  return "$rc"
}

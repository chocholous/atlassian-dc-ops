#!/usr/bin/env bash
# Sdílené funkce pro atl-* skripty. Není určeno ke spuštění samostatně.
#
# ZÁMĚRNĚ tady NENÍ `set -e`. Tenhle soubor se `source`-uje, takže by přepsal
# nastavení volajícího — `bin/atl-auth-check` chce běžet BEZ -e, aby posbíral
# výsledky všech kontrol. Kdo -e chce, nastaví si ho po sourcování.
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

  # -v/--trace* vypíší hlavičku Authorization, tedy token, na výstup.
  # Ověřený únik → odmítáme.
  local a
  for a in "$@"; do
    case "$a" in
      -v|--verbose|--trace|--trace-ascii|--trace-all|--trace-config)
        echo "CHYBA: $a je zakázané — vypsalo by hlavičku Authorization (token)." >&2
        return 2 ;;
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

  status="$(awk 'NR==1{print $2}' "$hdr" 2>/dev/null)"
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
    404) echo "        Endpoint nebo objekt neexistuje." >&2 ;;
  esac

  [[ $rc -ne 0 ]] && return "$rc"
  return 22
}

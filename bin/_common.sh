#!/usr/bin/env bash
# Sdílené funkce pro atl-* skripty. Není určeno ke spuštění samostatně.
#
# ZÁMĚRNĚ tady NENÍ `set -e`. Tenhle soubor se `source`-uje, takže by přepsal
# nastavení volajícího skriptu — `bin/atl-auth-check` chce běžet BEZ -e, aby
# mohl posbírat výsledky všech kontrol i při selhání první z nich.
# Každý skript si -e nastavuje sám, po sourcování.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ATL_ENV_FILE:-$REPO_ROOT/.env}"

# Ověří, že externí nástroje existují. `command -v` v zsh vrací i aliasy,
# proto se ptáme na spustitelný soubor.
require_tools() {
  local t missing=()
  for t in "$@"; do
    [[ -x "$(command -v "$t" 2>/dev/null)" ]] || missing+=("$t")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "CHYBA: chybí nástroje: ${missing[*]}" >&2
    echo "       Nainstaluj je (brew install ${missing[*]}) a zkus znovu." >&2
    return 1
  fi
}

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

# Vypíše úvodní blok komentářů daného skriptu jako nápovědu.
# Záměrně bez fixních čísel řádků — ta se rozejdou při první editaci.
usage_from_header() {
  awk 'NR==1 {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$1"
}

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "CHYBA: $name není nastavená v $ENV_FILE" >&2
    return 1
  fi
}

# --------------------------------------------------------------------------
# Klasifikace selhání. Rozlišit drift schématu od chyby auth je zásadní:
# obnovovat discovery na 401 by znamenalo smyčku, která nic nespraví.
#
# atl_classify <http_status> <soubor_s_telem>  → schema|endpoint|auth|perm|conflict|request|unknown
atl_classify() {
  local st="$1" f="$2" body
  body="$(head -c 3000 "$f" 2>/dev/null || true)"
  case "$st" in
    401) echo auth;     return ;;
    403) echo perm;     return ;;
    409) echo conflict; return ;;
    3*)  echo endpoint; return ;;
    404) echo endpoint; return ;;
    400)
      # Jira u chybného payloadu vrací {"errors":{"customfield_X":"...","summary":"..."}}
      # Právě to je signatura driftu schématu (nové/změněné povinné pole).
      if printf '%s' "$body" | grep -q '"errors"[[:space:]]*:[[:space:]]*{[^}]'; then
        echo schema
      else
        echo request
      fi
      return ;;
  esac
  echo unknown
}

# Seznam povinných polí z uloženého discovery — pro diff před/po obnovení.
atl_required_snapshot() {
  local f="$REPO_ROOT/config/instances.json"
  [[ -f "$f" ]] || return 0
  jq -r '[(.jira.create // [])[] | "\(.type): \(.required | sort | join(","))"] | sort[]' \
     "$f" 2>/dev/null || true
}

# Samoléčení. Obnoví dotčenou sekci discovery a řekne, co se změnilo.
# U ČTENÍ smí volající zkusit znovu; u ZÁPISU se záměrně nezkouší — nové
# povinné pole by znamenalo vymyslet hodnotu, a to je rozhodnutí uživatele.
# atl_selfheal <kind> <method> → 0 = obnoveno a lze zkusit znovu, 1 = neobnovuj
atl_selfheal() {
  local kind="$1" method="$2" before after
  [[ "${ATL_SELFHEAL:-1}" != "0" ]] || return 1
  [[ -z "${ATL_HEALING:-}" ]] || return 1     # už léčíme, nezacyklit se
  [[ "$kind" == "schema" ]] || return 1        # jen drift schématu

  echo "SAMOLÉČENÍ: 400 s chybami polí vypadá na změnu schématu — obnovuji discovery." >&2
  before="$(atl_required_snapshot)"
  if ATL_HEALING=1 "$REPO_ROOT/bin/atl-discover" --section jira >/dev/null 2>&1; then
    after="$(atl_required_snapshot)"
    if [[ "$before" == "$after" ]]; then
      echo "SAMOLÉČENÍ: povinná pole se nezměnila — chyba je v payloadu, ne ve schématu." >&2
    else
      echo "SAMOLÉČENÍ: povinná pole se ZMĚNILA:" >&2
      diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") \
        | grep '^[<>]' | sed 's/^/        /' >&2 || true
    fi
    if [[ "$method" == "GET" || "$method" == "HEAD" ]]; then
      return 0
    fi
    echo "SAMOLÉČENÍ: zápis se ZÁMĚRNĚ nezkouší znovu — doplň payload podle" >&2
    echo "        config/instances.json (.jira.create) a zavolej to znovu sám." >&2
    return 1
  fi
  echo "SAMOLÉČENÍ: obnovení discovery selhalo — zkus bin/atl-auth-check." >&2
  return 1
}

# atl_curl <base_url> <token> <method> <path> [curl args...]
#
# Token se předává curlu konfigurací na stdin (-K -), NE přes -H v argv.
# Argumenty procesu jsou čitelné pro každý lokální proces přes `ps`, takže
# `-H "Authorization: Bearer $token"` by token vystavil. Ověřeno měřením:
# před opravou 1 proces curl s tokenem v argv, po opravě 0.
# Důsledek: stdin je obsazený → data posílej přes `-d @soubor`, ne `-d @-`.
#
# Návratový kód JE směrodatný: `--fail-with-body` dá nenulový rc na HTTP >=400
# (a tělo přesto vypíše), 3xx se kontroluje zvlášť.
#
# Tělo jde do temp souboru a pak na stdout — je potřeba ho umět přečíst pro
# klasifikaci selhání. Nepředávej vlastní -o.
#
# Proměnné:
#   ATL_TIMEOUT    timeout requestu v sekundách (default 30)
#   ATL_DRY_RUN=1  nic nezapíše — u jiné metody než GET/HEAD jen vypíše, co by udělal
#   ATL_SELFHEAL=0 vypne samoléčení (discovery si ho vypíná, aby se nezacyklila)
atl_curl() {
  local base="$1" token="$2" method="$3" path="$4"
  shift 4

  if [[ "${ATL_DRY_RUN:-}" == "1" && "$method" != "GET" && "$method" != "HEAD" ]]; then
    echo "DRY RUN: neprovedeno — $method ${base}${path}" >&2
    [[ $# -gt 0 ]] && echo "DRY RUN: další argumenty: $*" >&2
    return 0
  fi

  # Guard: -v/--verbose/--trace* vypíší hlavičku Authorization, tedy token,
  # do stderr a odtud do transkriptu. Ověřeno jako reálný únik → odmítáme.
  local a
  for a in "$@"; do
    case "$a" in
      -v|--verbose|--trace|--trace-ascii|--trace-all|--trace-config)
        echo "CHYBA: $a je zakázané — vypsalo by hlavičku Authorization (token) na výstup." >&2
        return 2 ;;
    esac
  done

  local hdr body rc status kind
  hdr="$(mktemp -t atl_hdr)" || return 1
  body="$(mktemp -t atl_body)" || { rm -f "$hdr"; return 1; }

  # `|| rc=$?` je nutné: volající skripty běží se `set -e`, které by je při
  # nenulovém rc z curlu ukončilo ještě před vyhodnocením statusu níž.
  rc=0
  printf 'header = "Authorization: Bearer %s"\n' "$token" | curl -sS -K - \
    --fail-with-body \
    --max-time "${ATL_TIMEOUT:-30}" \
    -D "$hdr" -o "$body" \
    -X "$method" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    "$@" \
    "${base}${path}" || rc=$?

  status="$(awk 'NR==1{print $2}' "$hdr" 2>/dev/null)"
  cat "$body"

  if [[ $rc -eq 0 && "${status:-}" == 2* ]]; then
    rm -f "$hdr" "$body"; return 0
  fi

  kind="$(atl_classify "${status:-000}" "$body")"
  printf 'CHYBA: %s %s — HTTP %s (%s), curl rc=%s\n' \
    "$method" "$path" "${status:-neznámý}" "$kind" "$rc" >&2
  case "$kind" in
    auth)     echo "        PAT neplatný nebo vypršel. Ověř: bin/atl-auth-check" >&2 ;;
    perm)     echo "        Token platný, chybí oprávnění. Discovery to nespraví." >&2 ;;
    conflict) echo "        Confluence: version.number musí být aktuální + 1. Načti stránku znovu." >&2 ;;
    endpoint) echo "        Endpoint v této verzi neexistuje (na DC typicky /rest/api/3," >&2
              echo "        nebo starý tvar createmeta). Tělo NEJSOU data." >&2 ;;
    schema)   : ;;
    request)  echo "        Payload odmítnut, ale bez chyb polí — zkontroluj JQL/CQL a syntaxi." >&2 ;;
  esac

  if atl_selfheal "$kind" "$method"; then
    rm -f "$hdr" "$body"
    echo "SAMOLÉČENÍ: schéma obnoveno, opakuji čtení." >&2
    ATL_HEALING=1 atl_curl "$base" "$token" "$method" "$path" "$@"
    return $?
  fi

  rm -f "$hdr" "$body"
  [[ $rc -ne 0 ]] && return "$rc"
  return 22
}

#!/usr/bin/env sh

# shellcheck disable=SC2034
dns_matchdns_info='MatchDNS.com
Site: MatchDNS.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_matchdns
Options:
 MATCHDNS_KEY API Key from the dashboard (scopes: read + records:write)
 MATCHDNS_API API base url. Default "https://www.matchdns.com". Optional.
Issues: github.com/acmesh-official/acme.sh/issues/7373
Author: MatchDNS <support@matchdns.com>'

MATCHDNS_API="${MATCHDNS_API:-https://www.matchdns.com}"

################  internal helpers  ################

# _matchdns_rest <method> <path> [json_body]
# stdout = response body; non-zero on HTTP error.
_matchdns_rest() {
  _m="$1"
  _ep="$2"
  _data="$3"
  _debug2 "matchdns API: $_m $_ep $_data"
  export _H1="X-API-Key: $MATCHDNS_KEY"
  export _H2="Content-Type: application/json"
  if [ "$_m" = "GET" ]; then
    _response="$(_get "$MATCHDNS_API$_ep")"
  else
    _response="$(_post "$_data" "$MATCHDNS_API$_ep" "" "$_m")"
  fi
  _ret=$?
  if [ "$_ret" != "0" ]; then
    _err "MatchDNS API request failed ($_m $_ep): $_response"
    return 1
  fi
  # acme.sh's _get/_post report HTTP 4xx/5xx as success (curl runs without
  # --fail), so a transport-level zero does not mean the call worked: check the
  # status line AND the body. A plain-text 404 (route miss) carries no platform
  # error envelope, so the envelope check alone would let it pass as success.
  if [ -n "$HTTP_HEADER" ] && [ -f "$HTTP_HEADER" ]; then
    _mdstat="$(grep '^HTTP' "$HTTP_HEADER" | _tail_n 1 | cut -d ' ' -f 2)"
    if [ -n "$_mdstat" ] && [ "$_mdstat" != "200" ] && [ "$_mdstat" != "201" ]; then
      _err "MatchDNS API HTTP $_mdstat ($_m $_ep): $_response"
      return 1
    fi
  fi
  # Every platform error uses the {"error":{"code":...}} envelope and no
  # success response (zones/records lists, {"status":...}, created record)
  # carries a "code" key.
  if _contains "$_response" '"code":"'; then
    _err "MatchDNS API error ($_m $_ep): $_response"
    return 1
  fi
  printf "%s" "$_response"
}

# _matchdns_get_root <fulldomain>
# Longest-suffix zone discovery via ?name= exact lookup.
# Sets: _matchdns_zone_id, _matchdns_zone (no trailing dot).
_matchdns_get_root() {
  _fd="$1"
  _i=2
  _p=1
  while [ "$_p" -lt 6 ]; do
    _h="$(printf "%s" "$_fd" | cut -d . -f "$_i"-1000)"
    if [ -z "$_h" ]; then
      break
    fi
    _debug "trying zone: $_h"
    _resp="$(_matchdns_rest GET "/api/v1/zones?name=$_h")" || return 1
    # The zone object is serialized from a Go map (alphabetical key order —
    # "created_at" sorts before "id"), so never anchor on field positions:
    # take the first "id": in the body. The ?name= filter is an exact match,
    # the response holds at most one zone, so that id is the zone id.
    _zid="$(printf "%s" "$_resp" | _egrep_o '"id":[0-9][0-9]*' | _head_n 1 | cut -d : -f 2)"
    if [ -n "$_zid" ]; then
      _matchdns_zone_id="$_zid"
      _matchdns_zone="$_h"
      _debug "zone found: $_h (id=$_zid)"
      return 0
    fi
    _i=$((_i + 1))
    _p=$((_p + 1))
  done
  _err "No zone found for $_fd (is the domain added and active in MatchDNS?)"
  return 1
}

# _matchdns_setup
# Load & persist credential; fail fast when missing.
_matchdns_setup() {
  MATCHDNS_KEY="${MATCHDNS_KEY:-$(_readaccountconf_mutable MATCHDNS_KEY)}"
  MATCHDNS_API="${MATCHDNS_API:-$(_readaccountconf_mutable MATCHDNS_API)}"
  if [ -z "$MATCHDNS_KEY" ]; then
    MATCHDNS_KEY=""
    _err "MATCHDNS_KEY is not set."
    _err "Create an API Key in the MatchDNS dashboard (scopes: read + records:write),"
    _err "then: export MATCHDNS_KEY=\"sdns-ak-xxxx\" and retry."
    return 1
  fi
  _saveaccountconf_mutable MATCHDNS_KEY "$MATCHDNS_KEY"
  _saveaccountconf_mutable MATCHDNS_API "$MATCHDNS_API"
  MATCHDNS_API="${MATCHDNS_API:-https://www.matchdns.com}"
  return 0
}

# _matchdns_list_txt <zone_id> <relative_name>
# Fetch the TXT records for a name. Sets _matchdns_records: one
# "id|line_id|policy|values_json" row per record (columns zipped — RecordIO
# serializes one "id"/"line_id"/"policy"/"values" per record, in order).
# Extraction anchors, all safe against user string values (remark etc.):
#  - JSON escapes quotes inside string values (\"), so a key pattern like
#    "id": or "values":[ can never be forged from remark/name_display text
#  - the values array is matched STRUCTURALLY from its own "values":[{ anchor
#    instead of "record start → first ]": a remark containing a bare ] (JSON
#    does not escape brackets) would truncate that segment and silently drop
#    the real values — the anchor sits after remark, and TXT values are
#    base64url, so the first ] after it always closes the values array
_matchdns_list_txt() {
  _mdzid="$1"
  _mdname="$2"
  _mdresp="$(_matchdns_rest GET "/api/v1/zones/${_mdzid}/records?name=${_mdname}&type=TXT")" || return 1
  if ! _contains "$_mdresp" '"id":'; then
    _matchdns_records=""
    return 0
  fi
  _mdids="$(printf "%s" "$_mdresp" | _egrep_o '"id":[0-9][0-9]*' | cut -d : -f 2 | tr -d '[:space:]')"
  _mdlines="$(printf "%s" "$_mdresp" | _egrep_o '"line_id":[0-9][0-9]*' | cut -d : -f 2 | tr -d '[:space:]')"
  _mdpols="$(printf "%s" "$_mdresp" | _egrep_o '"policy":"[a-z_]*"' | cut -d '"' -f 4)"
  _mdvals="$(printf "%s" "$_mdresp" | _egrep_o '"values":\[\{"value":"[^"]*"[^]]*\]')"
  # zip the four columns row by row (sed -n Np keeps it pure POSIX; a record
  # list here is at most a handful of same-name TXT lines)
  _matchdns_records=""
  _mdcount="$(printf "%s\n" "$_mdids" | grep -c .)"
  _mdi=1
  while [ "$_mdi" -le "$_mdcount" ]; do
    _matchdns_records="${_matchdns_records}$(printf "%s\n" "$_mdids" | sed -n "${_mdi}p")|$(printf "%s\n" "$_mdlines" | sed -n "${_mdi}p")|$(printf "%s\n" "$_mdpols" | sed -n "${_mdi}p")|$(printf "%s\n" "$_mdvals" | sed -n "${_mdi}p")
"
    _mdi=$((_mdi + 1))
  done
  return 0
}

################  acme.sh entry points  ################

# dns_matchdns_add <fulldomain(_acme-challenge.x)> <txtvalue>
# The platform keeps one record per (name, type, line) and serves multi-value
# TXT, so wildcard issuances ("-d example.com -d '*.example.com'") must keep
# both challenge values in the SAME record: APPEND the value when a record
# already exists (never replace it), create the record otherwise.
dns_matchdns_add() {
  fulldomain="$1"
  txtvalue="$2"

  _matchdns_setup || return 1

  # the platform normalizes names to lower case and matches ?name= byte-exact
  fulldomain="$(printf "%s" "$fulldomain" | tr '[:upper:]' '[:lower:]')"

  _info "Adding TXT record via MatchDNS API"
  _matchdns_get_root "$fulldomain" || return 1

  # relative name under the zone (_acme-challenge / _acme-challenge.sub)
  _mdsub="$(printf "%s" "$fulldomain" | sed "s/\.${_matchdns_zone}\$//")"
  if [ "$_mdsub" = "$fulldomain" ]; then
    _mdsub="@"
  fi
  _debug "zone=$_matchdns_zone id=$_matchdns_zone_id name=$_mdsub"

  _matchdns_list_txt "$_matchdns_zone_id" "$_mdsub" || return 1
  _mdfirst="$(printf "%s\n" "$_matchdns_records" | _head_n 1)"

  if [ -n "$_mdfirst" ]; then
    # split the row with cut, NEVER with ${x%%|*}/${x#*|} patterns: OpenBSD's
    # /bin/sh treats "|" as alternation in parameter-expansion patterns, so
    # %%|* eats the whole row and yields an empty record id (blind PUT to
    # /api/v1/records/). cut keeps the splitting literal on every POSIX shell.
    _mdrid="$(printf "%s" "$_mdfirst" | cut -d "|" -f 1)"
    # a parsed row MUST carry the record id: an empty id would send the PUT to
    # /api/v1/records/ (route miss, plain-text 404) and silently corrupt the
    # wildcard append — fail loudly instead
    if [ -z "$_mdrid" ]; then
      _err "TXT record row parsed without id - refusing blind update: $_mdfirst"
      return 1
    fi
    _mdline="$(printf "%s" "$_mdfirst" | cut -d "|" -f 2)"
    _mdpol="$(printf "%s" "$_mdfirst" | cut -d "|" -f 3)"
    _mdrest="$(printf "%s" "$_mdfirst" | cut -d "|" -f 4-)"
    # the existing values MUST be re-parsed: writing a record without them
    # would replace (wipe) the co-existing challenge values
    if [ -z "$_mdrest" ]; then
      _err "TXT record id=$_mdrid parsed without values - refusing replace."
      return 1
    fi
    # re-emit every existing value; return early when txtvalue is already there
    _mdvals=""
    while IFS= read -r _mdv; do
      [ -n "$_mdv" ] || continue
      if [ "$_mdv" = "$txtvalue" ]; then
        _info "TXT record id=$_mdrid already holds the value — nothing to add."
        return 0
      fi
      _mdvals="${_mdvals}{\"value\":\"${_mdv}\"},"
    done <<MDEOF
$(printf "%s" "$_mdrest" | _egrep_o '"value":"[^"]*"' | cut -d '"' -f 4)
MDEOF
    _mdvals="${_mdvals}{\"value\":\"${txtvalue}\"}"
    _mdbody="{\"name\":\"${_mdsub}\",\"type\":\"TXT\",\"ttl\":600,\"line_id\":${_mdline:-0},\"policy\":\"${_mdpol:-all}\",\"values\":[${_mdvals}]}"
    _info "Appending value to existing TXT record id=$_mdrid."
    _matchdns_rest PUT "/api/v1/records/${_mdrid}" "$_mdbody" || return 1
    _info "TXT record updated (\"${_mdsub}\" += \"${txtvalue}\")."
    return 0
  fi

  # ttl pinned to 600: it meets every plan's floor (the free tier minimum is
  # 600) and stays inside the absolute 10-86400 window, so a challenge record
  # never trips record.ttl_below_plan / record.bad_ttl. "policy" is REQUIRED —
  # the API rejects a record body without it (400 record.bad_policy), and
  # "all" is the right policy for a multi-value TXT challenge record.
  _mdbody="{\"name\":\"${_mdsub}\",\"type\":\"TXT\",\"ttl\":600,\"policy\":\"all\",\"values\":[{\"value\":\"${txtvalue}\"}]}"
  _matchdns_rest POST "/api/v1/zones/${_matchdns_zone_id}/records" "$_mdbody" || return 1

  _info "TXT record added (\"${_mdsub}\" → \"${txtvalue}\")."
  return 0
}

# dns_matchdns_rm <fulldomain(_acme-challenge.x)> <txtvalue>
# Strip ONLY the matching value from every record holding it; a record gets
# deleted (soft delete, 30-day trash) only when that was its last value.
dns_matchdns_rm() {
  fulldomain="$1"
  txtvalue="$2"

  _matchdns_setup || return 1

  fulldomain="$(printf "%s" "$fulldomain" | tr '[:upper:]' '[:lower:]')"

  _info "Removing TXT record value via MatchDNS API"
  _matchdns_get_root "$fulldomain" || return 1

  _mdsub="$(printf "%s" "$fulldomain" | sed "s/\.${_matchdns_zone}\$//")"
  if [ "$_mdsub" = "$fulldomain" ]; then
    _mdsub="@"
  fi

  _matchdns_list_txt "$_matchdns_zone_id" "$_mdsub" || return 1

  _mdremoved=0
  while IFS='|' read -r _mdrid _mdline _mdpol _mdvjson; do
    [ -n "$_mdrid" ] || continue
    _mdhit=0
    _mdkeep=""
    while IFS= read -r _mdv; do
      [ -n "$_mdv" ] || continue
      if [ "$_mdv" = "$txtvalue" ]; then
        _mdhit=1
      else
        _mdkeep="${_mdkeep}{\"value\":\"${_mdv}\"},"
      fi
    done <<MDEOF
$(printf "%s" "$_mdvjson" | _egrep_o '"value":"[^"]*"' | cut -d '"' -f 4)
MDEOF
    if [ "$_mdhit" != "1" ]; then
      continue
    fi
    _mdremoved=1
    if [ -n "$_mdkeep" ]; then
      _mdkeep="${_mdkeep%,}"
      _mdbody="{\"name\":\"${_mdsub}\",\"type\":\"TXT\",\"ttl\":600,\"line_id\":${_mdline:-0},\"policy\":\"${_mdpol:-all}\",\"values\":[${_mdkeep}]}"
      _info "Stripping value from TXT record id=$_mdrid (other values kept)."
      _matchdns_rest PUT "/api/v1/records/${_mdrid}" "$_mdbody" || return 1
    else
      _info "Deleting TXT record id=$_mdrid (the value was its last one)."
      _matchdns_rest DELETE "/api/v1/records/${_mdrid}" || return 1
    fi
  done <<EOF
$_matchdns_records
EOF

  if [ "$_mdremoved" = "0" ]; then
    _info "No matching TXT value found — nothing to remove."
  else
    _info "TXT challenge value removed."
  fi
  return 0
}

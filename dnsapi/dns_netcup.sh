#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_netcup_info='netcup.eu
Domains: netcup.de netcup.net
Site: netcup.eu/
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_netcup
Options:
 NC_Apikey API Key. The new netcup REST API key (64 characters) or the legacy CCP API key
 NC_Apipw API Password. Only used for the legacy CCP API
 NC_CID Customer Number. Only used for the legacy CCP API
 NC_Apikey_Legacy Legacy CCP API Key. Only used for domains not manageable via the REST API when NC_Apikey holds a new netcup REST API key. Optional.
Author: linux-insideDE
'

NC_Apikey="${NC_Apikey:-$(_readaccountconf_mutable NC_Apikey)}"
NC_Apipw="${NC_Apipw:-$(_readaccountconf_mutable NC_Apipw)}"
NC_CID="${NC_CID:-$(_readaccountconf_mutable NC_CID)}"
NC_Apikey_Legacy="${NC_Apikey_Legacy:-$(_readaccountconf_mutable NC_Apikey_Legacy)}"
end="https://ccp.netcup.net/run/webservice/servers/endpoint.php?JSON"
_nc_endrest="https://api.netcup.com/v1"
client=""

dns_netcup_add() {
  fulldomain=$1
  txtvalue=$2
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _nc_check_credentials; then
    return 1
  fi
  _saveaccountconf_mutable NC_Apikey "$NC_Apikey"
  if [ -n "$NC_Apipw" ]; then
    _saveaccountconf_mutable NC_Apipw "$NC_Apipw"
  fi
  if [ -n "$NC_CID" ]; then
    _saveaccountconf_mutable NC_CID "$NC_CID"
  fi
  if [ -n "$NC_Apikey_Legacy" ]; then
    _saveaccountconf_mutable NC_Apikey_Legacy "$NC_Apikey_Legacy"
  fi

  if _nc_is_rest_key; then
    _nc_rest_add "$fulldomain" "$txtvalue"
  else
    _nc_apikey="$NC_Apikey"
    _nc_legacy_add "$fulldomain" "$txtvalue"
  fi
}

dns_netcup_rm() {
  fulldomain=$1
  txtvalue=$2
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _nc_check_credentials; then
    return 1
  fi

  if _nc_is_rest_key; then
    _nc_rest_rm "$fulldomain" "$txtvalue"
  else
    _nc_apikey="$NC_Apikey"
    _nc_legacy_rm "$fulldomain" "$txtvalue"
  fi
}

####################  New netcup REST API (api.netcup.com)  ####################

_nc_rest_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _nc_rest_get_domain "$fulldomain"; then
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _dns_managed "$_dns_managed"

  if [ "$_dns_managed" = "false" ]; then
    _nc_rest_use_legacy "$_domain" || return 1
    _nc_legacy_add "$fulldomain" "$txtvalue"
    return
  fi
  if [ "$_dns_managed" != "true" ]; then
    _err "Unable to read isDnsManaged for $_domain from the netcup REST API response: $response"
    return 1
  fi

  case "$fulldomain" in
  _acme-challenge.*) ;;
  acmetestXyzRandomName.*)
    # The synthetic record of the DNS-API-Test, which expects add and
    # rm to succeed. The REST API can only manage _acme-challenge
    # records, so skip it. Real records are never treated as a no-op.
    _info "Skipping the DNS-API-Test record $fulldomain, the netcup REST API can only manage _acme-challenge records."
    return 0
    ;;
  *)
    # e.g. a challenge alias given in the "=" form without the prefix
    if [ -n "$NC_Apikey_Legacy" ] && [ -n "$NC_Apipw" ] && [ -n "$NC_CID" ]; then
      _debug "The netcup REST API can only create _acme-challenge records, using the legacy CCP API for $fulldomain"
      _nc_apikey="$NC_Apikey_Legacy"
      _nc_legacy_add "$fulldomain" "$txtvalue"
      return
    fi
    _err "The netcup REST API can only create _acme-challenge records, unable to create $fulldomain."
    _err "Set NC_Apikey_Legacy, NC_Apipw and NC_CID to manage it via the legacy CCP API."
    return 1
    ;;
  esac

  _nc_rest_get_scope "$fulldomain" "$_domain"
  _debug _scope "$_scope"

  if ! _nc_rest POST "domain/$_domain_id/acme/challenge" "{\"scope\": \"$_scope\", \"value\": \"$txtvalue\"}" ||
    ! _contains "$response" '"success": *true'; then
    _err "Unable to add the challenge record: $response"
    return 1
  fi

  # The challenge record is added to the zone right away, but deploying
  # the zone to the nameservers happens in the background, so poll until
  # the record has actually been deployed (up to about 60 seconds).
  _nc_tries=0
  while true; do
    if _nc_rest GET "domain/$_domain_id/acme/challenge/$_scope/$txtvalue" &&
      _contains "$response" '"status": *"deployed"'; then
      _info "The challenge record has been deployed"
      return 0
    fi
    _nc_tries=$(_math "$_nc_tries" + 1)
    if [ "$_nc_tries" -ge 12 ]; then
      break
    fi
    _debug "The challenge record has not been deployed yet, waiting 5 more seconds"
    _sleep 5
  done
  _info "The challenge record has still not been deployed after 60 seconds, continuing anyway"
  return 0
}

_nc_rest_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _nc_rest_get_domain "$fulldomain"; then
    return 1
  fi

  if [ "$_dns_managed" = "false" ]; then
    _nc_rest_use_legacy "$_domain" || return 1
    _nc_legacy_rm "$fulldomain" "$txtvalue"
    return
  fi
  if [ "$_dns_managed" != "true" ]; then
    _err "Unable to read isDnsManaged for $_domain from the netcup REST API response: $response"
    return 1
  fi

  case "$fulldomain" in
  _acme-challenge.*) ;;
  acmetestXyzRandomName.*)
    # See _nc_rest_add.
    _info "Skipping the DNS-API-Test record $fulldomain, the netcup REST API can only manage _acme-challenge records."
    return 0
    ;;
  *)
    if [ -n "$NC_Apikey_Legacy" ] && [ -n "$NC_Apipw" ] && [ -n "$NC_CID" ]; then
      _debug "The netcup REST API can only remove _acme-challenge records, using the legacy CCP API for $fulldomain"
      _nc_apikey="$NC_Apikey_Legacy"
      _nc_legacy_rm "$fulldomain" "$txtvalue"
      return
    fi
    _err "The netcup REST API can only remove _acme-challenge records, unable to remove $fulldomain."
    _err "Set NC_Apikey_Legacy, NC_Apipw and NC_CID to manage it via the legacy CCP API."
    return 1
    ;;
  esac

  _nc_rest_get_scope "$fulldomain" "$_domain"

  if ! _nc_rest DELETE "domain/$_domain_id/acme/challenge/$_scope/$txtvalue"; then
    _err "Unable to remove the challenge record: $response"
    return 1
  fi
  _nc_status=$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d '\r\n')
  _debug _nc_status "$_nc_status"
  case "$_nc_status" in
  204)
    return 0
    ;;
  404)
    _info "The challenge record was not found, nothing to remove"
    return 0
    ;;
  *)
    _err "Unable to remove the challenge record: $response"
    return 1
    ;;
  esac
}

# fulldomain
# Sets _domain_id, _domain and _dns_managed of the domain the record
# belongs to, walking up the name, longest match first. For a challenge
# record the leftmost label is the prefix and can never be a zone, so
# the walk starts one label in. Other names (e.g. a challenge alias in
# the "=" form) may be a zone apex themselves.
_nc_rest_get_domain() {
  case "$1" in
  _acme-challenge.*) i=2 ;;
  *) i=1 ;;
  esac
  while true; do
    h=$(printf "%s" "$1" | cut -d . -f "$i"-100)
    if [ -z "$h" ]; then
      _nc_nozone "$1"
      return 1
    fi
    _debug h "$h"
    if ! _nc_rest GET "domain?fqdn=$h"; then
      return 1
    fi
    if ! _contains "$response" '"success": *true'; then
      # e.g. an invalid API key; do not walk on, it would end in a
      # misleading "no zone found" error
      _err "The netcup REST API request failed: $response"
      _err "Note: NC_Apikey was detected as a netcup REST API key because it is 64 characters long."
      return 1
    fi
    if _contains "$response" '"fqdn"'; then
      # split the response so that first/last match cannot differ
      # between the egrep and sed implementations of _egrep_o
      _domain_id=$(printf "%s" "$response" | tr '{,' '\n' | _egrep_o '"id": *[0-9][0-9]*' | _head_n 1 | tr -dc '0-9')
      _dns_managed=$(printf "%s" "$response" | tr '{,' '\n' | _egrep_o '"isDnsManaged": *[a-z][a-z]*' | _head_n 1 | sed 's/.*: *//')
      _domain="$h"
      if [ -n "$_domain_id" ]; then
        return 0
      fi
      _err "Unable to parse the domain id from the netcup REST API response: $response"
      return 1
    fi
    i=$(_math "$i" + 1)
  done
}

# fulldomain domain
# Sets _scope to the host part of the challenge relative to the domain.
# The REST API prepends _acme-challenge. to the scope itself, so the
# prefix is stripped from the record name (the callers guarantee it is
# present).
_nc_rest_get_scope() {
  _scope="${1#_acme-challenge.}"
  if [ "$_scope" = "$2" ]; then
    _scope="@"
  else
    _scope="${_scope%".$2"}"
  fi
}

# domain
# Selects the legacy credentials for a domain whose DNS cannot be
# managed via the new netcup REST API.
_nc_rest_use_legacy() {
  _debug "The DNS of $1 cannot be managed via the REST API, using the legacy CCP API"
  if [ -z "$NC_Apikey_Legacy" ] || [ -z "$NC_Apipw" ] || [ -z "$NC_CID" ]; then
    _err "The DNS of the domain $1 cannot be managed via the new netcup REST API."
    _err "Set NC_Apikey_Legacy, NC_Apipw and NC_CID to your legacy CCP API credentials to manage it."
    return 1
  fi
  _nc_apikey="$NC_Apikey_Legacy"
}

# method endpoint [data]
# The response is returned in the global variable $response.
_nc_rest() {
  m=$1
  ep=$2
  data=$3
  _debug2 "REST $m $ep"

  export _H1="Authorization: Bearer $NC_Apikey"
  # blank the remaining header slots so that auth headers of another
  # dns hook cannot ride into the netcup REST API in a multi-provider
  # issuance
  export _H2=""
  export _H3=""
  export _H4=""
  export _H5=""
  if [ "$m" = "GET" ]; then
    response=$(_get "$_nc_endrest/$ep")
  else
    _debug2 data "$data"
    response=$(_post "$data" "$_nc_endrest/$ep" "" "$m" "application/json")
  fi
  _nc_ret="$?"
  _debug2 response "$response"
  return "$_nc_ret"
}

####################  Legacy CCP API (ccp.netcup.net)  ####################

_nc_legacy_add() {
  fulldomain=$1
  txtvalue=$2
  if ! _nc_legacy_login; then
    return 1
  fi
  domain=""
  exit=$(echo "$fulldomain" | tr -dc '.' | wc -c)
  exit=$(_math "$exit" + 1)
  i=$exit
  _nc_last=$(_nc_lastlevel "$i")
  _nc_found=""

  while
    [ "$exit" -ge "$_nc_last" ]
  do
    tmp=$(echo "$fulldomain" | cut -d'.' -f"$exit")
    if [ "$(_math "$i" - "$exit")" -eq 0 ]; then
      domain="$tmp"
    else
      domain="$tmp.$domain"
    fi
    if [ "$(_math "$i" - "$exit")" -ge 1 ]; then
      msg=$(_post "{\"action\": \"updateDnsRecords\", \"param\": {\"apikey\": \"$_nc_apikey\", \"apisessionid\": \"$sid\", \"customernumber\": \"$NC_CID\",\"clientrequestid\": \"$client\" , \"domainname\": \"$domain\", \"dnsrecordset\": { \"dnsrecords\": [ {\"id\": \"\", \"hostname\": \"$fulldomain.\", \"type\": \"TXT\", \"priority\": \"\", \"destination\": \"$txtvalue\", \"deleterecord\": \"false\", \"state\": \"yes\"} ]}}}" "$end" "" "POST")
      _debug "$msg"
      if [ "$(_getfield "$msg" "5" | sed 's/"statuscode"://g')" != 5028 ]; then
        if [ "$(_getfield "$msg" "4" | sed s/\"status\":\"//g | sed s/\"//g)" != "success" ]; then
          _err "$msg"
          return 1
        else
          _nc_found=1
          break
        fi
      fi
    fi
    exit=$(_math "$exit" - 1)
  done
  if [ -z "$_nc_found" ]; then
    _err "$msg"
    _nc_nozone "$fulldomain"
    return 1
  fi
  _nc_legacy_logout
}

_nc_legacy_rm() {
  fulldomain=$1
  txtvalue=$2
  if ! _nc_legacy_login; then
    return 1
  fi

  domain=""
  exit=$(echo "$fulldomain" | tr -dc '.' | wc -c)
  exit=$(_math "$exit" + 1)
  i=$exit
  rec=""
  _nc_last=$(_nc_lastlevel "$i")
  _nc_found=""

  while
    [ "$exit" -ge "$_nc_last" ]
  do
    tmp=$(echo "$fulldomain" | cut -d'.' -f"$exit")
    if [ "$(_math "$i" - "$exit")" -eq 0 ]; then
      domain="$tmp"
    else
      domain="$tmp.$domain"
    fi
    if [ "$(_math "$i" - "$exit")" -ge 1 ]; then
      msg=$(_post "{\"action\": \"infoDnsRecords\", \"param\": {\"apikey\": \"$_nc_apikey\", \"apisessionid\": \"$sid\", \"customernumber\": \"$NC_CID\", \"domainname\": \"$domain\"}}" "$end" "" "POST")
      rec=$(echo "$msg" | sed 's/\[//g' | sed 's/\]//g' | sed 's/{\"serverrequestid\".*\"dnsrecords\"://g' | sed 's/},{/};{/g' | sed 's/{//g' | sed 's/}//g')
      _debug "$msg"
      if [ "$(_getfield "$msg" "5" | sed 's/"statuscode"://g')" != 5028 ]; then
        if [ "$(_getfield "$msg" "4" | sed s/\"status\":\"//g | sed s/\"//g)" != "success" ]; then
          _err "$msg"
          return 1
        else
          _nc_found=1
          break
        fi
      fi
    fi
    exit=$(_math "$exit" - 1)
  done
  if [ -z "$_nc_found" ]; then
    _err "$msg"
    _nc_nozone "$fulldomain"
    return 1
  fi

  ida=0000
  idv=0001
  ids=0000000000
  i=1
  while
    [ "$i" -ne 0 ]
  do
    specrec=$(_getfield "$rec" "$i" ";")
    idv="$ida"
    ida=$(_getfield "$specrec" "1" "," | sed 's/\"id\":\"//g' | sed 's/\"//g')
    txtv=$(_getfield "$specrec" "5" "," | sed 's/\"destination\":\"//g' | sed 's/\"//g')
    i=$(_math "$i" + 1)
    if [ "$txtvalue" = "$txtv" ]; then
      i=0
      ids="$ida"
    fi
    if [ "$ida" = "$idv" ]; then
      i=0
    fi
  done
  msg=$(_post "{\"action\": \"updateDnsRecords\", \"param\": {\"apikey\": \"$_nc_apikey\", \"apisessionid\": \"$sid\", \"customernumber\": \"$NC_CID\",\"clientrequestid\": \"$client\" , \"domainname\": \"$domain\", \"dnsrecordset\": { \"dnsrecords\": [ {\"id\": \"$ids\", \"hostname\": \"$fulldomain.\", \"type\": \"TXT\", \"priority\": \"\", \"destination\": \"$txtvalue\", \"deleterecord\": \"TRUE\", \"state\": \"yes\"} ]}}}" "$end" "" "POST")
  _debug "$msg"
  if [ "$(_getfield "$msg" "4" | sed s/\"status\":\"//g | sed s/\"//g)" != "success" ]; then
    _err "$msg"
    return 1
  fi
  _nc_legacy_logout
}

_nc_legacy_login() {
  # never send the REST API Bearer header (or auth headers of another
  # dns hook) to the legacy CCP API
  export _H1=""
  export _H2=""
  export _H3=""
  export _H4=""
  export _H5=""
  tmp=$(_post "{\"action\": \"login\", \"param\": {\"apikey\": \"$_nc_apikey\", \"apipassword\": \"$NC_Apipw\", \"customernumber\": \"$NC_CID\"}}" "$end" "" "POST")
  sid=$(echo "$tmp" | tr '{}' '\n' | grep apisessionid | cut -d '"' -f 4)
  _debug "$tmp"
  if [ "$(_getfield "$tmp" "4" | sed s/\"status\":\"//g | sed s/\"//g)" != "success" ]; then
    _err "$tmp"
    return 1
  fi
}

_nc_legacy_logout() {
  tmp=$(_post "{\"action\": \"logout\", \"param\": {\"apikey\": \"$_nc_apikey\", \"apisessionid\": \"$sid\", \"customernumber\": \"$NC_CID\"}}" "$end" "" "POST")
  _debug "$tmp"
  if [ "$(_getfield "$tmp" "4" | sed s/\"status\":\"//g | sed s/\"//g)" != "success" ]; then
    _err "$tmp"
    return 1
  fi
}

####################  Shared helpers  ####################

_nc_check_credentials() {
  if [ -z "$NC_Apikey" ]; then
    _err "No Credentials given"
    _err "Set NC_Apikey to your netcup REST API key (64 characters) or your legacy CCP API key."
    return 1
  fi
  if ! _nc_is_rest_key; then
    if [ -z "$NC_Apipw" ] || [ -z "$NC_CID" ]; then
      _err "No Credentials given"
      _err "The legacy CCP API needs NC_Apikey, NC_Apipw and NC_CID."
      return 1
    fi
  fi
}

# New netcup REST API keys are 64 characters long, legacy CCP API keys
# are 50, so the key length selects the API.
_nc_is_rest_key() {
  [ "${#NC_Apikey}" -eq 64 ]
}

# The legacy zone lookup walks the challenge name from the right, one
# label at a time. The leftmost label is the challenge prefix, so the
# full name itself can never be a zone: asking netcup for it only
# returns 4013 "Validation Error", which would then mask the real 5028
# "zone could not be found". Stop one label short, unless the name is
# too short to have a challenge prefix at all (manual invocation).
# levels
_nc_lastlevel() {
  if [ "$1" -ge 3 ]; then
    echo 2
  else
    echo 1
  fi
}

# fulldomain
_nc_nozone() {
  _err "No DNS zone for $1 was found at netcup."
  _err "Check that the domain belongs to the account of the configured credentials and that its DNS is hosted at netcup."
}

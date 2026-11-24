#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_wedos_info='WEDOS.com
Site: wedos.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_wedos
Options:
 WEDOS_Username WAPI login (account email)
 WEDOS_Wapipass WAPI password
Issues: github.com/acmesh-official/acme.sh/issues/7071
Author: Jan Forman <jforman@jflab.cz>
'

WEDOS_Api="https://api.wedos.com/wapi/json"

########  Public functions #####################

#Usage: dns_wedos_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_wedos_add() {
  fulldomain=$(echo "$1" | _lower_case)
  txtvalue=$2

  if ! _wedos_init; then
    return 1
  fi

  _debug "Detecting root zone for $fulldomain"
  if ! _get_root "$fulldomain"; then
    _err "Cannot determine root zone for: $fulldomain"
    return 1
  fi
  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"

  _info "Adding TXT record: $_sub_domain.$_domain"
  if ! _wedos_request "dns-row-add" "{\"domain\":\"$_domain\",\"name\":\"$_sub_domain\",\"ttl\":\"300\",\"type\":\"TXT\",\"rdata\":\"$txtvalue\"}"; then
    _err "Failed to add TXT record"
    return 1
  fi

  _info "Committing DNS changes for $_domain"
  if ! _wedos_request "dns-domain-commit" "{\"name\":\"$_domain\"}"; then
    _err "Failed to commit DNS changes"
    return 1
  fi

  return 0
}

#Usage: dns_wedos_rm   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_wedos_rm() {
  fulldomain=$(echo "$1" | _lower_case)
  txtvalue=$2

  if ! _wedos_init; then
    return 1
  fi

  _debug "Detecting root zone for $fulldomain"
  if ! _get_root "$fulldomain"; then
    _err "Cannot determine root zone for: $fulldomain"
    return 1
  fi
  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"

  # _get_root leaves the dns-rows-list response for $_domain in $response
  _debug "Looking up row IDs for TXT value: $txtvalue"
  _row_ids=$(echo "$response" | tr '{' '\n' | grep -F -- "\"rdata\":\"$txtvalue\"" | grep -F -- "\"name\":\"$_sub_domain\"" | _egrep_o '"ID": *"[0-9]*"' | tr -dc '0-9\n')
  _debug _row_ids "$_row_ids"

  if [ -z "$_row_ids" ]; then
    _info "TXT record not found, nothing to remove"
    return 0
  fi

  for _row_id in $_row_ids; do
    _info "Removing TXT record ID $_row_id from $_domain"
    if ! _wedos_request "dns-row-delete" "{\"domain\":\"$_domain\",\"row_id\":\"$_row_id\"}"; then
      _err "Failed to delete TXT record"
      return 1
    fi
  done

  _info "Committing DNS changes for $_domain"
  if ! _wedos_request "dns-domain-commit" "{\"name\":\"$_domain\"}"; then
    _err "Failed to commit DNS changes"
    return 1
  fi

  return 0
}

####################  Private functions below ##################################

_wedos_init() {
  WEDOS_Username="${WEDOS_Username:-$(_readaccountconf_mutable WEDOS_Username)}"
  WEDOS_Wapipass="${WEDOS_Wapipass:-$(_readaccountconf_mutable WEDOS_Wapipass)}"

  if [ -z "$WEDOS_Username" ] || [ -z "$WEDOS_Wapipass" ]; then
    WEDOS_Username=""
    WEDOS_Wapipass=""
    _err "You didn't specify the WEDOS WAPI credentials yet."
    _err "Please export WEDOS_Username and WEDOS_Wapipass and try again."
    return 1
  fi

  _saveaccountconf_mutable WEDOS_Username "$WEDOS_Username"
  _saveaccountconf_mutable WEDOS_Wapipass "$WEDOS_Wapipass"
  return 0
}

# WAPI auth token: sha1(login + sha1(password) + hour), where the hour is
# the current hour on the WEDOS servers (Europe/Prague timezone).
# The POSIX TZ string is used so no tzdata is required on the client.
_wedos_auth() {
  if [ "$_wedos_utc" ]; then
    # fallback: WAPI accepts 1 hour of skew, UTC+1 fits both CET and CEST
    _wedos_hour=$(date -u +%H)
    _wedos_hour=$(printf '%02d' "$(((${_wedos_hour#0} + 1) % 24))")
  else
    _wedos_hour=$(TZ='CET-1CEST,M3.5.0,M10.5.0/3' date +%H)
  fi
  _wedos_phash=$(printf '%s' "$WEDOS_Wapipass" | _digest sha1 hex)
  printf '%s' "${WEDOS_Username}${_wedos_phash}${_wedos_hour}" | _digest sha1 hex
}

#Usage: _wedos_request <command> <data-json>
#Returns 0 and sets $response on WAPI code 1000, returns 1 otherwise.
_wedos_request() {
  _wedos_cmd="$1"
  _wedos_data="$2"

  _wedos_token=$(_wedos_auth)
  _secure_debug _wedos_token "$_wedos_token"

  _wedos_json="{\"request\":{\"user\":\"$WEDOS_Username\",\"auth\":\"$_wedos_token\",\"command\":\"$_wedos_cmd\",\"data\":$_wedos_data}}"
  _debug2 "WAPI command: $_wedos_cmd"
  _debug2 "WAPI data: $_wedos_data"

  # _post sends the global _H1.._H5 headers with every request; clear them so
  # headers from earlier API calls are not leaked to the WAPI endpoint.
  export _H1=""
  export _H2=""
  export _H3=""
  export _H4=""
  export _H5=""

  _wedos_body="request=$(printf '%s' "$_wedos_json" | _url_encode)"
  response=$(_post "$_wedos_body" "$WEDOS_Api" "" "POST" "application/x-www-form-urlencoded")
  if [ "$?" != "0" ]; then
    _err "WAPI request failed for command '$_wedos_cmd'"
    return 1
  fi
  _debug2 "WAPI response: $response"

  _wedos_code=$(echo "$response" | _egrep_o '"code": *[0-9]*' | _head_n 1 | tr -dc '0-9')
  _debug2 "WAPI result code: $_wedos_code"
  if [ "$_wedos_code" = "1000" ]; then
    return 0
  fi

  # some systems ignore the TZ variable (Haiku), sending a wrong auth hour;
  # retry once with the UTC fallback in _wedos_auth
  if [ "$_wedos_code" = "2050" ] && [ -z "$_wedos_utc" ]; then
    _wedos_utc=1
    _wedos_request "$_wedos_cmd" "$_wedos_data"
    return $?
  fi

  # 2050 = bad credentials, 2051 = IP not whitelisted, 2052 = IP blocked
  if [ "$_wedos_code" = "2050" ] || [ "$_wedos_code" = "2051" ] || [ "$_wedos_code" = "2052" ]; then
    _wedos_result=$(echo "$response" | _egrep_o '"result": *"[^"]*"' | _head_n 1 | cut -d '"' -f 4)
    _err "WAPI authentication error $_wedos_code: $_wedos_result"
    _err "Check WEDOS_Username, WEDOS_Wapipass and the WAPI IP whitelist."
    _wedos_autherr=1
    return 1
  fi

  _debug "WAPI error for command '$_wedos_cmd': $response"
  return 1
}

# Determine the registered domain (_domain) and subdomain prefix (_sub_domain)
# by walking up the labels and calling dns-rows-list until WAPI accepts one.
# _acme-challenge.www.example.co.uk
#   -> _sub_domain=_acme-challenge.www  _domain=example.co.uk
# The full domain itself is tried first, so a zone apex (e.g. DNS alias mode
# pointing at the registered domain) resolves to an empty _sub_domain.
_get_root() {
  _gr_full="$1"
  _gr_i=1
  _wedos_autherr=""
  while true; do
    _gr_candidate=$(printf '%s' "$_gr_full" | cut -d . -f "${_gr_i}"-100)
    _debug2 "Checking zone candidate: $_gr_candidate"
    if [ -z "$_gr_candidate" ]; then
      return 1
    fi

    if _wedos_request "dns-rows-list" "{\"domain\":\"$_gr_candidate\"}"; then
      _domain="$_gr_candidate"
      if [ "$_gr_i" = "1" ]; then
        _sub_domain=""
      else
        _sub_domain=$(printf '%s' "$_gr_full" | cut -d . -f 1-"$((_gr_i - 1))")
      fi
      return 0
    fi

    # auth error hits every candidate, stop the walk
    if [ "$_wedos_autherr" ]; then
      return 1
    fi

    _gr_i=$((_gr_i + 1))
  done
}

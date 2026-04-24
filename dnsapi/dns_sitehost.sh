#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_sitehost_info='SiteHost
Site: sitehost.nz
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_sitehost
Options:
 SITEHOST_API_KEY API Key
 SITEHOST_CLIENT_ID Client ID. The numeric client ID for your SiteHost account.
Issues: github.com/acmesh-official/acme.sh/issues/6892
Author: Jordan Russell <jordanbrussell@gmail.com>
'

SITEHOST_API="https://api.sitehost.nz/1.5"

########  Public functions #####################

# Usage: dns_sitehost_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_sitehost_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _sitehost_load_creds; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  # SiteHost expects the full record name as the name parameter
  _info "Adding TXT record for ${fulldomain}"
  if _sitehost_rest POST "dns/add_record.json" "client_id=$(printf '%s' "${SITEHOST_CLIENT_ID}" | _url_encode)&domain=$(printf '%s' "${_domain}" | _url_encode)&type=TXT&name=$(printf '%s' "${fulldomain}" | _url_encode)&content=$(printf '%s' "${txtvalue}" | _url_encode)"; then
    if _contains "$response" '"status":true'; then
      _info "TXT record added successfully."
      return 0
    fi
  fi

  _err "Could not add TXT record for ${fulldomain}"
  _err "$response"
  return 1
}

# Usage: dns_sitehost_rm   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Remove the txt record after validation.
dns_sitehost_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _sitehost_load_creds; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting TXT records for ${_domain}"
  if ! _sitehost_rest GET "dns/list_records.json" "client_id=$(printf '%s' "${SITEHOST_CLIENT_ID}" | _url_encode)&domain=$(printf '%s' "${_domain}" | _url_encode)"; then
    _err "Could not list DNS records"
    _err "$response"
    return 1
  fi

  if ! _contains "$response" '"status":true'; then
    _err "Error listing DNS records"
    _err "$response"
    return 1
  fi

  # Extract record ID matching our fulldomain, type TXT, and txtvalue
  # Response format: {"return":[{"id":"123","name":"...","type":"TXT","content":"..."},...]}
  # SiteHost returns flat single-line JSON objects in the records array
  # Escape regex metacharacters in values before grep matching
  _fulldomain_grep="$(printf "%s" "$fulldomain" | sed 's/[][\\.^$*]/\\&/g')"
  _txtvalue_grep="$(printf "%s" "$txtvalue" | sed 's/[][\\.^$*]/\\&/g')"
  # Use field-specific matching to avoid false positives from substring matches
  _record_id="$(echo "$response" | _egrep_o '\{[^}]*\}' | grep '"name" *: *"'"${_fulldomain_grep}"'"' | grep '"type" *: *"TXT"' | grep '"content" *: *"'"${_txtvalue_grep}"'"' | _head_n 1 | _egrep_o '"id" *: *"?[0-9]+"?' | _egrep_o '[0-9]+')"

  if [ -z "$_record_id" ]; then
    _info "TXT record not found, nothing to remove."
    return 0
  fi

  _debug _record_id "$_record_id"

  _info "Deleting TXT record ${_record_id} for ${fulldomain}"
  if _sitehost_rest POST "dns/delete_record.json" "client_id=$(printf '%s' "${SITEHOST_CLIENT_ID}" | _url_encode)&domain=$(printf '%s' "${_domain}" | _url_encode)&record_id=$(printf '%s' "${_record_id}" | _url_encode)"; then
    if _contains "$response" '"status":true'; then
      _info "TXT record deleted successfully."
      return 0
    fi
  fi

  _err "Could not delete TXT record for ${fulldomain}"
  _err "$response"
  return 1
}

####################  Private functions below ##################################

_sitehost_load_creds() {
  SITEHOST_API_KEY="${SITEHOST_API_KEY:-$(_readaccountconf_mutable SITEHOST_API_KEY)}"
  SITEHOST_CLIENT_ID="${SITEHOST_CLIENT_ID:-$(_readaccountconf_mutable SITEHOST_CLIENT_ID)}"

  if [ -z "$SITEHOST_API_KEY" ] || [ -z "$SITEHOST_CLIENT_ID" ]; then
    SITEHOST_API_KEY=""
    SITEHOST_CLIENT_ID=""
    _err "You didn't specify SITEHOST_API_KEY and/or SITEHOST_CLIENT_ID."
    _err "Please export them and try again."
    return 1
  fi

  _saveaccountconf_mutable SITEHOST_API_KEY "$SITEHOST_API_KEY"
  _saveaccountconf_mutable SITEHOST_CLIENT_ID "$SITEHOST_CLIENT_ID"
  return 0
}

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1

  _debug "Getting domain list"

  # Fetch ALL pages of domains first so we can match the most specific zone
  # (a more specific zone on a later page must take precedence over a broader match)
  _all_domains=""
  _page=1

  while true; do
    if ! _sitehost_rest GET "dns/list_domains.json" "client_id=$(printf '%s' "${SITEHOST_CLIENT_ID}" | _url_encode)&filters%5Bpage_number%5D=${_page}"; then
      _err "Could not list domains"
      return 1
    fi

    if ! _contains "$response" '"status":true'; then
      _err "Error listing domains"
      _err "$response"
      return 1
    fi

    _all_domains="${_all_domains} ${response}"

    _total_pages=$(echo "$response" | _egrep_o '"total_pages" *: *[0-9]+' | _egrep_o '[0-9]+')
    if [ -z "$_total_pages" ] || [ "$_page" -ge "$_total_pages" ]; then
      break
    fi

    _page=$(_math "$_page" + 1)
  done

  # Try each subdomain level, most specific first
  _i=1
  _p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "${_i}"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      return 1
    fi

    if echo "$_all_domains" | grep -F "\"${h}\"" >/dev/null 2>&1; then
      if [ "$_i" = "1" ]; then
        # DNS alias mode - fulldomain is the zone itself
        _sub_domain=""
      else
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"${_p}")
      fi
      _domain="${h}"
      return 0
    fi

    _p="${_i}"
    _i=$(_math "$_i" + 1)
  done

  return 1
}

# Usage: _sitehost_rest method endpoint data
_sitehost_rest() {
  m="$1"
  ep="$2"
  data="$3"
  url="${SITEHOST_API}/${ep}"

  _debug url "$url"

  _apikey="$(printf "%s" "${SITEHOST_API_KEY}" | _url_encode)"

  if [ "$m" = "GET" ]; then
    response="$(_get "${url}?apikey=${_apikey}&${data}")"
  else
    _debug2 data "$data"
    response="$(_post "apikey=${_apikey}&${data}" "$url")"
  fi

  if [ "$?" != "0" ]; then
    _err "error ${ep}"
    return 1
  fi

  response="$(printf '%s' "$response" | tr -d '\r')"

  _debug2 response "$response"
  return 0
}

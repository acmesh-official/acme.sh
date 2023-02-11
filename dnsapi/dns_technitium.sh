#!/usr/bin/env sh
#
# acme.sh DNS API plugin for Technitium DNS Server <https://technitium.com/dns/>
#
# Requires the following environment variables to be configured:
#
# DNS_WEB_URL:
#   - URL for the Technitium DNS web console which must including the scheme
#     and port, e.g. https://dns-server.example.com:53443
#
# DNS_API_TOKEN:
#   - Provide an API token with permission to create and remove records in the
#     target DNS zone. Review the documentation for the process to create a token:
#     https://github.com/TechnitiumSoftware/DnsServer/blob/master/APIDOCS.md#create-api-token
#

dns_technitium_add() {
  _fqdn="$1"
  _text="$2"

  if ! _check_dns_web_url_and_api_token; then
    return 1
  fi

  if ! _get_zone "$_fqdn"; then
    _err "Error: could not find zone for $_fqdn in Technitium DNS"
    return 1
  fi

  _add_record_url="${DNS_WEB_URL}/api/zones/records/add?token=${DNS_API_TOKEN}&domain=${_fqdn}&zone=${_zone}&type=TXT&ttl=300&text=${_text}"
  _response=$(_get "$_add_record_url" | _normalizeJson)

  if _contains "$_response" "\"status\":\"ok\""; then
    _info "Success: added DNS TXT record for ${_fqdn}"
    return 0
  else
    _err "Error: failed to add DNS TXT record for ${_fqdn}"
    return 1
  fi

}

dns_technitium_rm() {
  _fqdn="$1"
  _text="$2"

  if ! _check_dns_web_url_and_api_token; then
    return 1
  fi

  if ! _get_zone "$_fqdn"; then
    _err "Error: could not find zone for $_fqdn in Techitium DNS"
    return 1
  fi

  _remove_record_url="${DNS_WEB_URL}/api/zones/records/delete?token=${DNS_API_TOKEN}&domain=${_fqdn}&zone=${_zone}&type=TXT&text=${_text}"
  _response=$(_get "$_remove_record_url" | _normalizeJson)

  if _contains "$_response" "\"status\":\"ok\""; then
    _info "Success: removed DNS TXT record for ${_fqdn}"
    return 0
  else
    _err "Error: failed to remove DNS TXT record for ${_fqdn}"
    return 1
  fi

}

_get_zone() {
  domain=$1
  i=1

  _list_zones_url="${DNS_WEB_URL}/api/zones/list?token=${DNS_API_TOKEN}"
  _all_zones=$(_get "$_list_zones_url" | _normalizeJson)

  while true; do

    h=$(printf "%s" "$domain" | cut -d . -f "$i-100")
    _debug h "$h"
    if [ -z "$h" ]; then
      # not valid
      return 1
    fi

    if _contains "$_all_zones" "\"name\":\"$h\""; then
      _zone=$h
      _debug _zone "$_zone"
      return 0
    fi

    i=$(_math "$i" + 1)

  done
  return 1

}

_check_dns_web_url_and_api_token() {

  DNS_WEB_URL="${DNS_WEB_URL:-$(_readaccountconf_mutable DNS_WEB_URL)}"
  DNS_API_TOKEN="${DNS_API_TOKEN:-$(_readaccountconf_mutable DNS_API_TOKEN)}"

  if [ -z "$DNS_WEB_URL" ]; then
    _err "Error: DNS API web interface URL not provided"
    return 1
  fi

  if [ -z "$DNS_API_TOKEN" ]; then
    _err "Error: DNS API token not provided"
    return 1
  fi

  # store the DNS Server web console URL and API token to the account conf file.
  _saveaccountconf_mutable DNS_WEB_URL "$DNS_WEB_URL"
  _saveaccountconf_mutable DNS_API_TOKEN "$DNS_API_TOKEN"

}

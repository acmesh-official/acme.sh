#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_artfiles_info='ArtFiles.de
Site: ArtFiles.de
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_artfiles
Options:
 AF_API_USERNAME API Username
 AF_API_PASSWORD API Password
Issues: github.com/acmesh-official/acme.sh/issues/4718
Author: Martin Arndt <https://troublezone.net/>
'

########## API configuration ###################################################

AF_API_SUCCESS='status":"OK'
AF_URL_DCP='https://dcp.c.artfiles.de/api/'
AF_URL_DNS=${AF_URL_DCP}'dns/{*}_dns.html?domain='
AF_URL_DOMAINS=${AF_URL_DCP}'domain/get_domains.html'

########## Public functions ####################################################

# Adds a new TXT record for given ACME challenge value & domain.
# Usage: dns_artfiles_add _acme-challenge.www.example.com "ACME challenge value"
dns_artfiles_add() {
  domain="$1"
  txtValue="$2"
  _info 'Using ArtFiles.de DNS addition API…'
  _debug 'Domain' "$domain"
  _debug 'txtValue' "$txtValue"

  _set_credentials
  _saveaccountconf_mutable 'AF_API_USERNAME' "$AF_API_USERNAME"
  _saveaccountconf_mutable 'AF_API_PASSWORD' "$AF_API_PASSWORD"

  _set_headers
  _get_zone "$domain"
  _dns 'GET'
  if ! _contains "$response" 'TXT'; then
    _err 'Retrieving TXT records failed.'

    return 1
  fi

  _clean_records
  _dns 'SET' "$(printf -- '%s\n_acme-challenge "%s"' "$response" "$txtValue")"
  if ! _contains "$response" "$AF_API_SUCCESS"; then
    _err 'Adding ACME challenge value failed.'

    return 1
  fi
}

# Removes the existing TXT record for given ACME challenge value & domain.
# Usage: dns_artfiles_rm _acme-challenge.www.example.com "ACME challenge value"
dns_artfiles_rm() {
  domain="$1"
  txtValue="$2"
  _info 'Using ArtFiles.de DNS removal API…'
  _debug 'Domain' "$domain"
  _debug 'txtValue' "$txtValue"

  _set_credentials
  _set_headers
  _get_zone "$domain"
  if ! _dns 'GET'; then
    return 1
  fi

  if ! _contains "$response" "$txtValue"; then
    _err 'Retrieved TXT records are missing given ACME challenge value.'

    return 1
  fi

  _clean_records
  response="$(printf -- '%s' "$response" | sed '/_acme-challenge "'"$txtValue"'"/d')"
  _dns 'SET' "$response"
  if ! _contains "$response" "$AF_API_SUCCESS"; then
    _err 'Removing ACME challenge value failed.'

    return 1
  fi
}

########## Private functions ###################################################

# Cleans awful TXT records response of ArtFiles's API & pretty prints it.
# Usage: _clean_records
_clean_records() {
  _info 'Cleaning TXT records…'
  # Extract TXT part, strip trailing quote sign (ACME.sh API guidelines forbid
  # usage of SED's GNU extensions, hence couldn't omit it via regex), strip '\'
  # from '\"' & turn '\n' into real LF characters.
  # Yup, awful API to use - but that's all we got to get this working, so… ;)
  _debug2 'Raw  ' "$response"
  response="$(printf -- '%s' "$response" | sed 's/^.*TXT":"\([^}]*\).*$/\1/;s/,".*$//;s/.$//;s/\\"/"/g;s/\\n/\n/g')"
  _debug2 'Clean' "$response"
}

# Executes an HTTP GET or POST request for getting or setting DNS records,
# containing given payload upon POST.
# Usage: _dns [GET | SET] [payload]
_dns() {
  _info 'Executing HTTP request…'
  action="$1"
  payload="$(printf -- '%s' "$2" | _url_encode)"
  url="$(printf -- '%s%s' "$AF_URL_DNS" "$domain" | sed 's/{\*}/'"$(printf -- '%s' "$action" | _lower_case)"'/')"

  if [ "$action" = 'SET' ]; then
    _debug2 'Payload' "$payload"
    response="$(_post '' "$url&TXT=$payload" '' 'POST' 'application/x-www-form-urlencoded')"
  else
    response="$(_get "$url" '' 10)"
  fi

  if ! _contains "$response" "$AF_API_SUCCESS"; then
    _err "DNS API error: $response"

    return 1
  fi

  _debug 'Response' "$response"

  return 0
}

# Gets the root domain zone for given domain.
# Usage: _get_zone _acme-challenge.www.example.com
_get_zone() {
  fqdn="$1"
  domains="$(_get "$AF_URL_DOMAINS" '' 10)"
  _info 'Getting domain zone…'
  _debug2 'FQDN' "$fqdn"
  _debug2 'Domains' "$domains"

  while _contains "$fqdn" "."; do
    if _contains "$domains" "$fqdn"; then
      domain="$fqdn"
      _info "Found root domain zone: $domain"
      break
    else
      fqdn="${fqdn#*.}"
      _debug2 'FQDN' "$fqdn"
    fi
  done

  if [ "$domain" = "$fqdn" ]; then
    return 0
  fi

  _err 'Couldn'\''t find root domain zone.'

  return 1
}

# Sets the credentials for accessing ArtFiles's API
# Usage: _set_credentials
_set_credentials() {
  _info 'Setting credentials…'
  AF_API_USERNAME="${AF_API_USERNAME:-$(_readaccountconf_mutable AF_API_USERNAME)}"
  AF_API_PASSWORD="${AF_API_PASSWORD:-$(_readaccountconf_mutable AF_API_PASSWORD)}"
  if [ -z "$AF_API_USERNAME" ] || [ -z "$AF_API_PASSWORD" ]; then
    _err 'Missing ArtFiles.de username and/or password.'
    _err 'Please ensure both are set via export command & try again.'

    return 1
  fi
}

# Adds the HTTP Authorization & Content-Type headers to a follow-up request.
# Usage: _set_headers
_set_headers() {
  _info 'Setting headers…'
  encoded="$(printf -- '%s:%s' "$AF_API_USERNAME" "$AF_API_PASSWORD" | _base64)"
  export _H1="Authorization: Basic $encoded"
  export _H2='Content-Type: application/json'
}

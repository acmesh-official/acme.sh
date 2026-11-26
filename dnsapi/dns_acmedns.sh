#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_acmedns_info='acme-dns Server API
 The acme-dns is a limited DNS server with RESTful API to handle ACME DNS challenges.
Site: github.com/joohoi/acme-dns
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_acmedns
Options:
 ACMEDNS_USERNAME Username. Optional.
 ACMEDNS_PASSWORD Password. Optional.
 ACMEDNS_SUBDOMAIN Subdomain. Optional.
 ACMEDNS_STORAGE JSON config. Optional.
 ACMEDNS_BASE_URL API endpoint. Default: "https://auth.acme-dns.io".
Issues: github.com/dampfklon/acme.sh
Author: Wolfgang Ebner, Sven Neubuaer
'

########## Public functions ##########

#Usage: dns_acmedns_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_acmedns_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using acme-dns"
  _debug "fulldomain $fulldomain"
  _debug "txtvalue $txtvalue"

  #for compatiblity from account conf
  ACMEDNS_USERNAME="${ACMEDNS_USERNAME:-$(_readaccountconf_mutable ACMEDNS_USERNAME)}"
  _clearaccountconf_mutable ACMEDNS_USERNAME
  ACMEDNS_PASSWORD="${ACMEDNS_PASSWORD:-$(_readaccountconf_mutable ACMEDNS_PASSWORD)}"
  _clearaccountconf_mutable ACMEDNS_PASSWORD
  ACMEDNS_SUBDOMAIN="${ACMEDNS_SUBDOMAIN:-$(_readaccountconf_mutable ACMEDNS_SUBDOMAIN)}"
  _clearaccountconf_mutable ACMEDNS_SUBDOMAIN

  # Load per-domain config
  ACMEDNS_BASE_URL="${ACMEDNS_BASE_URL:-$(_readdomainconf ACMEDNS_BASE_URL)}"
  ACMEDNS_USERNAME="${ACMEDNS_USERNAME:-$(_readdomainconf ACMEDNS_USERNAME)}"
  ACMEDNS_PASSWORD="${ACMEDNS_PASSWORD:-$(_readdomainconf ACMEDNS_PASSWORD)}"
  ACMEDNS_SUBDOMAIN="${ACMEDNS_SUBDOMAIN:-$(_readdomainconf ACMEDNS_SUBDOMAIN)}"
  ACMEDNS_STORAGE="${ACMEDNS_STORAGE:-$(_readdomainconf ACMEDNS_STORAGE)}"

  # Detect if user explicitly configured JSON storage
  _use_storage_conf=""
  [ -n "$ACMEDNS_STORAGE" ] && _use_storage_conf=1

  # Load from JSON storage if credentials are incomplete
  if [ -z "$ACMEDNS_USERNAME" ] || [ -z "$ACMEDNS_PASSWORD" ] || [ -z "$ACMEDNS_SUBDOMAIN" ]; then
    _acmedns_lookup_from_json "$fulldomain"
  fi

  # For compatibility: old versions stored ACMEDNS_UPDATE_URL in the account
  # conf (issue 3899). Do not clear it here: it must stay available for the
  # other domains that have not migrated to their domain conf yet.
  if [ -z "$ACMEDNS_BASE_URL" ]; then
    _acmedns_update_url="$(_readaccountconf_mutable ACMEDNS_UPDATE_URL)"
    if [ "$_acmedns_update_url" ]; then
      ACMEDNS_BASE_URL="$(echo "$_acmedns_update_url" | sed 's#/update$##')"
    fi
  fi

  # Default acme-dns endpoint
  [ -z "$ACMEDNS_BASE_URL" ] && ACMEDNS_BASE_URL="https://auth.acme-dns.io"

  ACMEDNS_UPDATE_URL="$ACMEDNS_BASE_URL/update"
  ACMEDNS_REGISTER_URL="$ACMEDNS_BASE_URL/register"

  if [ -z "$ACMEDNS_USERNAME" ] || [ -z "$ACMEDNS_PASSWORD" ]; then
    response="$(_post "" "$ACMEDNS_REGISTER_URL" "" "POST")"
    _debug response "$response"
    ACMEDNS_USERNAME=$(echo "$response" | sed -n 's/^{.*\"username\":[ ]*\"\([^\"]*\)\".*}/\1/p')
    _debug "received username: $ACMEDNS_USERNAME"
    ACMEDNS_PASSWORD=$(echo "$response" | sed -n 's/^{.*\"password\":[ ]*\"\([^\"]*\)\".*}/\1/p')
    _debug "received password: $ACMEDNS_PASSWORD"
    ACMEDNS_SUBDOMAIN=$(echo "$response" | sed -n 's/^{.*\"subdomain\":[ ]*\"\([^\"]*\)\".*}/\1/p')
    _debug "received subdomain: $ACMEDNS_SUBDOMAIN"
    ACMEDNS_FULLDOMAIN=$(echo "$response" | sed -n 's/^{.*\"fulldomain\":[ ]*\"\([^\"]*\)\".*}/\1/p')
    _info "##########################################################"
    _info "# Create $fulldomain CNAME $ACMEDNS_FULLDOMAIN DNS entry #"
    _info "##########################################################"
    _info "Press enter to continue... "
    read -r _
  fi

  # Save per-domain config
  _savedomainconf ACMEDNS_BASE_URL "$ACMEDNS_BASE_URL"

  # Save either JSON storage or credentials (mutually exclusive)
  if [ "$_use_storage_conf" = "1" ]; then
    _savedomainconf ACMEDNS_STORAGE "$ACMEDNS_STORAGE"
    _cleardomainconf ACMEDNS_USERNAME
    _cleardomainconf ACMEDNS_PASSWORD
    _cleardomainconf ACMEDNS_SUBDOMAIN
  else
    _savedomainconf ACMEDNS_USERNAME "$ACMEDNS_USERNAME"
    _savedomainconf ACMEDNS_PASSWORD "$ACMEDNS_PASSWORD"
    _savedomainconf ACMEDNS_SUBDOMAIN "$ACMEDNS_SUBDOMAIN"
    _cleardomainconf ACMEDNS_STORAGE
  fi

  export _H1="X-Api-User: $ACMEDNS_USERNAME"
  export _H2="X-Api-Key: $ACMEDNS_PASSWORD"
  data="{\"subdomain\":\"$ACMEDNS_SUBDOMAIN\", \"txt\": \"$txtvalue\"}"

  _debug data "$data"
  response="$(_post "$data" "$ACMEDNS_UPDATE_URL" "" "POST" "application/json")"
  _debug response "$response"

  if ! echo "$response" | grep "\"$txtvalue\"" >/dev/null; then
    _err "invalid response of acme-dns"
    return 1
  fi
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_acmedns_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using acme-dns"
  _debug "fulldomain $fulldomain"
  _debug "txtvalue $txtvalue"
}

########## Private functions ##########

_acmedns_lookup_from_json() {
  _acmedns_fulldomain="$1"
  _acmedns_domain="${_acmedns_fulldomain#_acme-challenge.}"

  _acmedns_storage="$ACMEDNS_STORAGE"
  [ -z "$_acmedns_storage" ] && _acmedns_storage="$HOME/.acme-dns.json"
  [ ! -f "$_acmedns_storage" ] && return 1

  # Escape dots in the domain for use in sed
  _acmedns_safe_domain=$(printf '%s\n' "$_acmedns_domain" | sed 's/\./\\./g')

  # Isolate one domain object even when the storage file is a single line.
  _acmedns_entry="$(
    tr -d '\r\n' <"$_acmedns_storage" |
      sed -n "s/.*\"$_acmedns_safe_domain\"[[:space:]]*:[[:space:]]*{\([^}]*\)}.*/\1/p"
  )"
  [ -z "$_acmedns_entry" ] && return 1

  _acmedns_server_url="$(echo "$_acmedns_entry" | sed -n 's/.*"server_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  _acmedns_username="$(echo "$_acmedns_entry" | sed -n 's/.*"username"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  _acmedns_password="$(echo "$_acmedns_entry" | sed -n 's/.*"password"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  _acmedns_subdomain="$(echo "$_acmedns_entry" | sed -n 's/.*"subdomain"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

  [ -n "$_acmedns_server_url" ] && ACMEDNS_BASE_URL="$_acmedns_server_url"
  [ -n "$_acmedns_username" ] && ACMEDNS_USERNAME="$_acmedns_username"
  [ -n "$_acmedns_password" ] && ACMEDNS_PASSWORD="$_acmedns_password"
  [ -n "$_acmedns_subdomain" ] && ACMEDNS_SUBDOMAIN="$_acmedns_subdomain"

  ACMEDNS_STORAGE="$_acmedns_storage"
  return 0
}

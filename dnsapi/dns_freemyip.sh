#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_freemyip_info='FreeMyIP.com
Site: FreeMyIP.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_freemyip
Options:
 FREEMYIP_Token API Token
Issues: github.com/acmesh-official/acme.sh/issues/6247
Author: Recolic Keghart <root@recolic.net>, @Giova96
'

FREEMYIP_DNS_API="https://freemyip.com/update?"

################ Public functions ################

#Usage: dns_freemyip_add    fulldomain    txtvalue
dns_freemyip_add() {
  fulldomain="$1"
  txtvalue="$2"

  _info "Add TXT record $txtvalue for $fulldomain using freemyip.com api"

  FREEMYIP_Token="${FREEMYIP_Token:-$(_readaccountconf_mutable FREEMYIP_Token)}"
  if [ -z "$FREEMYIP_Token" ]; then
    FREEMYIP_Token=""
    _err "You don't specify FREEMYIP_Token yet."
    _err "Please specify your token and try again."
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable FREEMYIP_Token "$FREEMYIP_Token"

  if _is_root_domain_published "$fulldomain"; then
    _err "freemyip API don't allow you to set multiple TXT record for the same subdomain!"
    _err "You must apply certificate for only one domain at a time!"
    _err "===="
    _err "For example, aaa.yourdomain.freemyip.com and bbb.yourdomain.freemyip.com and yourdomain.freemyip.com ALWAYS share the same TXT record. They will overwrite each other if you apply multiple domain at the same time."
    _debug "If you are testing this workflow in github pipeline or acmetest, please set TEST_DNS_NO_SUBDOMAIN=1 and TEST_DNS_NO_WILDCARD=1"
    return 1
  fi

  # txtvalue must be url-encoded. But it's not necessary for acme txt value.
  _freemyip_get_until_ok "${FREEMYIP_DNS_API}token=$FREEMYIP_Token&domain=$fulldomain&txt=$txtvalue" 2>&1
  return $?
}

#Usage: dns_freemyip_rm    fulldomain    txtvalue
dns_freemyip_rm() {
  fulldomain="$1"
  txtvalue="$2"

  _info "Delete TXT record $txtvalue for $fulldomain using freemyip.com api"

  FREEMYIP_Token="${FREEMYIP_Token:-$(_readaccountconf_mutable FREEMYIP_Token)}"
  if [ -z "$FREEMYIP_Token" ]; then
    FREEMYIP_Token=""
    _err "You don't specify FREEMYIP_Token yet."
    _err "Please specify your token and try again."
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable FREEMYIP_Token "$FREEMYIP_Token"

  # Leave the TXT record as empty or "null" to delete the record.
  _freemyip_get_until_ok "${FREEMYIP_DNS_API}token=$FREEMYIP_Token&domain=$fulldomain&txt=" 2>&1
  return $?
}

################ Private functions below  ################
_get_root() {
  _fmi_d="$1"

  echo "$_fmi_d" | rev | cut -d '.' -f 1-3 | rev
}

# There is random failure while calling freemyip API too fast. This function automatically retry until success.
_freemyip_get_until_ok() {
  _fmi_url="$1"
  for i in $(seq 1 8); do
    _debug "HTTP GET freemyip.com API '$_fmi_url', retry $i/8..."
    _get "$_fmi_url" | tee /dev/fd/2 | grep OK && return 0
    _sleep 1 # DO NOT send the request too fast
  done
  _err "Failed to request freemyip API: $_fmi_url . Server does not say 'OK'"
  return 1
}

# Verify in public dns if domain is already there.
_is_root_domain_published() {
  _fmi_d="$1"
  _webroot="$(_get_root "$_fmi_d")"

  _info "Verifying '""$_fmi_d""' freemyip webroot (""$_webroot"") is not published yet"
  for i in $(seq 1 3); do
    _debug "'$_webroot' ns lookup, retry $i/3..."
    if [ "$(_ns_lookup "$_fmi_d" TXT)" ]; then
      _debug "'$_webroot' already has a TXT record published!"
      return 0
    fi
    _sleep 10 # Give it some time to propagate the TXT record
  done
  return 1
}

#!/usr/bin/env sh
#
#Author: Recolic Keghart <root@recolic.net>
#
########  Public functions #####################

FREEMYIP_Token="xxxx"

#Usage: dns_freemyip_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_freemyip_add() {
  fulldomain="$1"
  txtvalue="$2"

  _info "Add TXT record using freemyip.com api"
  _info "WARNING: If your DDNS domain is 'MYDOMAIN.freemyip.com', you can only create certificate for 'MYDOMAIN.freemyip.com' or '*.MYDOMAIN.freemyip.com'. Subdomain is not supported. "
  _debug "fulldomain: $fulldomain"
  _debug "txtvalue: $txtvalue"

  FREEMYIP_Token="${FREEMYIP_Token:-$(_readaccountconf_mutable FREEMYIP_Token)}"
  if [ -z "$FREEMYIP_Token" ]; then
    FREEMYIP_Token=""
    _err "You don't specify FREEMYIP_Token yet."
    _err "Please specify your token and try again."
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable FREEMYIP_Token "$FREEMYIP_Token"

  # txtvalue must be url-encoded. But it's not necessary for acme txt value.
  _get "https://freemyip.com/update?token=$FREEMYIP_Token&domain=$fulldomain&txt=$txtvalue" | grep OK
  return $?
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_freemyip_rm() {
  fulldomain="$1"
  txtvalue="$2"

  _info "Delete TXT record using freemyip.com api"
  _debug "fulldomain: $fulldomain"
  _debug "txtvalue: $txtvalue"

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
  _get "https://freemyip.com/update?token=$FREEMYIP_Token&domain=$fulldomain&txt=" | grep OK
  return $?
}

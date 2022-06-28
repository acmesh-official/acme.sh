#!/usr/bin/env sh
#
# Author: Recolic Keghart <root@recolic.net>
#

# acme.sh user: please set your token here!
[ -z "$FREEMYIP_Token" ] && FREEMYIP_Token="05ddb54360621d37dea67259"

################ Do not modify after this line ##############

# Note: this script was executed in subshell. It means all env would be cleanup, and EXIT event would be called between different domain names. The only way to persist state is a temporary file.
freemyip_prevdomain_tmpfile=/tmp/.acme-sh-freemyip-prevdomain

# There is random failure while calling freemyip API too fast. This function automatically retry until success.
freemyip_get_until_ok() {
  _fmi_url="$1"
  for i in $(seq 1 8); do
    _debug "HTTP GET freemyip.com API '$_fmi_url', retry $i/8..."
    _get "$_fmi_url" | tee /dev/fd/2 | grep OK && return 0
    sleep 1 # DO NOT send the request too fast
  done
  _err "Failed to request freemyip API: $_fmi_url . Server does not say 'OK'"
  return 2
}

#Usage: dns_freemyip_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
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

  if [ ! -f "$freemyip_prevdomain_tmpfile" ]; then
    echo "$fulldomain" >"$freemyip_prevdomain_tmpfile"
  else
    _err "freemyip API don't allow you to set multiple TXT record for the same subdomain! "
    _err "You must apply certificate for only one domain at a time! "
    _err "===="
    _err "For example, aaa.yourdomain.freemyip.com and bbb.yourdomain.freemyip.com and yourdomain.freemyip.com ALWAYS share the same TXT record. They will overwrite each other if you apply multiple domain at the same time. "
    _err "(You are trying to set TXT record for $fulldomain, but it will overwrite $(cat "$freemyip_prevdomain_tmpfile"))"
    _debug "If you are testing this workflow in github pipeline or acmetest, please set TEST_DNS_NO_SUBDOMAIN=1 and TEST_DNS_NO_WILDCARD=1"
    rm -f "$freemyip_prevdomain_tmpfile"
    return 2
  fi

  # txtvalue must be url-encoded. But it's not necessary for acme txt value.
  freemyip_get_until_ok "https://freemyip.com/update?token=$FREEMYIP_Token&domain=$fulldomain&txt=$txtvalue" 2>&1
  return $?
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_freemyip_rm() {
  fulldomain="$1"
  txtvalue="$2"

  _info "Delete TXT record $txtvalue for $fulldomain using freemyip.com api"
  rm -f "$freemyip_prevdomain_tmpfile"

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
  freemyip_get_until_ok "https://freemyip.com/update?token=$FREEMYIP_Token&domain=$fulldomain&txt=" 2>&1
  return $?
}

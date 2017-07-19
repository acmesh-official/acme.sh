#!/usr/bin/env sh

########  Public functions #####################

#Usage: dns_nsupdate_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_nsupdate_add() {
  fulldomain=$1
  txtvalue=$2
  _checkKeyFile || return 1
  # save the dns server and key to the account conf file.
  _saveaccountconf NSUPDATE_SERVER "${NSUPDATE_SERVER}"
  _saveaccountconf NSUPDATE_KEY "${NSUPDATE_KEY}"
  _savedomainconf NSUPDATE_SUFFIX "${NSUPDATE_SUFFIX}"
  _info "adding ${fulldomain}${NSUPDATE_SUFFIX}. 60 in txt \"${txtvalue}\""
  nsupdate -k "${NSUPDATE_KEY}" <<EOF
server ${NSUPDATE_SERVER}
update add ${fulldomain}${NSUPDATE_SUFFIX}. 60 in txt "${txtvalue}"
send
EOF
  if [ $? -ne 0 ]; then
    _err "error updating domain"
    return 1
  fi

  return 0
}

#Usage: dns_nsupdate_rm   _acme-challenge.www.domain.com
dns_nsupdate_rm() {
  fulldomain=$1
  _checkKeyFile || return 1
  _info "removing ${fulldomain}${NSUPDATE_SUFFIX}. txt"
  nsupdate -k "${NSUPDATE_KEY}" <<EOF
server ${NSUPDATE_SERVER}
update delete ${fulldomain}${NSUPDATE_SUFFIX}. txt
send
EOF
  if [ $? -ne 0 ]; then
    _err "error updating domain"
    return 1
  fi

  return 0
}

####################  Private functions below ##################################

_checkKeyFile() {
  [ -n "${NSUPDATE_SERVER}" ] || NSUPDATE_SERVER="localhost"
  if [ "${NSUPDATE_SERVER}" = "localhost" -a -z "${NSUPDATE_KEY}" ]; then
    NSUPDATE_KEY=/var/run/named/session.key
  fi
  if [ -z "${NSUPDATE_KEY}" ]; then
    _err "you must specify a path to the nsupdate key file"
    return 1
  fi
  if [ ! -r "${NSUPDATE_KEY}" ]; then
    _err "key ${NSUPDATE_KEY} is unreadable"
    return 1
  fi
}

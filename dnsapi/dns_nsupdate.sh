#!/usr/bin/env sh

########  Public functions #####################

#Usage: dns_nsupdate_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_nsupdate_add() {
  fulldomain=$1
  txtvalue=$2
  NSUPDATE_SERVER="${NSUPDATE_SERVER:-$(_readaccountconf_mutable NSUPDATE_SERVER)}"
  NSUPDATE_SERVER_PORT="${NSUPDATE_SERVER_PORT:-$(_readaccountconf_mutable NSUPDATE_SERVER_PORT)}"
  NSUPDATE_KEY="${NSUPDATE_KEY:-$(_readaccountconf_mutable NSUPDATE_KEY)}"
  NSUPDATE_ZONE="${NSUPDATE_ZONE:-$(_readaccountconf_mutable NSUPDATE_ZONE)}"
  NSUPDATE_CNAME_ZONE="${NSUPDATE_CNAME_ZONE:-$(_readaccountconf_mutable NSUPDATE_CNAME_ZONE)}"

  _checkKeyFile || return 1

  # save the dns server and key to the account conf file.
  _saveaccountconf_mutable NSUPDATE_SERVER "${NSUPDATE_SERVER}"
  _saveaccountconf_mutable NSUPDATE_SERVER_PORT "${NSUPDATE_SERVER_PORT}"
  _saveaccountconf_mutable NSUPDATE_KEY "${NSUPDATE_KEY}"
  _saveaccountconf_mutable NSUPDATE_ZONE "${NSUPDATE_ZONE}"
  _saveaccountconf_mutable NSUPDATE_CNAME_ZONE "${NSUPDATE_CNAME_ZONE}"

  [ -n "${NSUPDATE_SERVER}" ] || NSUPDATE_SERVER="localhost"
  [ -n "${NSUPDATE_SERVER_PORT}" ] || NSUPDATE_SERVER_PORT=53

  if [ -n "${NSUPDATE_CNAME_ZONE}" ]; then
    _info "adding _acme-challenge.${NSUPDATE_CNAME_ZONE}. 60 in txt \"${txtvalue}\""
    _info "the record ${fulldomain}. must be a CNAME to this record for validation to succeed"
  else
    _info "adding ${fulldomain}. 60 in txt \"${txtvalue}\""
  fi
  [ -n "$DEBUG" ] && [ "$DEBUG" -ge "$DEBUG_LEVEL_1" ] && nsdebug="-d"
  [ -n "$DEBUG" ] && [ "$DEBUG" -ge "$DEBUG_LEVEL_2" ] && nsdebug="-D"
  if [ -n "${NSUPDATE_CNAME_ZONE}" ]; then
    nsupdate -k "${NSUPDATE_KEY}" $nsdebug <<EOF
server ${NSUPDATE_SERVER}  ${NSUPDATE_SERVER_PORT} 
zone ${NSUPDATE_CNAME_ZONE}.
update add _acme-challenge.${NSUPDATE_CNAME_ZONE}. 60 in txt "${txtvalue}"
send
EOF
  elif [ -n "${NSUPDATE_ZONE}" ]; then
    nsupdate -k "${NSUPDATE_KEY}" $nsdebug <<EOF
server ${NSUPDATE_SERVER}  ${NSUPDATE_SERVER_PORT} 
zone ${NSUPDATE_ZONE}.
update add ${fulldomain}. 60 in txt "${txtvalue}"
send
EOF
  else
    nsupdate -k "${NSUPDATE_KEY}" $nsdebug <<EOF
server ${NSUPDATE_SERVER}  ${NSUPDATE_SERVER_PORT}
update add ${fulldomain}. 60 in txt "${txtvalue}"
send
EOF
  fi
  if [ $? -ne 0 ]; then
    _err "error updating domain"
    return 1
  fi

  return 0
}

#Usage: dns_nsupdate_rm   _acme-challenge.www.domain.com
dns_nsupdate_rm() {
  fulldomain=$1

  NSUPDATE_SERVER="${NSUPDATE_SERVER:-$(_readaccountconf_mutable NSUPDATE_SERVER)}"
  NSUPDATE_SERVER_PORT="${NSUPDATE_SERVER_PORT:-$(_readaccountconf_mutable NSUPDATE_SERVER_PORT)}"
  NSUPDATE_KEY="${NSUPDATE_KEY:-$(_readaccountconf_mutable NSUPDATE_KEY)}"
  NSUPDATE_ZONE="${NSUPDATE_ZONE:-$(_readaccountconf_mutable NSUPDATE_ZONE)}"

  _checkKeyFile || return 1
  [ -n "${NSUPDATE_SERVER}" ] || NSUPDATE_SERVER="localhost"
  [ -n "${NSUPDATE_SERVER_PORT}" ] || NSUPDATE_SERVER_PORT=53
  if [ -n "${NSUPDATE_CNAME_ZONE}" ]; then
    _info "removing _acme-challenge.${NSUPDATE_CNAME_ZONE}. txt"
  else
    _info "removing ${fulldomain}. txt"
  fi
  [ -n "$DEBUG" ] && [ "$DEBUG" -ge "$DEBUG_LEVEL_1" ] && nsdebug="-d"
  [ -n "$DEBUG" ] && [ "$DEBUG" -ge "$DEBUG_LEVEL_2" ] && nsdebug="-D"
  if [ -n "${NSUPDATE_CNAME_ZONE}" ]; then
    nsupdate -k "${NSUPDATE_KEY}" $nsdebug <<EOF
server ${NSUPDATE_SERVER}  ${NSUPDATE_SERVER_PORT} 
update delete _acme-challenge.${NSUPDATE_CNAME_ZONE}. txt
zone ${NSUPDATE_CNAME_ZONE}.
send
EOF
  elif [ -n "${NSUPDATE_ZONE}" ]; then
    nsupdate -k "${NSUPDATE_KEY}" $nsdebug <<EOF
server ${NSUPDATE_SERVER}  ${NSUPDATE_SERVER_PORT} 
update delete ${fulldomain}. txt
zone ${NSUPDATE_ZONE}.
send
EOF
  else
    nsupdate -k "${NSUPDATE_KEY}" $nsdebug <<EOF
server ${NSUPDATE_SERVER}  ${NSUPDATE_SERVER_PORT}
update delete ${fulldomain}. txt
send
EOF
  fi
  if [ $? -ne 0 ]; then
    _err "error updating domain"
    return 1
  fi

  return 0
}

####################  Private functions below ##################################

_checkKeyFile() {
  if [ -z "${NSUPDATE_KEY}" ]; then
    _err "you must specify a path to the nsupdate key file"
    return 1
  fi
  if [ ! -r "${NSUPDATE_KEY}" ]; then
    _err "key ${NSUPDATE_KEY} is unreadable"
    return 1
  fi
}

#!/usr/bin/env sh


# Update DNS via nsupdate with "-y" option
# Based on dns_nsupdate.sh, which used with "-k" option
#
# Author: Vadim Kalinnikov <moose@ylsoftware.com>

########  Public functions #####################

#Usage: dns_nsupdatey_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_nsupdatey_add() {
  fulldomain=$1
  txtvalue=$2
  NSUPDATE_Y_SERVER="${NSUPDATE_Y_SERVER:-$(_readaccountconf_mutable NSUPDATE_Y_SERVER)}"
  NSUPDATE_Y_SERVER_PORT="${NSUPDATE_Y_SERVER_PORT:-$(_readaccountconf_mutable NSUPDATE_Y_SERVER_PORT)}"
  NSUPDATE_Y_KEY="${NSUPDATE_Y_KEY:-$(_readaccountconf_mutable NSUPDATEY_KEY)}"
  NSUPDATE_Y_ZONE="${NSUPDATE_Y_ZONE:-$(_readaccountconf_mutable NSUPDATE_Y_ZONE)}"

  _checkKeyParam || return 1

  # save the dns server and key to the account conf file.
  _saveaccountconf_mutable NSUPDATE_Y_SERVER "${NSUPDATE_Y_SERVER}"
  _saveaccountconf_mutable NSUPDATE_Y_SERVER_PORT "${NSUPDATE_Y_SERVER_PORT}"
  _saveaccountconf_mutable NSUPDATE_Y_KEY "${NSUPDATE_Y_KEY}"
  _saveaccountconf_mutable NSUPDATE_Y_ZONE "${NSUPDATE_Y_ZONE}"

  [ -n "${NSUPDATE_Y_SERVER}" ] || NSUPDATE_SERVER="localhost"
  [ -n "${NSUPDATE_Y_SERVER_PORT}" ] || NSUPDATE_SERVER_PORT=53

  _info "adding ${fulldomain}. 60 in txt \"${txtvalue}\""
  [ -n "$DEBUG" ] && [ "$DEBUG" -ge "$DEBUG_LEVEL_1" ] && nsdebug="-d"
  [ -n "$DEBUG" ] && [ "$DEBUG" -ge "$DEBUG_LEVEL_2" ] && nsdebug="-D"
  if [ -z "${NSUPDATE_Y_ZONE}" ]; then
    nsupdate -y "${NSUPDATE_Y_KEY}" $nsdebug <<EOF
server ${NSUPDATE_Y_SERVER}  ${NSUPDATE_Y_SERVER_PORT}
update add ${fulldomain}. 60 in txt "${txtvalue}"
send
EOF
  else
    nsupdate -y "${NSUPDATE_Y_KEY}" $nsdebug <<EOF
server ${NSUPDATE_Y_SERVER}  ${NSUPDATE_Y_SERVER_PORT}
zone ${NSUPDATE_Y_ZONE}.
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
dns_nsupdatey_rm() {
  fulldomain=$1

  NSUPDATE_Y_SERVER="${NSUPDATE_Y_SERVER:-$(_readaccountconf_mutable NSUPDATE_Y_SERVER)}"
  NSUPDATE_Y_SERVER_PORT="${NSUPDATE_Y_SERVER_PORT:-$(_readaccountconf_mutable NSUPDATE_Y_SERVER_PORT)}"
  NSUPDATE_Y_KEY="${NSUPDATE_Y_KEY:-$(_readaccountconf_mutable NSUPDATE_Y_KEY)}"
  NSUPDATE_Y_ZONE="${NSUPDATE_Y_ZONE:-$(_readaccountconf_mutable NSUPDATE_Y_ZONE)}"

  _checkKeyParam || return 1
  [ -n "${NSUPDATE_Y_SERVER}" ] || NSUPDATE_Y_SERVER="localhost"
  [ -n "${NSUPDATE_Y_SERVER_PORT}" ] || NSUPDATE_Y_SERVER_PORT=53
  _info "removing ${fulldomain}. txt"
  [ -n "$DEBUG" ] && [ "$DEBUG" -ge "$DEBUG_LEVEL_1" ] && nsdebug="-d"
  [ -n "$DEBUG" ] && [ "$DEBUG" -ge "$DEBUG_LEVEL_2" ] && nsdebug="-D"
  if [ -z "${NSUPDATE_Y_ZONE}" ]; then
    nsupdate -y "${NSUPDATE_Y_KEY}" $nsdebug <<EOF
server ${NSUPDATE_Y_SERVER}  ${NSUPDATE_Y_SERVER_PORT}
update delete ${fulldomain}. txt
send
EOF
  else
    nsupdate -y "${NSUPDATE_Y_KEY}" $nsdebug <<EOF
server ${NSUPDATE_Y_SERVER}  ${NSUPDATE_Y_SERVER_PORT}
zone ${NSUPDATE_Y_ZONE}.
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

_checkKeyParam() {
  if [ -z "${NSUPDATE_Y_KEY}" ]; then
    _err "you must specify a key in format: name:key"
    return 1
  fi

  key_name=${NSUPDATE_Y_KEY%%:*}
  key_value=${NSUPDATE_Y_KEY#*:}

  if [ -z "${key_name}" ]; then
    _err "Bad key name!"
    return 1
  fi

  if [ -z "${key_value}" ]; then
    _err "Bad key value!"
    return 1
  fi
}

#!/usr/bin/env sh

########  Public functions #####################
ECHO=$(command -v echo)
NSUPDATE=$(command -v nsupdate)
NSUPDATE_COMMANDS_FILE="/tmp/nsupdate"

#Usage: dns_nsupdate_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_nsupdate_add() {
  fulldomain=$1
  txtvalue=$2
  _checkKeyFile || return 1
  [ -n "${NSUPDATE_SERVER}" ] || NSUPDATE_SERVER="localhost"
  [ -n "${NSUPDATE_SERVER_PORT}" ] || NSUPDATE_SERVER_PORT=53
  # save the dns server and key to the account conf file.
  _saveaccountconf NSUPDATE_SERVER "${NSUPDATE_SERVER}"
  _saveaccountconf NSUPDATE_SERVER_PORT "${NSUPDATE_SERVER_PORT}"
  _saveaccountconf NSUPDATE_KEY "${NSUPDATE_KEY}"
  if ! [ -z "$NSUPDATE_ZONE" ]; then
    _saveaccountconf NSUPDATE_ZONE "${NSUPDATE_ZONE}"
  fi
  _info "adding ${fulldomain}. 60 in txt \"${txtvalue}\""

  $ECHO "server ${NSUPDATE_SERVER} ${NSUPDATE_SERVER_PORT}" > ${NSUPDATE_COMMANDS_FILE}
  if ! [ -z "$NSUPDATE_ZONE" ]; then
    $ECHO "zone ${NSUPDATE_ZONE}" >> ${NSUPDATE_COMMANDS_FILE}
  fi
  $ECHO "update add ${fulldomain}. 60 in txt \"${txtvalue}\"" >> ${NSUPDATE_COMMANDS_FILE}
  $ECHO "send" >> ${NSUPDATE_COMMANDS_FILE}
  
  _debug "$(cat ${NSUPDATE_COMMANDS_FILE})"

  if ! $NSUPDATE -k "${NSUPDATE_KEY}" -v ${NSUPDATE_COMMANDS_FILE}; then
    _err "error updating domain"
    rm ${NSUPDATE_COMMANDS_FILE}
    return 1
  fi
  rm ${NSUPDATE_COMMANDS_FILE}
  return 0
}

#Usage: dns_nsupdate_rm   _acme-challenge.www.domain.com
dns_nsupdate_rm() {
  fulldomain=$1
  _checkKeyFile || return 1
  [ -n "${NSUPDATE_SERVER}" ] || NSUPDATE_SERVER="localhost"
  [ -n "${NSUPDATE_SERVER_PORT}" ] || NSUPDATE_SERVER_PORT=53
  _info "removing ${fulldomain}. txt"
  
  $ECHO "server ${NSUPDATE_SERVER} ${NSUPDATE_SERVER_PORT}" > ${NSUPDATE_COMMANDS_FILE}
  if ! [ -z "$NSUPDATE_ZONE" ]; then
    $ECHO "zone ${NSUPDATE_ZONE}" >> ${NSUPDATE_COMMANDS_FILE}
  fi
  $ECHO "update delete ${fulldomain}. txt" >> ${NSUPDATE_COMMANDS_FILE}
  $ECHO "send" >> ${NSUPDATE_COMMANDS_FILE}

  _debug "$(cat ${NSUPDATE_COMMANDS_FILE})"

  if ! $NSUPDATE -k "${NSUPDATE_KEY}" -v ${NSUPDATE_COMMANDS_FILE}; then
    _err "error updating domain"
    rm ${NSUPDATE_COMMANDS_FILE}
    return 1
  fi
  rm ${NSUPDATE_COMMANDS_FILE}
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

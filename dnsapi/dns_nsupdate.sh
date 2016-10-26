#!/usr/bin/env bash


########  Public functions #####################

#Usage: dns_nsupdate_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_nsupdate_add() {
  fulldomain=$1
  txtvalue=$2
  _checkKeyFile || return 1
  NSUPDATE_SERVER=${NSUPDATE_SERVER:-localhost}
  # save the dns server and key to the account conf file.
  _saveaccountconf NSUPDATE_SERVER "${NSUPDATE_SERVER}"
  _saveaccountconf NSUPDATE_KEY "${NSUPDATE_KEY}"
  tmp=$(mktemp --tmpdir acme_nsupdate.XXXXXX)
  cat > ${tmp} <<EOF
server ${NSUPDATE_SERVER}
update add ${fulldomain}. 60 in txt "${txtvalue}"
send
EOF
  _info "adding ${fulldomain}. 60 in txt \"${txtvalue}\""
  nsupdate -k ${NSUPDATE_KEY} ${tmp}
  if [ $? -ne 0 ]; then
    _err "error updating domain, see ${tmp} for details"
    return 1
  fi
  rm -f ${tmp}
  
  return 0
}

#Usage: dns_nsupdate_rm   _acme-challenge.www.domain.com
dns_nsupdate_rm() {
  fulldomain=$1
  _checkKeyFile || return 1
  NSUPDATE_SERVER=${NSUPDATE_SERVER:-localhost}
  tmp=$(mktemp --tmpdir acme_nsupdate.XXXXXX)
  cat > ${tmp} <<EOF
server ${NSUPDATE_SERVER}
update delete ${fulldomain}. txt
send
EOF
  _info "removing ${fulldomain}. txt"
  nsupdate -k ${NSUPDATE_KEY} ${tmp}
  if [ $? -ne 0 ]; then
    _err "error updating domain, see ${tmp} for details"
    return 1
  fi
  rm -f ${tmp}

  return 0
}


####################  Private functions bellow ##################################

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

_info() {
  if [ -z "$2" ] ; then
    echo "[$(date)] $1"
  else
    echo "[$(date)] $1='$2'"
  fi
}

_err() {
  _info "$@" >&2
  return 1
}

_debug() {
  if [ -z "$DEBUG" ] ; then
    return
  fi
  _err "$@"
  return 0
}

_debug2() {
  if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ] ; then
    _debug "$@"
  fi
  return
}

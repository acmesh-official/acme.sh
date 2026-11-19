#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_nsupdate_info='nsupdate RFC 2136 DynDNS client
Site: bind9.readthedocs.io/en/v9.18.19/manpages.html#nsupdate-dynamic-dns-update-utility
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_nsupdate
Options:
 NSUPDATE_SERVER Server hostname. Default: "localhost".
 NSUPDATE_SERVER_PORT Server port. Default: "53".
 NSUPDATE_KEY File path to TSIG key. Default: "". Optional.
 NSUPDATE_ZONE Domain zone to update. Optional.
 NSUPDATE_FOLLOW_CNAME Follow a CNAME at the challenge record and update its target instead; NSUPDATE_ZONE is ignored when a CNAME was followed. Default: "". Optional.
'

########  Public functions #####################

#Usage: dns_nsupdate_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_nsupdate_add() {
  fulldomain=$1
  txtvalue=$2
  NSUPDATE_SERVER="${NSUPDATE_SERVER:-$(_readaccountconf_mutable NSUPDATE_SERVER)}"
  NSUPDATE_SERVER_PORT="${NSUPDATE_SERVER_PORT:-$(_readaccountconf_mutable NSUPDATE_SERVER_PORT)}"
  NSUPDATE_KEY="${NSUPDATE_KEY:-$(_readaccountconf_mutable NSUPDATE_KEY)}"
  NSUPDATE_ZONE="${NSUPDATE_ZONE:-$(_readaccountconf_mutable NSUPDATE_ZONE)}"
  NSUPDATE_OPT="${NSUPDATE_OPT:-$(_readaccountconf_mutable NSUPDATE_OPT)}"
  NSUPDATE_FOLLOW_CNAME="${NSUPDATE_FOLLOW_CNAME:-$(_readaccountconf_mutable NSUPDATE_FOLLOW_CNAME)}"

  # save the dns server and key to the account conf file.
  _saveaccountconf_mutable NSUPDATE_SERVER "${NSUPDATE_SERVER}"
  _saveaccountconf_mutable NSUPDATE_SERVER_PORT "${NSUPDATE_SERVER_PORT}"
  _saveaccountconf_mutable NSUPDATE_KEY "${NSUPDATE_KEY}"
  _saveaccountconf_mutable NSUPDATE_ZONE "${NSUPDATE_ZONE}"
  _saveaccountconf_mutable NSUPDATE_OPT "${NSUPDATE_OPT}"
  _saveaccountconf_mutable NSUPDATE_FOLLOW_CNAME "${NSUPDATE_FOLLOW_CNAME}"

  [ -n "${NSUPDATE_SERVER}" ] || NSUPDATE_SERVER="localhost"
  [ -n "${NSUPDATE_SERVER_PORT}" ] || NSUPDATE_SERVER_PORT=53
  [ -n "${NSUPDATE_KEY}" ] || NSUPDATE_KEY=""
  [ -n "${NSUPDATE_OPT}" ] || NSUPDATE_OPT=""

  NSUPDATE_SERVER_LIST=$(printf "%s" "$NSUPDATE_SERVER" | tr ',' ' ')

  if [ -n "${NSUPDATE_FOLLOW_CNAME}" ]; then
    _nfc_resolved=$(_nsupdate_follow_cname "${fulldomain}")
    if [ "${_nfc_resolved}" != "${fulldomain}" ]; then
      fulldomain=${_nfc_resolved}
      NSUPDATE_ZONE=""
    fi
  fi

  _info "adding ${fulldomain}. 60 in txt \"${txtvalue}\""
  [ -n "$DEBUG" ] && [ "$DEBUG" -ge "$DEBUG_LEVEL_1" ] && nsdebug="-d"
  [ -n "$DEBUG" ] && [ "$DEBUG" -ge "$DEBUG_LEVEL_2" ] && nsdebug="-D"

  for NS_SERVER in $NSUPDATE_SERVER_LIST; do
    _info "Updating DNS server: $NS_SERVER"

    if [ -z "${NSUPDATE_ZONE}" ]; then
      #shellcheck disable=SC2086
      if [ -z "${NSUPDATE_KEY}" ]; then
        nsupdate $nsdebug $NSUPDATE_OPT <<EOF
server ${NS_SERVER}  ${NSUPDATE_SERVER_PORT}
update add ${fulldomain}. 60 in txt "${txtvalue}"
send
EOF
      else
        nsupdate -k "${NSUPDATE_KEY}" $nsdebug $NSUPDATE_OPT <<EOF
server ${NS_SERVER}  ${NSUPDATE_SERVER_PORT}
update add ${fulldomain}. 60 in txt "${txtvalue}"
send
EOF
      fi
    else
      #shellcheck disable=SC2086
      if [ -z "${NSUPDATE_KEY}" ]; then
        nsupdate $nsdebug $NSUPDATE_OPT <<EOF
server ${NS_SERVER}  ${NSUPDATE_SERVER_PORT}
zone ${NSUPDATE_ZONE}.
update add ${fulldomain}. 60 in txt "${txtvalue}"
send
EOF
      else
        nsupdate -k "${NSUPDATE_KEY}" $nsdebug $NSUPDATE_OPT <<EOF
server ${NS_SERVER}  ${NSUPDATE_SERVER_PORT}
zone ${NSUPDATE_ZONE}.
update add ${fulldomain}. 60 in txt "${txtvalue}"
send
EOF
      fi
    fi
  done
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
  NSUPDATE_OPT="${NSUPDATE_OPT:-$(_readaccountconf_mutable NSUPDATE_OPT)}"
  NSUPDATE_FOLLOW_CNAME="${NSUPDATE_FOLLOW_CNAME:-$(_readaccountconf_mutable NSUPDATE_FOLLOW_CNAME)}"

  [ -n "${NSUPDATE_SERVER}" ] || NSUPDATE_SERVER="localhost"
  [ -n "${NSUPDATE_SERVER_PORT}" ] || NSUPDATE_SERVER_PORT=53
  [ -n "${NSUPDATE_KEY}" ] || NSUPDATE_KEY=""

  NSUPDATE_SERVER_LIST=$(printf "%s" "$NSUPDATE_SERVER" | tr ',' ' ')

  if [ -n "${NSUPDATE_FOLLOW_CNAME}" ]; then
    _nfc_resolved=$(_nsupdate_follow_cname "${fulldomain}")
    if [ "${_nfc_resolved}" != "${fulldomain}" ]; then
      fulldomain=${_nfc_resolved}
      NSUPDATE_ZONE=""
    fi
  fi

  _info "removing ${fulldomain}. txt"
  [ -n "$DEBUG" ] && [ "$DEBUG" -ge "$DEBUG_LEVEL_1" ] && nsdebug="-d"
  [ -n "$DEBUG" ] && [ "$DEBUG" -ge "$DEBUG_LEVEL_2" ] && nsdebug="-D"

  for NS_SERVER in $NSUPDATE_SERVER_LIST; do
    _info "Updating DNS server: $NS_SERVER"

    if [ -z "${NSUPDATE_ZONE}" ]; then
      #shellcheck disable=SC2086
      if [ -z "${NSUPDATE_KEY}" ]; then
        nsupdate $nsdebug $NSUPDATE_OPT <<EOF
server ${NS_SERVER}  ${NSUPDATE_SERVER_PORT}
update delete ${fulldomain}. txt
send
EOF
      else
        nsupdate -k "${NSUPDATE_KEY}" $nsdebug $NSUPDATE_OPT <<EOF
server ${NS_SERVER}  ${NSUPDATE_SERVER_PORT}
update delete ${fulldomain}. txt
send
EOF
      fi
    else
      #shellcheck disable=SC2086
      if [ -z "${NSUPDATE_KEY}" ]; then
        nsupdate $nsdebug $NSUPDATE_OPT <<EOF
server ${NS_SERVER}  ${NSUPDATE_SERVER_PORT}
zone ${NSUPDATE_ZONE}.
update delete ${fulldomain}. txt
send
EOF
      else
        nsupdate -k "${NSUPDATE_KEY}" $nsdebug $NSUPDATE_OPT <<EOF
server ${NS_SERVER}  ${NSUPDATE_SERVER_PORT}
zone ${NSUPDATE_ZONE}.
update delete ${fulldomain}. txt
send
EOF
      fi
    fi
  done
  if [ $? -ne 0 ]; then
    _err "error updating domain"
    return 1
  fi

  return 0
}

####################  Private functions below ##################################

#Usage: _nsupdate_follow_cname <name>
#Follow a chain of CNAMEs (at most 5) from the given name and echo the
#final name. Uses dig, kdig, host or nslookup, whichever is present.
_nsupdate_follow_cname() {
  _nfc_name=$1
  _nfc_i=0
  while [ "${_nfc_i}" -lt 5 ]; do
    if _exists dig; then
      _nfc_target=$(dig +short CNAME "${_nfc_name}" 2>/dev/null)
    elif _exists kdig; then
      _nfc_target=$(kdig +short CNAME "${_nfc_name}" 2>/dev/null)
    elif _exists host; then
      _nfc_target=$(host -t CNAME "${_nfc_name}" 2>/dev/null | sed -n "s/.* is an alias for //p")
    else
      _nfc_target=$(nslookup -type=cname "${_nfc_name}" 2>/dev/null | sed -n "s/.*canonical name = //p")
    fi
    _nfc_target=$(printf "%s\\n" "${_nfc_target}" | grep -v "^;" | head -n 1 | tr -d " \\t\\r" | sed "s/\\.$//")
    if [ -z "${_nfc_target}" ]; then
      break
    fi
    _nfc_name=${_nfc_target}
    _nfc_i=$((_nfc_i + 1))
  done
  printf "%s\n" "${_nfc_name}"
}

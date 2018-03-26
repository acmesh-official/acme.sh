#!/usr/bin/env sh

############################################################
# Plugin para criação automática da entrada de DNS txt     #
# Uso com o sistema acme.sh                                #
#                                                          #
# Author: Felipe Keller Braz <felipebraz@kinghost.com.br>  #
# Report Bugs here: infra_interno@kinghost.com.br          #
#                                                          #
# Values to export:                                        #
# export INFRAWS_Hash="PASSWORD"                           #
############################################################

INFRAWS_Api="http://infra-ws.kinghost.net/serverbackend/acme"

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_infraws_add() {
  fulldomain=$1
  txtvalue=$2

  INFRAWS_Hash="${INFRAWS_Hash:-$(_readaccountconf_mutable INFRAWS_Hash)}"

  if [ -z "$INFRAWS_Hash" ]; then
    INFRAWS_Hash=""
    _err "You don't specify KingHost api password and email yet."
    _err "Please create you key and try again."
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable INFRAWS_Hash "$INFRAWS_Hash"

  _debug "Getting txt records"
  infraws_rest GET "dns" "name=$fulldomain&content=$txtvalue"

  #This API call returns "status":"ok" if dns record does not exists
  #We are creating a new txt record here, so we expect the "ok" status
  if ! echo "$response" | grep '"status":"ok"' >/dev/null; then
    _err "Error"
    _err "$response"
    return 1
  fi

  infraws_rest POST "dns" "name=$fulldomain&content=$txtvalue"
  if ! echo "$response" | grep '"status":"ok"' >/dev/null; then
    _err "Error"
    _err "$response"
    return 1
  fi

  return 0
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
dns_infraws_rm() {
  fulldomain=$1
  txtvalue=$2

  INFRAWS_Hash="${INFRAWS_Hash:-$(_readaccountconf_mutable INFRAWS_Hash)}"
  if [ -z "$INFRAWS_Hash" ]; then
    INFRAWS_Hash=""
    _err "You don't specify KingHost api key and email yet."
    _err "Please create you key and try again."
    return 1
  fi

  _debug "Getting txt records"
  infraws_rest GET "dns" "name=$fulldomain&content=$txtvalue"

  infraws_rest DELETE "dns" "name=$fulldomain&content=$txtvalue"
  if ! echo "$response" | grep '"status":"ok"' >/dev/null; then
    _err "Error"
    _err "$response"
    return 1
  fi

  return 0
}

####################  Private functions below ##################################
infraws_rest() {
  method=$1
  uri="$2"
  data="$3"
  _debug "$uri"

  if [ "$method" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$INFRAWS_Api/hash/$INFRAWS_Hash/" "" "$method")"
  else
    response="$(_get "$INFRAWS_Api/hash/$INFRAWS_Hash/?$data")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $uri"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

#!/usr/bin/env sh

#Here is a sample custom api script.
#This file name is "dns_myapi.sh"
#So, here must be a method   dns_myapi_add()
#Which will be called by acme.sh to add the txt record to your api system.
#returns 0 means success, otherwise error.



########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_myapi_add() {
  fulldomain=$1
  txtvalue=$2
  _err "Not implemented!"
  return 1;
}





####################  Private functions bellow ##################################
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
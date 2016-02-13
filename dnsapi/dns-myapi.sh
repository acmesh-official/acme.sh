#!/bin/bash

#Here is a sample custom api script.
#This file name is "dns-myapi.sh"
#So, here must be a method   dns-myapi-add()
#Which will be called by le.sh to add the txt record to your api system.
#returns 0 meanst success, otherwise error.



########  Public functions #####################

#Usage: add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns-myapi-add() {
  fulldomain=$1
  txtvalue=$2
  _err "Not implemented!"
  return 1;
}









####################  Private functions bellow ##################################


_debug() {

  if [ -z "$DEBUG" ] ; then
    return
  fi
  
  if [ -z "$2" ] ; then
    echo $1
  else
    echo "$1"="$2"
  fi
}

_info() {
  if [ -z "$2" ] ; then
    echo "$1"
  else
    echo "$1"="$2"
  fi
}

_err() {
  if [ -z "$2" ] ; then
    echo "$1" >&2
  else
    echo "$1"="$2" >&2
  fi
}



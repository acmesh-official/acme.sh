#!/bin/bash

#Report Bugs here: https://github.com/acmesh-official/acme.sh
#
LS_API="http://www.icdn.hk:5050/api/drsd"
########  Public functions #####################

# Please Read this guide first: https://github.com/acmesh-official/acme.sh/wiki/DNS-API-Dev-Guide

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_ls_add() {
  fulldomain=$1
  txtvalue=$2

  LS_Key="${LS_Key:-$(_readaccountconf_mutable LS_Key)}"
  if [ -z "$LS_Key" ]; then
    _err "You don't specify ls api key yet."
    _err "Please create you key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable LS_Key "$LS_Key"

  _info "Adding TXT record to ${fulldomain}"
  response="$(_post "secretkey=${LS_Key}&domain=${fulldomain}&rval=${txtvalue}" "$LS_API")"
  if ! _contains "${response}" 'success'; then
    _err "Could not create resource record, check logs"
    _err "${response}"
    return 1
  else
    return 0
  fi
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_ls_rm() {
  fulldomain=$1
  txtvalue=$2
  LS_Key="${LS_Key:-$(_readaccountconf_mutable LS_Key)}"
  if [ -z "$LS_Key" ]; then
    _err "You don't specify ls api key yet."
    _err "Please create you key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable LS_Key "$LS_Key"

  _info "Adding TXT record to ${fulldomain}"
  response="$(_post "secretkey=${LS_Key}&domain=${fulldomain}&rval=${txtvalue}&option=del" "$LS_API")"
  if ! _contains "${response}" 'success'; then
    _err "Could not create resource record, check logs"
    _err "${response}"
    return 1
  else
    return 0
  fi
}
####################  Private functions below ##################################

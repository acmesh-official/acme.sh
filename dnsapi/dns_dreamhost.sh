#!/usr/bin/env sh

#Author: RhinoLance
#Report Bugs here: https://github.com/RhinoLance/acme.sh
#

#define the api endpoint
DH_API_ENDPOINT="https://api.dreamhost.com/"
querystring=""

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dreamhost_add() {
  fulldomain=$1
  txtvalue=$2

  if ! validate "$fulldomain" "$txtvalue"; then
    return 1
  fi

  querystring="key=$DH_API_KEY&cmd=dns-add_record&record=$fulldomain&type=TXT&value=$txtvalue"
  if ! submit "$querystring"; then
    return 1
  fi

  return 0
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_dreamhost_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! validate "$fulldomain" "$txtvalue"; then
    return 1
  fi

  querystring="key=$DH_API_KEY&cmd=dns-remove_record&record=$fulldomain&type=TXT&value=$txtvalue"
  if ! submit "$querystring"; then
    return 1
  fi

  return 0
}

####################  Private functions below ##################################

#send the command to the api endpoint.
submit() {
  querystring=$1

  url="$DH_API_ENDPOINT?$querystring"

  _debug url "$url"

  if ! response="$(_get "$url")"; then
    _err "Error <$1>"
    return 1
  fi

  if [ -z "$2" ]; then
    message="$(echo "$response" | _egrep_o "\"Message\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \")"
    if [ -n "$message" ]; then
      _err "$message"
      return 1
    fi
  fi

  _debug response "$response"

  return 0
}

#check that we have a valid API Key
validate() {
  fulldomain=$1
  txtvalue=$2

  _info "Using dreamhost"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  #retrieve the API key from the environment variable if it exists, otherwise look for a saved key.
  DH_API_KEY="${DH_API_KEY:-$(_readaccountconf_mutable DH_API_KEY)}"

  if [ -z "$DH_API_KEY" ]; then
    DH_API_KEY=""
    _err "You didn't specify the DreamHost api key yet (export DH_API_KEY=\"<api key>\")"
    _err "Please login to your control panel, create a key and try again."
    return 1
  fi

  #save the api key to the account conf file.
  _saveaccountconf_mutable DH_API_KEY "$DH_API_KEY"
}

#!/usr/bin/env sh
#
# tele3.cz DNS API
#
# Author: Roman Blizik
# Report Bugs here: https://github.com/par-pa/acme.sh
#
# --
# export TELE3_Key="MS2I4uPPaI..."
# export TELE3_Secret="kjhOIHGJKHg"
# --

TELE3_API="https://www.tele3.cz/acme/"

########  Public functions  #####################

dns_tele3_add() {
  _info "Using TELE3 DNS"
  data="\"ope\":\"add\", \"domain\":\"$1\", \"value\":\"$2\""
  if ! _tele3_call; then
    _err "Publish zone failed"
    return 1
  fi

  _info "Zone published"
}

dns_tele3_rm() {
  _info "Using TELE3 DNS"
  data="\"ope\":\"rm\", \"domain\":\"$1\", \"value\":\"$2\""
  if ! _tele3_call; then
    _err "delete TXT record failed"
    return 1
  fi

  _info "TXT record successfully deleted"
}

####################  Private functions below  ##################################

_tele3_init() {
  TELE3_Key="${TELE3_Key:-$(_readaccountconf_mutable TELE3_Key)}"
  TELE3_Secret="${TELE3_Secret:-$(_readaccountconf_mutable TELE3_Secret)}"
  if [ -z "$TELE3_Key" ] || [ -z "$TELE3_Secret" ]; then
    TELE3_Key=""
    TELE3_Secret=""
    _err "You must export variables: TELE3_Key and TELE3_Secret"
    return 1
  fi

  #save the config variables to the account conf file.
  _saveaccountconf_mutable TELE3_Key "$TELE3_Key"
  _saveaccountconf_mutable TELE3_Secret "$TELE3_Secret"
}

_tele3_call() {
  _tele3_init
  data="{\"key\":\"$TELE3_Key\", \"secret\":\"$TELE3_Secret\", $data}"

  _debug data "$data"

  response="$(_post "$data" "$TELE3_API" "" "POST")"
  _debug response "$response"

  if [ "$response" != "success" ]; then
    _err "$response"
    return 1
  fi
}

#!/usr/bin/env sh

#Author: Florian Pfitzer
#Report Bugs here: https://github.com/acmesh-official/acme.sh
#export BURP_COLLABORATOR_CONFIG=/etc/burp/collaborator.json
#export BURP_COLLABORATOR_RESTART='/usr/bin/systemctl restart burp-collaborator'
#
########  Public functions #####################

dns_burp_add() {
  txtvalue=$2
  _info "Using burp"
  BURP_COLLABORATOR_CONFIG="${BURP_COLLABORATOR_CONFIG:-$(_readaccountconf_mutable BURP_COLLABORATOR_CONFIG)}"
  BURP_COLLABORATOR_RESTART="${BURP_COLLABORATOR_RESTART:-$(_readaccountconf_mutable BURP_COLLABORATOR_RESTART)}"
  if [ -z "$BURP_COLLABORATOR_CONFIG" ] || [ -z "$BURP_COLLABORATOR_RESTART" ]; then
    BURP_COLLABORATOR_CONFIG=""
    BURP_COLLABORATOR_RESTART=""
    _err "You did not specify BURP_COLLABORATOR_CONFIG and BURP_COLLABORATOR_RESTART"
    return 1
  fi
  _saveaccountconf_mutable BURP_COLLABORATOR_CONFIG "$BURP_COLLABORATOR_CONFIG"
  _saveaccountconf_mutable BURP_COLLABORATOR_RESTART "$BURP_COLLABORATOR_RESTART"

  json=$(cat "$BURP_COLLABORATOR_CONFIG")
  json=$(echo "$json" | jq ".customDnsRecords += [{\"label\": \"_acme-challenge\", \"record\": \"$txtvalue\", \"type\": \"TXT\", \"ttl\": 60}]")

  echo "$json" >"$BURP_COLLABORATOR_CONFIG"

  eval "$BURP_COLLABORATOR_RESTART"

  return 0
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_burp_rm() {
  txtvalue=$2
  _info "Using burp"

  json=$(cat "$BURP_COLLABORATOR_CONFIG")
  json=$(echo "$json" | jq "del(.customDnsRecords[] | select(.label == \"_acme-challenge\"))")

  echo "$json" >"$BURP_COLLABORATOR_CONFIG"

  eval "$BURP_COLLABORATOR_RESTART"
}

####################  Private functions below ##################################

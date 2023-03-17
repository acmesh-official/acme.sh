#!/usr/bin/env sh
GOOGLEDOMAINS_API="https://acmedns.googleapis.com/v1/acmeChallengeSets"
dns_googledomains_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using Google Domains api"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  GOOGLEDOMAINS_TOKEN="${GOOGLEDOMAINS_TOKEN:-$(_readaccountconf_mutable GOOGLEDOMAINS_TOKEN)}"

  if [ -z "$GOOGLEDOMAINS_TOKEN" ]; then
    GOOGLEDOMAINS_TOKEN=""
    _err "You did not specify GOOGLEDOMAINS_TOKEN yet."
    _err "Please create your key and try again."
    _err "e.g."
    _err "export GOOGLEDOMAINS_TOKEN=d41d8cd98f00b204e9800998ecf8427e"
    return 1
  fi
  #save the api token to the account conf file.
  _saveaccountconf_mutable GOOGLEDOMAINS_TOKEN "$GOOGLEDOMAINS_TOKEN"

  _debug "First detect the root zone"
  i=0
  while [ $i -le "$(echo "$fulldomain" | grep -o '\.' | wc -l)" ]; do
    # join the domain parts from the current index to the end
    current_domain=$(echo "$fulldomain" | cut -d "." -f $((i + 1))-)

    # make a curl request to the URL and break the loop if the HTTP response code is 200
    response="$(_get "$GOOGLEDOMAINS_API/$current_domain")"

    if _contains "$response" "INVALID_ARGUMENT"; then
      _info "Invalid domain: $current_domain"
    else
      _info "Found valid domain: $current_domain"
      break
    fi
    i=$((i + 1))
  done
  export _H1="Content-Type: application/json"
  _post "{\"accessToken\":\"$GOOGLEDOMAINS_TOKEN\",\"keepExpiredRecords\":true,\"recordsToAdd\":[{\"digest\":\"$txtvalue\",\"fqdn\":\"$fulldomain\"}]}" "$GOOGLEDOMAINS_API/$current_domain:rotateChallenges" "" ""
}
dns_googledomains_rm() {
  fulldomain=$1
  txtvalue=$2

  GOOGLEDOMAINS_TOKEN="${GOOGLEDOMAINS_TOKEN:-$(_readaccountconf_mutable GOOGLEDOMAINS_TOKEN)}"
  _info "Using Google Domains api"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  i=0
  while [ $i -le "$(echo "$fulldomain" | grep -o '\.' | wc -l)" ]; do
    # join the domain parts from the current index to the end
    current_domain=$(echo "$fulldomain" | cut -d "." -f $((i + 1))-)

    # make a curl request to the URL and break the loop if the HTTP response code is 200
    response="$(_get "$GOOGLEDOMAINS_API/$current_domain")"
    if _contains "$response" "INVALID_ARGUMENT"; then
      echo "Invalid domain: $current_domain"
    else
      echo "Found valid domain: $current_domain"
      break
    fi
    i=$((i + 1))
  done
  export _H1="Content-Type: application/json"
  _post "{\"accessToken\":\"$GOOGLEDOMAINS_TOKEN\",\"keepExpiredRecords\":true,\"recordsToRemove\":[{\"digest\":\"$txtvalue\",\"fqdn\":\"$fulldomain\"}]}" "$GOOGLEDOMAINS_API/$current_domain:rotateChallenges" "" ""
}

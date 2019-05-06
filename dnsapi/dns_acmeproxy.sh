#!/usr/bin/env sh

## Acmeproxy DNS provider to be used with acmeproxy (http://github.com/mdbraber/acmeproxy)
## API integration by Maarten den Braber
##
## Report any bugs via https://github.com/mdbraber/acme.sh

dns_acmeproxy_add() {
  fulldomain="${1}"
  txtvalue="${2}"
  action="present"

  _debug "Calling: _acmeproxy_request() '${fulldomain}' '${txtvalue}' '${action}'"
  _acmeproxy_request $fulldomain $txtvalue $action
}

dns_acmeproxy_rm() {
  fulldomain="${1}"
  txtvalue="${2}"
  action="cleanup"

  _debug "Calling: _acmeproxy_request() '${fulldomain}' '${txtvalue}' '${action}'"
  _acmeproxy_request $fulldomain $txtvalue $action
}

_acmeproxy_request() {

  ## Nothing to see here, just some housekeeping
  fulldomain=$1
  txtvalue=$2
  action=$3

  _info "Using acmeproxy"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  ACMEPROXY_ENDPOINT="${ACMEPROXY_ENDPOINT:-$(_readaccountconf_mutable ACMEPROXY_ENDPOINT)}"
  ACMEPROXY_USERNAME="${ACMEPROXY_USERNAME:-$(_readaccountconf_mutable ACMEPROXY_USERNAME)}"
  ACMEPROXY_PASSWORD="${ACMEPROXY_PASSWORD:-$(_readaccountconf_mutable ACMEPROXY_PASSWORD)}"

  ## Check for the endpoint
  if [ -z "ACMEPROXY_ENDPOINT" ]; then
    ACMEPROXY_ENDPOINT=""
    _err "You didn't specify the endpoint"
    _err "Please set them via 'export ACMEPROXY_ENDPOINT=https://ip:port' and try again."
    return 1
  fi

  ## Check for the credentials
  if [ -z "$ACMEPROXY_USERNAME" ] || [ -z "$ACMEPROXY_PASSWORD" ]; then
    ACMEPROXY_USERNAME=""
    ACMEPROXY_PASSWORD=""
    _err "You didn't set username and password"
    _err "Please set them via 'export ACMEPROXY_USERNAME=...' and 'export ACMEPROXY_PASSWORD=...' and try again."
    return 1
  fi

  ## Save the credentials to the account file
  _saveaccountconf_mutable ACMEPROXY_ENDPOINT "$ACMEPROXY_ENDPOINT"
  _saveaccountconf_mutable ACMEPROXY_USERNAME "$ACMEPROXY_USERNAME"
  _saveaccountconf_mutable ACMEPROXY_PASSWORD "$ACMEPROXY_PASSWORD"

  ## Base64 encode the credentials
  credentials=$(printf "%b" "$ACMEPROXY_USERNAME:$ACMEPROXY_PASSWORD" | _base64)

  ## Construct the HTTP Authorization header
  export _H1="Authorization: Basic $credentials"
  export _H2="Accept: application/json"
  export _H3="Content-Type: application/json"

  ## Add the challenge record to the acmeproxy grid member
  response="$(_post "{\"fqdn\": \"$fulldomain.\", \"value\": \"$txtvalue\"}" "$ACMEPROXY_ENDPOINT/$action" "" "POST")"

  ## Let's see if we get something intelligible back from the unit
  if echo "$response" | grep "\"$txtvalue\"" > /dev/null; then
    _info "Successfully created the txt record"
    return 0
  else
    _err "Error encountered during record addition"
    _err "$response"
    return 1
  fi

}

####################  Private functions below ##################################

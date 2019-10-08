#!/usr/bin/env sh

# Name: dns_miab.sh
#
# Authors:
#    Darven Dissek 2018
#    William Gertz 2019
#
#     Thanks to Neil Pang for the code reused from acme.sh from HTTP-01 validation
#     used to communicate with the MailintheBox Custom DNS API
# Report Bugs here:
#    https://github.com/billgertz/MIAB_dns_api (for dns_miab.sh)
#    https://github.com/Neilpang/acme.sh       (for acme.sh)
#
########  Public functions #####################

#Usage: dns_miab_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_miab_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using miab"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  MIAB_Username="${MIAB_Username:-$(_readaccountconf_mutable MIAB_Username)}"
  MIAB_Password="${MIAB_Password:-$(_readaccountconf_mutable MIAB_Password)}"
  MIAB_Server="${MIAB_Server:-$(_readaccountconf_mutable MIAB_Server)}"

  #debug log the environmental variables
  _debug MIAB_Username "$MIAB_Username"
  _debug MIAB_Password "$MIAB_Password"
  _debug MIAB_Server "$MIAB_Server"

  if [ -z "$MIAB_Username" ] || [ -z "$MIAB_Password" ] || [ -z "$MIAB_Server" ]; then
    MIAB_Username=""
    MIAB_Password=""
    MIAB_Server=""
    _err "You didn't specify MIAB_Username or MIAB_Password or MIAB_Server."
    _err "Please try again."
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable MIAB_Username "$MIAB_Username"
  _saveaccountconf_mutable MIAB_Password "$MIAB_Password"
  _saveaccountconf_mutable MIAB_Server "$MIAB_Server"

  baseurl="https://$MIAB_Server/admin/dns/custom/$fulldomain/txt"

  #Add the challenge record
  result="$(_miab_post "$txtvalue" "$baseurl" "POST" "$MIAB_Username" "$MIAB_Password")"

  _debug result "$result"

  #check if result was good
  if _contains "$result" "updated DNS"; then
    _info "Successfully created the txt record"
    return 0
  else
    _err "Error encountered during record addition"
    _err "$result"
    return 1
  fi
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_miab_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using miab"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  MIAB_Username="${MIAB_Username:-$(_readaccountconf_mutable MIAB_Username)}"
  MIAB_Password="${MIAB_Password:-$(_readaccountconf_mutable MIAB_Password)}"
  MIAB_Server="${MIAB_Server:-$(_readaccountconf_mutable MIAB_Server)}"

  #debug log the environmental variables
  _debug MIAB_Username "$MIAB_Username"
  _debug MIAB_Password "$MIAB_Password"
  _debug MIAB_Server "$MIAB_Server"

  if [ -z "$MIAB_Username" ] || [ -z "$MIAB_Password" ] || [ -z "$MIAB_Server" ]; then
    MIAB_Username=""
    MIAB_Password=""
    MIAB_Server=""
    _err "You didn't specify MIAB_Username or MIAB_Password or MIAB_Server."
    _err "Please try again."
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable MIAB_Username "$MIAB_Username"
  _saveaccountconf_mutable MIAB_Password "$MIAB_Password"
  _saveaccountconf_mutable MIAB_Server "$MIAB_Server"

  baseurl="https://$MIAB_Server/admin/dns/custom/$fulldomain/txt"

  #Remove the challenge record
  result="$(_miab_post "$txtvalue" "$baseurl" "DELETE" "$MIAB_Username" "$MIAB_Password")"

  _debug result "$result"

  #check if result was good
  if _contains "$result" "updated DNS"; then
    _info "Successfully created the txt record"
    return 0
  else
    _err "Error encountered during record addition"
    _err "$result"
    return 1
  fi
}

####################  Private functions below ##################################
#
# post changes to MIAB dns (taken from acme.sh)
_miab_post() {
  body="$1"
  _post_url="$2"
  httpmethod="$3"
  username="$4"
  password="$5"

  if [ -z "$httpmethod" ]; then
    httpmethod="POST"
  fi

  _debug $httpmethod
  _debug "_post_url" "$_post_url"
  _debug2 "body" "$body"

  _inithttp

  if [ "$_ACME_CURL" ] && [ "${ACME_USE_WGET:-0}" = "0" ]; then
    _CURL="$_ACME_CURL"

    if [ "$HTTPS_INSECURE" ]; then
      _CURL="$_CURL --insecure  "
    fi

    _debug "_CURL" "$_CURL"
    response="$($_CURL --user-agent "$USER_AGENT" -X $httpmethod --user "$username:$password" -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" -H "$_H5" --data "$body" "$_post_url")"
    _ret="$?"

    if [ "$_ret" != "0" ]; then
      _err "Please refer to https://curl.haxx.se/libcurl/c/libcurl-errors.html for error code: $_ret"
      if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ]; then
        _err "Here is the curl dump log:"
        _err "$(cat "$_CURL_DUMP")"
      fi
    fi

  elif [ "$_ACME_WGET" ]; then
    _WGET="$_ACME_WGET"

    if [ "$HTTPS_INSECURE" ]; then
      _WGET="$_WGET --no-check-certificate "
    fi

    _debug "_WGET" "$_WGET"

    if [ "$httpmethod" = "POST" ]; then
      response="$($_WGET -S -O - --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --post-data="$body" "$_post_url" 2>"$HTTP_HEADER")"
    else
      response="$($_WGET -S -O - --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --method $httpmethod --body-data="$body" "$_post_url" 2>"$HTTP_HEADER")"
    fi

    _ret="$?"

    if [ "$_ret" = "8" ]; then
      _ret=0
      _debug "wget returns 8, the server returns a 'Bad request' response, lets process the response later."
    fi

    if [ "$_ret" != "0" ]; then
      _err "Please refer to https://www.gnu.org/software/wget/manual/html_node/Exit-Status.html for error code: $_ret"
    fi

    _sed_i "s/^ *//g" "$HTTP_HEADER"

  else
    _ret="$?"
    _err "Neither curl nor wget was found, cannot do $httpmethod."
  fi

  _debug "_ret" "$_ret"
  printf "%s" "$response"
  return $_ret
}

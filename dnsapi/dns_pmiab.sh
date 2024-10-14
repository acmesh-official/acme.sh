#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_pmiab_info='Power-Mail-in-a-Box
Site: github.com/ddavness/power-mailinabox
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_pmiab
Options:
 PMIAB_Username Admin username
 PMIAB_Password Admin password
 PMIAB_Server Server hostname. FQDN of your_PMIAB Server
Issues: github.com/acmesh-official/acme.sh/issues/2550
Author: Roland Giesler (lifeboy)
Cloned from dns_miab by Darven Dissek, William Gertz
'

########  Public functions #####################

#Usage: dns_pmiab_add  _acme-challenge.www.domain.com  "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_pmiab_add() {
  fulldomain=$1
  txtvalue="$2"
  _info "Using pmiab challenge add"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  #retrieve pmiab environemt vars
  if ! _retrieve_pmiab_env; then
    return 1
  fi

  #check domain and seperate into domain and host
  if ! _get_root "$fulldomain"; then
    _err "Cannot find any part of ${fulldomain} is hosted on ${PMIAB_Server}"
    return 1
  fi

  _debug2 _sub_domain "$_sub_domain"
  _debug2 _domain "$_domain"

  #add the challenge record
  _api_path="custom/${fulldomain}/txt"
  # Added "value=" and "&ttl=300" to accomodate the new TXT record format used by the PMIAB API
  _pmiab_rest "value=$txtvalue&ttl=300" "$_api_path" "POST"

  #check if result was good
  if _contains "$response" "updated DNS"; then
    _info "Successfully created the txt record"
    return 0
  else
    _err "Error encountered during record add"
    _err "$response"
    return 1
  fi
}

#Usage: dns_pmiab_rm  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_pmiab_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "Using pmiab challenge delete"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  #retrieve PMIAB environemt vars
  if ! _retrieve_pmiab_env; then
    return 1
  fi

  #check domain and separate into domain and host
  if ! _get_root "$fulldomain"; then
    _err "Cannot find any part of ${fulldomain} is hosted on ${PMIAB_Server}"
    return 1
  fi

  _debug2 _sub_domain "$_sub_domain"
  _debug2 _domain "$_domain"

  #Remove the challenge record
  _api_path="custom/${fulldomain}/txt"
  _pmiab_rest "$txtvalue" "$_api_path" "DELETE"

  #check if result was good
  if _contains "$response" "updated DNS"; then
    _info "Successfully removed the txt record"
    return 0
  else
    _err "Error encountered during record remove"
    _err "$response"
    return 1
  fi
}

####################  Private functions below ##################################
#
#Usage: _get_root  _acme-challenge.www.domain.com
#Returns:
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  _passed_domain=$1
  _debug _passed_domain "$_passed_domain"
  _i=2
  _p=1

  #get the zones hosed on PMIAB server, must be a json stream
  _pmiab_rest "" "zones" "GET"

  if ! _is_json "$response"; then
    _err "ERROR fetching domain list"
    _err "$response"
    return 1
  fi

  #cycle through the passed domain seperating out a test domain discarding
  #   the subdomain by marching thorugh the dots
  while true; do
    _test_domain=$(printf "%s" "$_passed_domain" | cut -d . -f "${_i}"-100)
    _debug _test_domain "$_test_domain"

    if [ -z "$_test_domain" ]; then
      return 1
    fi

    #report found if the test domain is in the json response and
    #   report the subdomain
    if _contains "$response" "\"$_test_domain\""; then
      _sub_domain=$(printf "%s" "$_passed_domain" | cut -d . -f 1-"${_p}")
      _domain=${_test_domain}
      return 0
    fi

    #cycle to the next dot in the passed domain
    _p=${_i}
    _i=$(_math "$_i" + 1)
  done

  return 1
}

#Usage: _retrieve_pmiab_env
#Returns (from store or environment variables):
# PMIAB_Username
# PMIAB_Password
# PMIAB_Server
#retrieve PMIAB environment variables, report errors and quit if problems
_retrieve_pmiab_env() {
  PMIAB_Username="${PMIAB_Username:-$(_readaccountconf_mutable PMIAB_Username)}"
  PMIAB_Password="${PMIAB_Password:-$(_readaccountconf_mutable PMIAB_Password)}"
  PMIAB_Server="${PMIAB_Server:-$(_readaccountconf_mutable PMIAB_Server)}"

  #debug log the environmental variables
  _debug PMIAB_Username "$PMIAB_Username"
  _debug PMIAB_Password "$PMIAB_Password"
  _debug PMIAB_Server "$PMIAB_Server"

  #check if PMIAB environemt vars set and quit if not
  if [ -z "$PMIAB_Username" ] || [ -z "$PMIAB_Password" ] || [ -z "$PMIAB_Server" ]; then
    _err "You didn't specify one or more of PMIAB_Username, PMIAB_Password or PMIAB_Server."
    _err "Please check these environment variables and try again."
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable PMIAB_Username "$PMIAB_Username"
  _saveaccountconf_mutable PMIAB_Password "$PMIAB_Password"
  _saveaccountconf_mutable PMIAB_Server "$PMIAB_Server"
  return 0
}

#Useage: _pmiab_rest  "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"  "custom/_acme-challenge.www.domain.com/txt  "POST"
#Returns: "updated DNS: domain.com"
#rest interface PMIAB dns
_pmiab_rest() {
  _data="$1"
  _api_path="$2"
  _httpmethod="$3"

  #encode username and password for basic authentication
  _credentials="$(printf "%s" "$PMIAB_Username:$PMIAB_Password" | _base64)"
  export _H1="Authorization: Basic $_credentials"
  _url="https://${PMIAB_Server}/admin/dns/${_api_path}"

  _debug2 _data "$_data"
  _debug _api_path "$_api_path"
  _debug2 _url "$_url"
  _debug2 _credentails "$_credentials"
  _debug _httpmethod "$_httpmethod"

  if [ "$_httpmethod" = "GET" ]; then
    response="$(_get "$_url")"
  else
    response="$(_post "$_data" "$_url" "" "$_httpmethod")"
  fi

  _retcode="$?"

  if [ "$_retcode" != "0" ]; then
    _err "PMIAB REST authentication failed on $_httpmethod"
    return 1
  fi

  _debug response "$response"
  return 0
}

#Usage: _is_json  "\[\n   "mydomain.com"\n]"
#Reurns "\[\n   "mydomain.com"\n]"
#returns the string if it begins and ends with square braces
_is_json() {
  _str="$(echo "$1" | _normalizeJson)"
  echo "$_str" | grep '^\[.*\]$' >/dev/null 2>&1
}

#!/usr/bin/env sh

# DirectAdmin 1.58.2 API
# This script can be used to deploy certificates to DirectAdmin
#
# User must provide login data and URL (incl. port) to DirectAdmin.
# You can create login key, by using the Login Keys function
# ( https://da.example.com:8443/CMD_LOGIN_KEYS ), which only has access to
# - CMD_API_SSL
#
# Report bugs to https://github.com/Eddict/acme.sh/issues
#
# Values to export:
# export DA_Api="https://remoteUser:remotePassword@da.example.com:8443"
# export DA_Api_Insecure=1
#
# Set DA_Api_Insecure to 1 for insecure and 0 for secure -> difference is
# whether ssl cert is checked for validity (0) or whether it is just accepted (1)
#
# Thanks to https://github.com/TigerP, creator of dnsapi/dns_da.sh
# That script helped a lot to create this one

########  Public functions #####################
directadmin_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  _DA_credentials && _DA_setSSL
  return 0
}

####################  Private functions below ##################################
# Usage: _DA_credentials
# It will check if the needed settings are available
_DA_credentials() {
  DA_Api="${DA_Api:-$(_readaccountconf_mutable DA_Api)}"
  DA_Api_Insecure="${DA_Api_Insecure:-$(_readaccountconf_mutable DA_Api_Insecure)}"
  if [ -z "${DA_Api}" ] || [ -z "${DA_Api_Insecure}" ]; then
    DA_Api=""
    DA_Api_Insecure=""
    _err "You haven't specified the DirectAdmin Login data, URL and whether you want check the DirectAdmin SSL cert. Please try again."
    return 1
  else
    _saveaccountconf_mutable DA_Api "${DA_Api}"
    _saveaccountconf_mutable DA_Api_Insecure "${DA_Api_Insecure}"
    # Set whether curl should use secure or insecure mode
    export HTTPS_INSECURE="${DA_Api_Insecure}"
  fi
}

# Usage: _da_get_api CMD_API_* data example.com
# Use the DirectAdmin API and check the result
# returns
#  response="error=0&text=Result text&details="
_da_get_api() {
  cmd=$1
  data=$2
  domain=$3
  _debug "$domain; $data"

  if ! response=$(_get "$DA_Api/$cmd?$data"); then
    _err "error $cmd"
    return 1
  fi
  _secure_debug2 response "$response"
  return 0
}

# Usage: _DA_setSSL
# Use the API to set the certificates
_DA_setSSL() {
  curData="domain=${_cdomain}&json=yes"
  _debug "Calling _da_get_api: '${curData}' '${DA_Api}/CMD_API_SSL'"
  _da_get_api CMD_API_SSL "${curData}" "${domain}"
  _secure_debug2 "response" "$response"
  cert_response=$response

  name="ssl_on"
  if ! _contains "$cert_response" "$name"; then
    _err "'${name}' was not found in response."
    return 1
  fi
  ssl_on="$(echo "$cert_response" | jq -r .$name)"
  _debug2 "$name" "$ssl_on"

  if [ "$ssl_on" = "yes" ]; then
    _debug "Domain '${_cdomain}' has SSL enabled: $(__green "$ssl_on")"
  else
    _err "Domain '${_cdomain}' does not has SSL enabled: $ssl_on"
    if [ -z "$FORCE" ]; then
      _info "Add '$(__red '--force')' to force to deploy."
      return 1
    fi
  fi

  name="server"
  if ! _contains "$cert_response" "$name"; then
    _err "'${name}' was not found in response."
    return 1
  fi
  server="$(echo "$cert_response" | jq -r .$name)"
  _debug "$name" "$server"

  if [ "$server" = "no" ]; then
    _debug "Domain '${_cdomain}' is using a custom/pasted certificate."
  else
    _err "Domain '${_cdomain}' is using the server certificate."
    if [ -z "$FORCE" ]; then
      _info "Add '$(__red '--force')' to force to deploy."
      return 1
    fi
  fi

  curData="domain=${_cdomain}&view=cacert&json=yes"
  _debug "Calling _DA_da_get_api_getSSL: '${curData}' '${DA_Api}/CMD_API_SSL'"
  _da_get_api CMD_API_SSL "${curData}" "${_cdomain}"
  _secure_debug2 "response" "$response"
  cacert_response=$response

  name="enabled"
  if ! _contains "$cacert_response" "$name"; then
    _err "'${name}' was not found in response."
    return 1
  fi
  enabled="$(echo "$cacert_response" | jq -r .$name)"
  _debug "$name" "$enabled"

  cca=$(cat -v "$_cca")
  cca_flat="$(echo "$cca" | tr -d '\r' | tr -d '\n')"
  ckey=$(cat -v "$_ckey")
  ckey_flat="$(echo "$ckey" | tr -d '\r' | tr -d '\n')"
  ccert=$(cat -v "$_ccert")
  ccert_flat="$(echo "$ccert" | tr -d '\r' | tr -d '\n')"

  name="cacert"
  sameCaCert=1
  if [ "$enabled" = "yes" ]; then
    _debug "Domain '${_cdomain}' is using a CA certificate."

    cacert="$(echo "$cacert_response" | jq -r .$name)"
    cacert_flat="$(echo "$cacert" | tr -d '\r' | tr -d '\n')"
    _debug2 "$name" "$cacert"

    if [ "$cacert_flat" != "$cca_flat" ]; then
      sameCaCert=0
      _info "Domain '${_cdomain}' is using $(__red 'a different') CA certificate."
    else
      _info "Domain '${_cdomain}' is using the same CA certificate."
    fi
  else
    _err "Domain '${_cdomain}' is currently not using a CA certificate."
    if [ -z "$FORCE" ]; then
      _info "Add '$(__red '--force')' to force to deploy."
      return 1
    fi
  fi

  name="key"
  sameKey=1
  if _contains "$cert_response" "$name"; then
    key="$(echo "$cert_response" | jq -r .$name)"
    key_flat="$(echo "$key" | tr -d '\r' | tr -d '\n')"
    _secure_debug2 "$name" "$key"

    if [ "$key_flat" != "$ckey_flat" ]; then
      sameKey=0
      _info "Domain '${_cdomain}' is using $(__red 'a different') private key."
    else
      _info "Domain '${_cdomain}' is using the same private key."
    fi
  fi

  name="certificate"
  sameCert=1
  if _contains "$cert_response" "$name"; then
    cert="$(echo "$cert_response" | jq -r .$name)"
    cert_flat="$(echo "$cert" | tr -d '\r' | tr -d '\n')"
    _debug2 "$name" "$cert"

    if [ "$cert_flat" != "$ccert_flat" ]; then
      sameCert=0
      _info "Domain '${_cdomain}' is using $(__red 'a different') certificate."
    else
      _info "Domain '${_cdomain}' is using the same certificate."
    fi
  fi

  if [ -n "$FORCE" ] || [ $sameCaCert -eq 0 ] || [ $sameKey -eq 0 ] || [ $sameCert -eq 0 ]; then
    if [ -n "$FORCE" ] || [ $sameCaCert -eq 0 ]; then
      export _H1="Content-Type: application/x-www-form-urlencoded"

      encoded_cacert_value="$(printf "%s" "${cca}" | _url_encode)"
      _debug2 encoded_cacert_value "$encoded_cacert_value"
      curData="domain=${_cdomain}&action=save&type=cacert&active=yes&cacert=${encoded_cacert_value}"
      response="$(_post "$curData" "${DA_Api}/CMD_API_SSL")"
      if _contains "${response}" 'error=0'; then
        _info "$(__green "Setting the cacert succeeded for domain '${_cdomain}'.")"
      else
        _err "Setting the cacert failed for domain '${_cdomain}'. Check response:"
        _err "$response"
        return 1
      fi
    fi

    if [ -n "$FORCE" ] || [ $sameKey -eq 0 ] || [ $sameCert -eq 0 ]; then
      export _H1="Content-Type: application/x-www-form-urlencoded"

      encoded_keycert_value="$(printf "%s" "${ckey}$'\n'${ccert}" | _url_encode)"
      _debug2 encoded_cert_value "$encoded_keycert_value"
      curData="domain=${_cdomain}&action=save&type=paste&request=no&certificate=${encoded_keycert_value}"
      response="$(_post "$curData" "${DA_Api}/CMD_API_SSL")"
      if _contains "${response}" 'error=0'; then
        _info "$(__green "Setting the key and cert succeeded for domain '${_cdomain}'.")"
      else
        _err "Setting the key and cert failed for domain '${_cdomain}'. Check response:"
        _err "$response"
        return 1
      fi
    fi
  else
    if [ $sameCaCert -eq 1 ] && [ $sameKey -eq 1 ] && [ $sameCert -eq 1 ]; then
      _info "Nothing to do. Domain '${_cdomain}' $(__green 'has already the same certifcates active.')"
      if [ -z "$FORCE" ]; then
        _info "Add '$(__red '--force')' to force to deploy."
      fi
    fi
  fi

  return 0
}

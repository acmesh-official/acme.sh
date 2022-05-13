#!/usr/bin/env sh
TRANSIP_Api_Url="https://api.transip.nl/v6"
TRANSIP_Token_Read_Only="false"
TRANSIP_Token_Global_Key="false"
TRANSIP_Token_Expiration="30 minutes"
# You can't reuse a label token, so we leave this empty normally
TRANSIP_Token_Label=""

########  Public functions #####################
#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_transip_add() {
  fulldomain="$1"
  _debug fulldomain="$fulldomain"
  txtvalue="$2"
  _debug txtvalue="$txtvalue"
  _transip_setup "$fulldomain" || return 1
  _info "Creating TXT record."
  if ! _transip_rest POST "domains/$_domain/dns" "{\"dnsEntry\":{\"name\":\"$_sub_domain\",\"type\":\"TXT\",\"content\":\"$txtvalue\",\"expire\":300}}"; then
    _err "Could not add TXT record."
    return 1
  fi
  return 0
}

dns_transip_rm() {
  fulldomain=$1
  _debug fulldomain="$fulldomain"
  txtvalue=$2
  _debug txtvalue="$txtvalue"
  _transip_setup "$fulldomain" || return 1
  _info "Removing TXT record."
  if ! _transip_rest DELETE "domains/$_domain/dns" "{\"dnsEntry\":{\"name\":\"$_sub_domain\",\"type\":\"TXT\",\"content\":\"$txtvalue\",\"expire\":300}}"; then
    _err "Could not remove TXT record $_sub_domain for $domain"
    return 1
  fi
  return 0
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain="$1"
  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)

    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
    _domain="$h"

    if _transip_rest GET "domains/$h/dns" && _contains "$response" "dnsEntries"; then
      return 0
    fi

    p=$i
    i=$(_math "$i" + 1)
  done
  _err "Unable to parse this domain"
  return 1
}

_transip_rest() {
  m="$1"
  ep="$2"
  data="$3"
  _debug ep "$ep"
  export _H1="Accept: application/json"
  export _H2="Authorization: Bearer $_token"
  export _H4="Content-Type: application/json"
  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$TRANSIP_Api_Url/$ep" "" "$m")"
    retcode=$?
  else
    response="$(_get "$TRANSIP_Api_Url/$ep")"
    retcode=$?
  fi

  if [ "$retcode" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

_transip_get_token() {
  nonce=$(echo "TRANSIP$(_time)" | _digest sha1 hex | cut -c 1-32)
  _debug nonce "$nonce"

  data="{\"login\":\"${TRANSIP_Username}\",\"nonce\":\"${nonce}\",\"read_only\":\"${TRANSIP_Token_Read_Only}\",\"expiration_time\":\"${TRANSIP_Token_Expiration}\",\"label\":\"${TRANSIP_Token_Label}\",\"global_key\":\"${TRANSIP_Token_Global_Key}\"}"
  _debug data "$data"

  #_signature=$(printf "%s" "$data" | openssl dgst -sha512 -sign "$TRANSIP_Key_File" | _base64)
  _signature=$(printf "%s" "$data" | _sign "$TRANSIP_Key_File" "sha512")
  _debug2 _signature "$_signature"

  export _H1="Signature: $_signature"
  export _H2="Content-Type: application/json"

  response="$(_post "$data" "$TRANSIP_Api_Url/auth" "" "POST")"
  retcode=$?
  _debug2 response "$response"
  if [ "$retcode" != "0" ]; then
    _err "Authentication failed."
    return 1
  fi
  if _contains "$response" "token"; then
    _token="$(echo "$response" | _normalizeJson | sed -n 's/^{"token":"\(.*\)"}/\1/p')"
    _debug _token "$_token"
    return 0
  fi
  return 1
}

_transip_setup() {
  fulldomain=$1

  # retrieve the transip creds
  TRANSIP_Username="${TRANSIP_Username:-$(_readaccountconf_mutable TRANSIP_Username)}"
  TRANSIP_Key_File="${TRANSIP_Key_File:-$(_readaccountconf_mutable TRANSIP_Key_File)}"
  # check their vals for null
  if [ -z "$TRANSIP_Username" ] || [ -z "$TRANSIP_Key_File" ]; then
    TRANSIP_Username=""
    TRANSIP_Key_File=""
    _err "You didn't specify a TransIP username and api key file location"
    _err "Please set those values and try again."
    return 1
  fi
  # save the username and api key to the account conf file.
  _saveaccountconf_mutable TRANSIP_Username "$TRANSIP_Username"
  _saveaccountconf_mutable TRANSIP_Key_File "$TRANSIP_Key_File"

  if [ -f "$TRANSIP_Key_File" ]; then
    if ! grep "BEGIN PRIVATE KEY" "$TRANSIP_Key_File" >/dev/null 2>&1; then
      _err "Key file doesn't seem to be a valid key: ${TRANSIP_Key_File}"
      return 1
    fi
  else
    _err "Can't read private key file: ${TRANSIP_Key_File}"
    return 1
  fi

  if [ -z "$_token" ]; then
    if ! _transip_get_token; then
      _err "Can not get token."
      return 1
    fi
  fi

  _get_root "$fulldomain" || return 1

  return 0
}

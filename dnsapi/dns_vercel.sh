#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_vercel_info='Vercel.com
Site: Vercel.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_vercel
Options:
 VERCEL_TOKEN API Token
'

# This is your API token which can be acquired on the account page.
# https://vercel.com/account/tokens

VERCEL_API="https://api.vercel.com"

#Usage: add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_vercel_add() {
  fulldomain=$1
  txtvalue=$2
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  VERCEL_TOKEN="${VERCEL_TOKEN:-$(_readaccountconf_mutable VERCEL_TOKEN)}"

  if [ -z "$VERCEL_TOKEN" ]; then
    VERCEL_TOKEN=""
    _err "You have not set the Vercel API token yet."
    _err "Please visit https://vercel.com/account/tokens to generate it."
    return 1
  fi

  _saveaccountconf_mutable VERCEL_TOKEN "$VERCEL_TOKEN"

  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"
  if _vercel_rest POST "v2/domains/$_domain/records" "{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"value\":\"$txtvalue\"}"; then
    if printf -- "%s" "$response" | grep "\"uid\":\"" >/dev/null; then
      _info "Added"
      return 0
    else
      _err "Unexpected response while adding text record."
      return 1
    fi
  fi
  _err "Add txt record error."
}

dns_vercel_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _vercel_rest GET "v2/domains/$_domain/records"

  count=$(printf "%s\n" "$response" | _egrep_o "\"name\":\"$_sub_domain\",[^{]*\"type\":\"TXT\"" | wc -l | tr -d " ")

  if [ "$count" = "0" ]; then
    _info "Don't need to remove."
  else
    _record_id=$(printf "%s" "$response" | _egrep_o "\"id\":[^,]*,\"slug\":\"[^,]*\",\"name\":\"$_sub_domain\",[^{]*\"type\":\"TXT\",\"value\":\"$txtvalue\"" | cut -d: -f2 | cut -d, -f1 | tr -d '"')

    if [ "$_record_id" ]; then
      echo "$_record_id" | while read -r item; do
        if _vercel_rest DELETE "v2/domains/$_domain/records/$item"; then
          _info "removed record" "$item"
          return 0
        else
          _err "failed to remove record" "$item"
          return 1
        fi
      done
    fi
  fi
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain="$1"
  ep="$2"
  i=1
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _vercel_rest GET "v4/domains/$h"; then
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\"" >/dev/null; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      _domain=$h
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_vercel_rest() {
  m="$1"
  ep="$2"
  data="$3"

  path="$VERCEL_API/$ep"

  export _H1="Content-Type: application/json"
  export _H2="Authorization: Bearer $VERCEL_TOKEN"

  if [ "$m" != "GET" ]; then
    _secure_debug2 data "$data"
    response="$(_post "$data" "$path" "" "$m")"
  else
    response="$(_get "$path")"
  fi
  _ret="$?"
  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  _debug "http response code $_code"
  _secure_debug2 response "$response"
  if [ "$_ret" != "0" ]; then
    _err "error $ep"
    return 1
  fi

  response="$(printf "%s" "$response" | _normalizeJson)"
  return 0
}

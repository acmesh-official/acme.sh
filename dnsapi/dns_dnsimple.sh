#!/usr/bin/env sh

# DNSimple domain api
#
# This is your oauth token which can be acquired on the account page. Please
# note that this must be an _account_ token and not a _user_ token.
# https://dnsimple.com/a/<your account id>/account/access_tokens
# DNSimple_OAUTH_TOKEN="sdfsdfsdfljlbjkljlkjsdfoiwje"

DNSimple_API="https://api.dnsimple.com/v2"

########  Public functions #####################

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dnsimple_add() {
  fulldomain=$1
  txtvalue=$2

  if [ -z "$DNSimple_OAUTH_TOKEN" ]; then
    DNSimple_OAUTH_TOKEN=""
    _err "You have not set the dnsimple oauth token yet."
    _err "Please visit https://dnsimple.com/user to generate it."
    return 1
  fi

  # save the oauth token for later
  _saveaccountconf DNSimple_OAUTH_TOKEN "$DNSimple_OAUTH_TOKEN"

  _debug "Retrive account ID"
  if ! _get_account_id; then
    _err "failed to retrive account id"
    return 1
  fi
  _debug _account_id "$_account_id"

  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"

  _debug "Getting txt records"
  _dnsimple_rest GET "$_account_id/zones/$_domain/records?per_page=100"

  if ! _contains "$response" "\"id\":"; then
    _err "Error"
    return 1
  fi

  count=$(printf "%s" "$response" | _egrep_o "\"name\":\"$_sub_domain\"" | wc -l | _egrep_o "[0-9]+")
  _debug count "$count"

  if [ "$count" = "0" ]; then
    _info "Adding record"
    if _dnsimple_rest POST "$_account_id/zones/$_domain/records" "{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"content\":\"$txtvalue\",\"ttl\":120}"; then
      if printf -- "%s" "$response" | grep "\"name\":\"$_sub_domain\"" >/dev/null; then
        _info "Added"
        return 0
      else
        _err "Add txt record error."
        return 1
      fi
    fi
    _err "Add txt record error."
  else
    _info "Updating record"
    record_id=$(printf "%s" "$response" | _egrep_o "\"id\":[^,]*,\"zone_id\":\"[^,]*\",\"parent_id\":null,\"name\":\"$_sub_domain\"" | cut -d: -f2 | cut -d, -f1)
    _debug "record_id" "$record_id"

    _dnsimple_rest PATCH "$_account_id/zones/$_domain/records/$record_id" "{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"content\":\"$txtvalue\",\"ttl\":120}"
    if [ "$?" = "0" ]; then
      _info "Updated!"
      #todo: check if the record takes effect
      return 0
    fi
    _err "Update error"
    return 1
  fi
}

# fulldomain
dns_dnsimple_rm() {
  fulldomain=$1

}

####################  Private functions bellow ##################################
# _acme-challenge.www.domain.com
# returns
#   _sub_domain=_acme-challenge.www
#   _domain=domain.com
_get_root() {
  domain=$1
  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    if [ -z "$h" ]; then
      # not valid
      return 1
    fi

    if ! _dnsimple_rest GET "$_account_id/zones/$h"; then
      return 1
    fi

    if _contains "$response" 'not found'; then
      _debug "$h not found"
    else
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain="$h"
      return 0
    fi
    p="$i"
    i=$(_math "$i" + 1)
  done
  return 1
}

_get_account_id() {
  if ! _dnsimple_rest GET "whoami"; then
    return 1
  fi

  if _contains "$response" "\"account\":null"; then
    _err "no account associated with this token"
    return 1
  fi

  if _contains "$response" "timeout"; then
    _err "timeout retrieving account_id"
    return 1
  fi

  _account_id=$(printf "%s" "$response" | _egrep_o "\"id\":[^,]*,\"email\":" | cut -d: -f2 | cut -d, -f1)
  return 0
}

_dnsimple_rest() {
  method=$1
  path="$2"
  data="$3"
  request_url="$DNSimple_API/$path"
  _debug "$path"

  _H1="Accept: application/json"
  _H2="Authorization: Bearer $DNSimple_OAUTH_TOKEN"
  if [ "$data" ]; then
    _H1="Content-Type: application/json"
    _debug data "$data"
    response="$(_post "$data" "$request_url" "" "$method")"
  else
    response="$(_get "$request_url")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $request_url"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

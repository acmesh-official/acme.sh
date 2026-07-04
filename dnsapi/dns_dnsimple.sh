#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_dnsimple_info='DNSimple.com
Site: DNSimple.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_dnsimple
Options:
 DNSimple_OAUTH_TOKEN OAuth Token
 DNSimple_ACCOUNT_ID Account ID. Optional, only needed when the token can access multiple accounts.
Issues: github.com/pho3nixf1re/acme.sh/issues
'

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

  if ! _get_account_id; then
    _err "failed to retrieve account id"
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _get_records "$_account_id" "$_domain" "$_sub_domain"

  _info "Adding record"
  if _dnsimple_rest POST "$_account_id/zones/$_domain/records" "{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"content\":\"$txtvalue\",\"ttl\":120}"; then
    if printf -- "%s" "$response" | grep "\"name\":\"$_sub_domain\"" >/dev/null; then
      _info "Added"
      return 0
    else
      _err "Unexpected response while adding text record."
      return 1
    fi
  fi
  _err "Add txt record error."
}

# fulldomain
dns_dnsimple_rm() {
  fulldomain=$1

  if ! _get_account_id; then
    _err "failed to retrieve account id"
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _get_records "$_account_id" "$_domain" "$_sub_domain"

  _extract_record_id "$_records" "$_sub_domain"
  if [ "$_record_id" ]; then
    echo "$_record_id" | while read -r item; do
      if _dnsimple_rest DELETE "$_account_id/zones/$_domain/records/$item"; then
        _info "removed record" "$item"
        return 0
      else
        _err "failed to remove record" "$item"
        return 1
      fi
    done
  fi
}

####################  Private functions bellow ##################################
# _acme-challenge.www.domain.com
# returns
#   _sub_domain=_acme-challenge.www
#   _domain=domain.com
_get_root() {
  domain=$1
  i=2
  previous=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
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
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$previous")
      _domain="$h"

      _debug _domain "$_domain"
      _debug _sub_domain "$_sub_domain"

      return 0
    fi

    previous="$i"
    i=$(_math "$i" + 1)
  done
  return 1
}

# returns _account_id
_get_account_id() {
  DNSimple_ACCOUNT_ID="${DNSimple_ACCOUNT_ID:-$(_readaccountconf DNSimple_ACCOUNT_ID)}"
  if [ "$DNSimple_ACCOUNT_ID" ]; then
    _saveaccountconf DNSimple_ACCOUNT_ID "$DNSimple_ACCOUNT_ID"
    _account_id="$DNSimple_ACCOUNT_ID"
    _debug _account_id "$_account_id"
    return 0
  fi

  _debug "retrieve account id"
  if ! _dnsimple_rest GET "whoami"; then
    return 1
  fi

  if _contains "$response" "timeout"; then
    _err "timeout retrieving account id"
    return 1
  fi

  if _contains "$response" "\"account\":null"; then
    # the whoami of a user token (dnsimple_u_*) carries no account,
    # so list the accounts the token can access instead
    # https://github.com/acmesh-official/acme.sh/issues/6491
    if ! _dnsimple_rest GET "accounts"; then
      return 1
    fi
  fi

  _account_id=$(printf "%s" "$response" | _egrep_o "\"id\":[^,]*,\"email\":" | cut -d: -f2 | cut -d, -f1)
  if [ -z "$_account_id" ]; then
    _err "no account associated with this token"
    return 1
  fi
  if [ "$(echo "$_account_id" | wc -l)" -gt 1 ]; then
    _err "The token has access to multiple accounts, please pick one and set it explicitly:"
    _err "export DNSimple_ACCOUNT_ID=<one of: $(echo "$_account_id" | tr '\n' ' ')>"
    return 1
  fi
  _debug _account_id "$_account_id"

  return 0
}

# returns
#   _records
#   _records_count
_get_records() {
  account_id=$1
  domain=$2
  sub_domain=$3

  _debug "fetching txt records"
  _dnsimple_rest GET "$account_id/zones/$domain/records?per_page=5000&sort=id:desc"

  if ! _contains "$response" "\"id\":"; then
    _err "failed to retrieve records"
    return 1
  fi

  _records_count=$(printf "%s" "$response" | _egrep_o "\"name\":\"$sub_domain\"" | wc -l | _egrep_o "[0-9]+")
  _records=$response
  _debug _records_count "$_records_count"
}

# returns _record_id
_extract_record_id() {
  _record_id=$(printf "%s" "$_records" | _egrep_o "\"id\":[^,]*,\"zone_id\":\"[^,]*\",\"parent_id\":null,\"name\":\"$_sub_domain\"" | cut -d: -f2 | cut -d, -f1)
  _debug "_record_id" "$_record_id"
}

# returns response
_dnsimple_rest() {
  method=$1
  path="$2"
  data="$3"
  request_url="$DNSimple_API/$path"
  _debug "$path"

  export _H1="Accept: application/json"
  export _H2="Authorization: Bearer $DNSimple_OAUTH_TOKEN"

  if [ "$data" ] || [ "$method" = "DELETE" ]; then
    _H1="Content-Type: application/json"
    _debug data "$data"
    response="$(_post "$data" "$request_url" "" "$method")"
  else
    response="$(_get "$request_url" "" "" "$method")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $request_url"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

#!/usr/bin/env sh
#
# Cloudflare.com API
# https://api.cloudflare.com/
#
# Pass credentials before "acme.sh --issue --dns dns_cf ..."
# --
# export CF_Key="sdfsdfsdfljlbjkljlkjsdfoiwje"
# export CF_Email="xxxx@sss.com"
# --

CF_API="https://api.cloudflare.com/client/v4"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_cf_add() {
  fulldomain="$1"
  txtvalue="$2"

  CF_Key="${CF_Key:-$(_readaccountconf_mutable CF_Key)}"
  CF_Email="${CF_Email:-$(_readaccountconf_mutable CF_Email)}"
  if [ -z "$CF_Key" ] || [ -z "$CF_Email" ]; then
    CF_Key=""
    CF_Email=""
    _err "You don't specify cloudflare api key and email yet."
    _err "Please create you key and try again."
    return 1
  fi

  if ! _contains "$CF_Email" "@"; then
    _err "It seems that the CF_Email=$CF_Email is not a valid email address."
    _err "Please check and retry."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable CF_Key "$CF_Key"
  _saveaccountconf_mutable CF_Email "$CF_Email"

  _debug "First detect the root zone"
  if ! _cf_get_zone; then
    return 1
  fi
  _debug _cf_zone "$_cf_zone"
  _debug _cf_zone_id "$_cf_zone_id"

  _debug "Getting TXT records"
  _cf_rest GET "zones/$_cf_zone_id/dns_records?type=TXT&name=$fulldomain"

  if ! _contains "$response" '"success":true'; then
    _err "Error getting TXT records"
    return 1
  fi

  count="$(printf "%s\n" "$response" | _egrep_o '"count" *: *[^,]*' | _head_n 1 | sed 's#^"count" *: *##')"
  _debug count "$count"
  if [ "$count" = "0" ]; then
    _info "Adding record"
    if _cf_rest POST "zones/$_cf_zone_id/dns_records" "{\"type\":\"TXT\",\"name\":\"$fulldomain\",\"content\":\"$txtvalue\",\"ttl\":120}"; then
      if _contains "$response" "$fulldomain"; then
        _info "Added, OK"
        return 0
      fi
    fi
    _err "Add TXT record error."
  else
    _info "Updating record"
    record_id="$(printf "%s\n" "$response" | _egrep_o '"id" *: *"[^"]*' | _head_n 1 | sed 's#^"id" *: *"##')"
    _debug record_id "$record_id"

    if _cf_rest PUT "zones/$_cf_zone_id/dns_records/$record_id" "{\"id\":\"$record_id\",\"type\":\"TXT\",\"name\":\"$fulldomain\",\"content\":\"$txtvalue\",\"zone_id\":\"$_cf_zone_id\",\"zone_name\":\"$_cf_zone\"}"; then
      _info "Updated, OK"
      return 0
    fi
    _err "Update TXT record error"
  fi

  return 1
}

#fulldomain txtvalue
dns_cf_rm() {
  fulldomain="$1"
  txtvalue="$2"

  CF_Key="${CF_Key:-$(_readaccountconf_mutable CF_Key)}"
  CF_Email="${CF_Email:-$(_readaccountconf_mutable CF_Email)}"
  if [ -z "$CF_Key" ] || [ -z "$CF_Email" ]; then
    CF_Key=""
    CF_Email=""
    _err "You don't specify cloudflare api key and email yet."
    _err "Please create you key and try again."
    return 1
  fi

  _debug "First detect the root zone"
  if ! _cf_get_zone; then
    return 1
  fi
  _debug _cf_zone "$_cf_zone"
  _debug _cf_zone_id "$_cf_zone_id"

  _debug "Getting TXT records"
  _cf_rest GET "zones/$_cf_zone_id/dns_records?type=TXT&name=$fulldomain&content=$txtvalue"

  if ! _contains "$response" '"success":true'; then
    _err "Error getting TXT records"
    return 1
  fi

  count="$(printf "%s\n" "$response" | _egrep_o '"count" *: *[^,]*' | _head_n 1 | sed 's#^"count" *: *##')"
  _debug count "$count"
  if [ "$count" = "0" ]; then
    _info "Don't need to remove."
    return 0
  fi

  record_id="$(printf "%s\n" "$response" | _egrep_o '"id" *: *"[^"]*' | _head_n 1 | sed 's#^"id" *: *"##')"
  _debug record_id "$record_id"
  if [ -z "$record_id" ]; then
    _err "Can not get record id to remove."
    return 1
  fi

  if _cf_rest DELETE "zones/$_cf_zone_id/dns_records/$record_id"; then
    if _contains "$response" '"success":true'; then
      return 0
    fi
  fi
  _err "Delete record error."

  return 1
}

####################  Private functions below ##################################
#fulldomain=_acme-challenge.www.domain.com
#returns
# _cf_zone=domain.com
# _cf_zone_id=sdjkglgdfewsdfg
_cf_get_zone() {
  i=2
  while true; do
    domain="$(printf "%s" "$fulldomain" | cut -d . -f "$i-100")"
    if [ -z "$domain" ]; then
      break
    fi

    if ! _cf_rest GET "zones?name=$domain"; then
      break
    fi

    _debug domain "$domain"

    if _contains "$response" "\"name\":\"$domain\""; then
      _cf_zone_id="$(printf "%s\n" "$response" | _egrep_o '\[."id" *: *"[^"]*' | _head_n 1 | sed 's#^\[."id" *: *"##')"
      if [ -z "$_cf_zone_id" ]; then
        break
      fi
      _cf_zone="$domain"
      return 0
    fi
    i=$(_math "$i" + 1)
  done

  _cf_zone=""
  _cf_zone_id=""
  _err "get zone failed"
  return 1
}

_cf_rest() {
  method="$1"
  request="$2"
  data="$3"

  export _H1="X-Auth-Email: $CF_Email"
  export _H2="X-Auth-Key: $CF_Key"
  export _H3="Content-Type: application/json"

  if [ "$method" = "GET" ]; then
    _debug request "$request"
    response="$(_get "$CF_API/$request" "" "")"
  else
    _debug data "$data"
    _debug request "$request"
    response="$(_post "$data" "$CF_API/$request" "" "$method")"
  fi

  if [ "$?" != "0" ]; then
    _err "error for request: $request"
    return 1
  fi

  _debug2 response "$response"
  return 0
}

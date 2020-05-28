#!/usr/bin/env sh

#
#CF_Key="sdfsdfsdfljlbjkljlkjsdfoiwje"
#
#CF_Email="xxxx@sss.com"

#CF_Token="xxxx"
#CF_Account_ID="xxxx"
#CF_Zone_ID="xxxx"

CF_Api="https://api.cloudflare.com/client/v4"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_cf_add() {
  fulldomain=$1
  txtvalue=$2

  CF_Token="${CF_Token:-$(_readaccountconf_mutable CF_Token)}"
  CF_Account_ID="${CF_Account_ID:-$(_readaccountconf_mutable CF_Account_ID)}"
  CF_Zone_ID="${CF_Zone_ID:-$(_readaccountconf_mutable CF_Zone_ID)}"
  CF_Key="${CF_Key:-$(_readaccountconf_mutable CF_Key)}"
  CF_Email="${CF_Email:-$(_readaccountconf_mutable CF_Email)}"

  if [ "$CF_Token" ]; then
    _saveaccountconf_mutable CF_Token "$CF_Token"
    _saveaccountconf_mutable CF_Account_ID "$CF_Account_ID"
    _saveaccountconf_mutable CF_Zone_ID "$CF_Zone_ID"
  else
    if [ -z "$CF_Key" ] || [ -z "$CF_Email" ]; then
      CF_Key=""
      CF_Email=""
      _err "You didn't specify a Cloudflare api key and email yet."
      _err "You can get yours from here https://dash.cloudflare.com/profile."
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
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _cf_rest GET "zones/${_domain_id}/dns_records?type=TXT&name=$fulldomain"

  if ! echo "$response" | tr -d " " | grep \"success\":true >/dev/null; then
    _err "Error"
    return 1
  fi

  # For wildcard cert, the main root domain and the wildcard domain have the same txt subdomain name, so
  # we can not use updating anymore.
  #  count=$(printf "%s\n" "$response" | _egrep_o "\"count\":[^,]*" | cut -d : -f 2)
  #  _debug count "$count"
  #  if [ "$count" = "0" ]; then
  _info "Adding record"
  if _cf_rest POST "zones/$_domain_id/dns_records" "{\"type\":\"TXT\",\"name\":\"$fulldomain\",\"content\":\"$txtvalue\",\"ttl\":120}"; then
    if _contains "$response" "$txtvalue"; then
      _info "Added, OK"
      return 0
    elif _contains "$response" "The record already exists"; then
      _info "Already exists, OK"
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi
  _err "Add txt record error."
  return 1

}

#fulldomain txtvalue
dns_cf_rm() {
  fulldomain=$1
  txtvalue=$2

  CF_Token="${CF_Token:-$(_readaccountconf_mutable CF_Token)}"
  CF_Account_ID="${CF_Account_ID:-$(_readaccountconf_mutable CF_Account_ID)}"
  CF_Zone_ID="${CF_Zone_ID:-$(_readaccountconf_mutable CF_Zone_ID)}"
  CF_Key="${CF_Key:-$(_readaccountconf_mutable CF_Key)}"
  CF_Email="${CF_Email:-$(_readaccountconf_mutable CF_Email)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _cf_rest GET "zones/${_domain_id}/dns_records?type=TXT&name=$fulldomain&content=$txtvalue"

  if ! echo "$response" | tr -d " " | grep \"success\":true >/dev/null; then
    _err "Error: $response"
    return 1
  fi

  count=$(echo "$response" | _egrep_o "\"count\": *[^,]*" | cut -d : -f 2 | tr -d " ")
  _debug count "$count"
  if [ "$count" = "0" ]; then
    _info "Don't need to remove."
  else
    record_id=$(echo "$response" | _egrep_o "\"id\": *\"[^\"]*\"" | cut -d : -f 2 | tr -d \" | _head_n 1 | tr -d " ")
    _debug "record_id" "$record_id"
    if [ -z "$record_id" ]; then
      _err "Can not get record id to remove."
      return 1
    fi
    if ! _cf_rest DELETE "zones/$_domain_id/dns_records/$record_id"; then
      _err "Delete record error."
      return 1
    fi
    echo "$response" | tr -d " " | grep \"success\":true >/dev/null
  fi

}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1
  i=1
  p=1

  # Use Zone ID directly if provided
  if [ "$CF_Zone_ID" ]; then
    if ! _cf_rest GET "zones/$CF_Zone_ID"; then
      return 1
    else
      if echo "$response" | tr -d " " | grep \"success\":true >/dev/null; then
        _domain=$(echo "$response" | _egrep_o "\"name\": *\"[^\"]*\"" | cut -d : -f 2 | tr -d \" | _head_n 1 | tr -d " ")
        if [ "$_domain" ]; then
          _cutlength=$((${#domain} - ${#_domain} - 1))
          _sub_domain=$(printf "%s" "$domain" | cut -c "1-$_cutlength")
          _domain_id=$CF_Zone_ID
          return 0
        else
          return 1
        fi
      else
        return 1
      fi
    fi
  fi

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if [ "$CF_Account_ID" ]; then
      if ! _cf_rest GET "zones?name=$h&account.id=$CF_Account_ID"; then
        return 1
      fi
    else
      if ! _cf_rest GET "zones?name=$h"; then
        return 1
      fi
    fi

    if _contains "$response" "\"name\":\"$h\"" || _contains "$response" '"total_count":1'; then
      _domain_id=$(echo "$response" | _egrep_o "\[.\"id\": *\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d \" | tr -d " ")
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
        _domain=$h
        return 0
      fi
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_cf_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  email_trimmed=$(echo "$CF_Email" | tr -d '"')
  key_trimmed=$(echo "$CF_Key" | tr -d '"')
  token_trimmed=$(echo "$CF_Token" | tr -d '"')

  export _H1="Content-Type: application/json"
  if [ "$token_trimmed" ]; then
    export _H2="Authorization: Bearer $token_trimmed"
  else
    export _H2="X-Auth-Email: $email_trimmed"
    export _H3="X-Auth-Key: $key_trimmed"
  fi

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$CF_Api/$ep" "" "$m")"
  else
    response="$(_get "$CF_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

#!/usr/bin/env sh

#
#AD_API_KEY="sdfsdfsdfljlbjkljlkjsdfoiwje"

#This is the Alwaysdata api wrapper for acme.sh

AD_HOST="api.alwaysdata.com"
AD_URL="https://$AD_API_KEY:@$AD_HOST"

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_ad_add() {
  fulldomain=$1
  txtvalue=$2

  if [ -z "$AD_API_KEY" ]; then
    AD_API_KEY=""
    _err "You didn't specify the AD api key yet."
    _err "Please create you key and try again."
    return 1
  fi

  _saveaccountconf AD_API_KEY "$AD_API_KEY"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _ad_tmpl_json="{\"domain\":$_domain_id,\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"value\":\"$txtvalue\"}"
  
  if ad_rest POST "record/" "" "$_ad_tmpl_json" && [ -z "$response" ]; then
    _info "txt record updated success."
    return 0
  fi
  
  return 1
}

#fulldomain txtvalue
dns_ad_rm() {
  fulldomain=$1
  txtvalue=$2

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  if ad_rest DELETE "record/" "domain=$_domain_id&name=$_sub_domain" "" && [ -z "$response" ]; then
    _info "txt record deleted success."
    return 0
  fi
  _debug response "$response"

  return 1
}

####################  Private functions below ##################################

_get_root() {
  domain=$1
  i=2
  p=1

  if ad_rest GET "domain/"; then
    while true; do
      h=$(printf "%s" "$domain" | cut -d . -f $i-100)
      if [ -z "$h" ]; then
        #not valid
        return 1
      fi

      if _contains "$response" "<name>$h</name>"; then
        hostedzone="$(echo "$response" | tr -d "\n" | sed 's/<object>/\n&/g' | _egrep_o "<object>.*<name>$h<.name>.*<.object>")"
        if [ -z "$hostedzone" ]; then
          _err "Error, can not get domain record."
          return 1
        fi
        _domain_id=$(printf "%s\n" "$hostedzone" | _egrep_o "<id>.*<.id>" | head -n 1 | _egrep_o ">.*<" | tr -d "<>")
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
  fi
  return 1
}

#method uri qstr data
ad_rest() {
  mtd="$1"
  ep="$2"
  qsr="$3"
  data="$4"

  _debug mtd "$mtd"
  _debug ep "$ep"
  _debug qsr "$qsr"
  _debug data "$data"

  _H1="Accept: application/xml"
  
  url="$AD_URL/v1/$ep?$qsr"

  if [ "$mtd" = "GET" ]; then
    response="$(_get "$url")"
  elif [ "$mtd" = "DELETE" ]; then
    response="$(_delete "$url")"
  else
    response="$(_post "$data" "$url")"
  fi

  _ret="$?"
  if [ "$_ret" = "0" ]; then
    # Errors usually 404, otherwise just empty response. How to detect 404?
    if _contains "$response" "<ErrorResponse"; then
      _err "Response error:$response"
      return 1
    fi
  fi

  return "$_ret"
}

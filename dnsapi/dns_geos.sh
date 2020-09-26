#!/usr/bin/env sh
########################################################################
# GeoScaling hook script for acme.sh
#
# Environment variables:
#
#  - $GEOS_Username  (your geoscaling.com username)
#  - $GEOS_Password  (your geoscaling.com password)
#
# Author: Jinhill.Chen <cb@jinhill.com>
# Git repo: https://github.com/jinhill/acme.sh

export COOKIE_FILE="$LE_CONFIG_HOME/http.cookie"
export USER_AGENT='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/85.0.4183.102 Safari/537.36'
#Add cookie to request
export _ACME_CURL="curl -k -s -c $COOKIE_FILE -b $COOKIE_FILE --dump-header $HTTP_HEADER "

#-- dns_geos_add() - Add TXT record --------------------------------------
# Usage: dns_geos_add _acme-challenge.subdomain.domain.com "XyZ123..."

dns_geos_add() {
  _full_domain=$1
  _txt_value=$2
  _info "Using DNS-01 GeoScaling hook"

  _login || return 1
  _get_zone "$_full_domain" || return 1
  _debug "zone id \"$_zone_id\" will be used."

  body="id=${_zone_id}&name=${_sub_domain}&type=TXT&content=${_txt_value}&ttl=300&prio=0"
  response=$(_post "$body" "https://www.geoscaling.com/dns2/ajax/add_record.php")
  _debug "add:$response"
  if _contains "$response" '"code":"OK"'; then
    _info "TXT record added successfully."
  else
    _err "Couldn't add the TXT record."
    return 1
  fi
  _debug2 response "$response"
  return 0
}

#-- dns_geos_rm() - Remove TXT record ------------------------------------
# Usage: dns_geos_rm _acme-challenge.subdomain.domain.com "XyZ123..."

dns_geos_rm() {
  _full_domain=$1
  _txt_value=$2
  _info "Cleaning up after DNS-01 GeoScaling hook"
  _login || return 1
  _get_zone "$_full_domain" || return 1
  _debug "zone id \"$_zone_id\" will be used."

  # Find the record id to clean
  record_id=$(_get_record_id "$_zone_id" "$_full_domain") || return 1
  body="id=${_zone_id}&record_id=${record_id}"
  response=$(_post "$body" "https://www.geoscaling.com/dns2/ajax/delete_record.php")
  _debug "rm:$response"
  if _contains "$response" '"code":"OK"'; then
    _info "Record removed successfully."
  else
    _err "Could not clean (remove) up the record. Please go to GEOS administration interface and clean it by hand."
    return 1
  fi
  return 0
}

########################## PRIVATE FUNCTIONS ###########################
#$1:string,$2:char,$ret:count
_count() {
  echo "$1" | awk -F"$2" '{print NF-1}'
}

_login() {
  GEOS_Username="${GEOS_Username:-$(_readaccountconf_mutable GEOS_Username)}"
  GEOS_Password="${GEOS_Password:-$(_readaccountconf_mutable GEOS_Password)}"
  if [ -z "$GEOS_Username" ] || [ -z "$GEOS_Password" ]; then
    GEOS_Username=
    GEOS_Password=
    _err "No auth details provided. Please set user credentials using the \$GEOS_Username and \$GEOS_Password environment variables."
    return 1
  fi
  _saveaccountconf_mutable GEOS_Username "$GEOS_Username"
  _saveaccountconf_mutable GEOS_Password "$GEOS_Password"
  username_encoded=$(printf "%s" "${GEOS_Username}" | _url_encode)
  password_encoded=$(printf "%s" "${GEOS_Password}" | _url_encode)
  body="username=${username_encoded}&password=${password_encoded}"
  if ! _post "$body" "https://www.geoscaling.com/dns2/index.php?module=auth"; then
    _err "geoscaling login failed for user $GEOS_Username bad RC from _post"
    return 1
  fi
  resp_header=$(grep 'HTTP/2 302' "$HTTP_HEADER")
  if [ -z "$resp_header" ]; then
    _err "geoscaling login failed for user $GEOS_Username. Check $HTTP_HEADER file"
    return 1
  fi
  return 0
}

#$1:full domain name,_acme-challenge.www.domain.com
#ret:
# _sub_domain=_acme-challenge.www
# _zone_id=xxxxxx
_get_zone() {
  response=$(_get "https://www.geoscaling.com/dns2/index.php?module=domains")
  table=$(echo "$response" | tr -d "\n" | grep -oP "(?<=<table border='0' align='center' cellpadding='10' cellspacing='10' class=\"threecolumns\">).*?(?=</table>)")
  items=$(echo "$table" | grep -oP "(?<=<a).*?(?=</a>)")
  #_debug "items=$items"
  i=2
  c=$(_count "$1" ".")
  while [ $i -le "$c" ]; do
    d=$(echo "$1" | cut -d . -f $i-)
    if [ -z "$d" ]; then
      return 1
    fi
    id=$(echo "$items" | grep -oP "id=[0-9]*.*$d" | cut -d "'" -f 1)
    if [ -n "$id" ]; then
      _sub_domain=$(echo "$1" | sed "s/.$d//")
      _zone_id=${id##*=}
      _debug "zone_id=$_zone_id"
      return 0
    fi
    i=$(_math "$i" + 1)
  done
  return 1
}

#$1:domain id,$2:dns fullname
_get_record_id() {
  response=$(_get "https://www.geoscaling.com/dns2/index.php?module=domain&id=$1")
  id=$(echo "$response" | tr -d "\n" | grep -oP "(?<=<table id='records_table').*?(?=</table>)" | grep -oP "id=\"[0-9]*.name\">$2" | cut -d '"' -f 2)
  if [ -z "$id" ]; then
    _err "DNS record $2 not found."
    return 1
  fi
  echo "${id%%.*}"
  return 0
}

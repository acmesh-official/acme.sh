#!/usr/bin/env sh

# WEDOS_Auth sha1($login.sha1($wpass).date('H', time()));
# TZ="Europe/Prague"
#
# Provide either Pass or Hash, hash'll be stored for renewal
# WEDOS_User = test@test
# WEDOS_Pass = test123
# WEDOS_Hash = sha1(WEDOS_Pass)

WEDOS_Api="https://api.wedos.com/wapi/json"
WEDOS_Hour=$(TZ="CET-1CEST,M3.5.0,M10.5.0/3" date +%H)

########  Public functions #####################

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_wedos_add() {
  fulldomain=$1
  txtvalue=$2

  _wedos_init

  _info "Adding txt record"

  response=
  if _wedos_rest '{ "request": {"user": "'"$WEDOS_User"'", "auth": "'"$WEDOS_Token"'", "command": "dns-row-add", "data": { "domain": "'"$_domain"'", "name": "'"$_sub_domain"'", "ttl": "600", "type": "TXT", "rdata": "'"$txtvalue"'" }}}'; then
    _info "Added, OK"
    if _wedos_rest '{ "request": {"user": "'"$WEDOS_User"'", "auth": "'"$WEDOS_Token"'", "command": "dns-domain-commit", "data": { "name": "'"$_domain"'" }}}'; then
      _info "Commit changes, OK"
      return 0
    else
      _err "Commit changes, Error"
      return 1
    fi
    return 0
  fi
  
  _err "Adding txt record, Error"
  return 1
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
dns_wedos_rm() {
  fulldomain=$1
  txtvalue=$2

  _wedos_init

  _debug "Getting txt records"

  response=
  if _wedos_rest '{ "request": {"user": "'"$WEDOS_User"'", "auth": "'"$WEDOS_Token"'", "command": "dns-rows-list", "data": { "domain": "'"$_domain"'" }}}'; then
    domain_info=$(printf "%s\n" "$response" | _egrep_o '\"ID\":\"[0-9]+\",\"name\":\"'"$_sub_domain"'\",\"ttl\":\"[0-9]+\",\"rdtype\":\"TXT\",\"rdata\":\"'"$txtvalue"'\"')
    domain_id=$(printf "%s\n" "$domain_info" | _egrep_o '\"ID\":\"[0-9]+\"' | _egrep_o '[0-9]+')
    _debug "Found txt record: $domain_info"
    _debug "ID: $domain_id"

    if _wedos_rest '{ "request": {"user": "'"$WEDOS_User"'", "auth": "'"$WEDOS_Token"'", "command": "dns-row-detail", "data": { "domain": "'"$_domain"'", "row_id": "'"$domain_id"'" }}}'; then
      checked_domain_info=$(printf "%s\n" "$response" | _egrep_o '\"ID\":\"[0-9]+\",\"name\":\"'"$_sub_domain"'\"')
      checked_domain_id=$(printf "%s\n" "$checked_domain_info" | _egrep_o '\"[0-9]+\"')
      if _wedos_rest '{ "request": {"user": "'"$WEDOS_User"'", "auth": "'"$WEDOS_Token"'", "command": "dns-row-delete", "data": { "domain": "'"$_domain"'", "row_id": '"$checked_domain_id"' }}}'; then
        _info "Txt record id: $checked_domain_id deleted."
        return 0
      fi
    fi
  fi

  _err "Deleting txt record, Error"
  return 1
}

####################  Private functions below ##################################
_wedos_rest() {

  _data=$(printf "%s" "$1" | _url_encode)
  _body_url="request="$_data

  _debug "$_data"
  _debug "$_body_url"

  # body  url [needbase64] [POST|PUT|DELETE] [ContentType]
  response=$(_post "$_body_url" $WEDOS_Api "" "POST" "application/x-www-form-urlencoded")
  _debug "$response"
  if _contains "$response" '"code":1000'; then
    return 0
  fi

  _err "Rest request, Error"
  return 1
}

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1

  if ! _wedos_rest '{ "request": {"user": "'"$WEDOS_User"'", "auth": "'"$WEDOS_Token"'", "command": "dns-domains-list" }}'; then
    return 1
  fi

  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug "h" "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if _contains "$response" "\"$h\"" >/dev/null; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain=$h
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_wedos_init() {

  WEDOS_Hash="${WEDOS_Hash:-$(_readaccountconf_mutable WEDOS_Hash)}"
  WEDOS_User="${WEDOS_User:-$(_readaccountconf_mutable WEDOS_User)}"

  if [ ! -z "$WEDOS_Pass" && -z "$WEDOS_Hash" ]; then
    WEDOS_Hash=$(printf "%s" "$WEDOS_Pass" | _digest sha1 1)  
  fi

  if [ -z "$WEDOS_Hash" ]; then
    _err "You didn't specify a wedos hash or password yet."
    _err "Please create hash or password and try again."
    return 1
  fi
  
  _saveaccountconf_mutable WEDOS_Hash "$WEDOS_Hash"

  if [ -z "$WEDOS_User" ]; then
    WEDOS_User=""
    _err "You didn't specify a wedos username yet."
    _err "Please create user and try again."
  fi
  
  _saveaccountconf_mutable WEDOS_User "$WEDOS_User"

  WEDOS_Token=$(printf "%s" "$WEDOS_User$WEDOS_Hash$WEDOS_Hour" | _digest sha1 1)

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
}

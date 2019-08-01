#!/usr/bin/env sh

#Here is a sample custom api script.
#This file name is "dns_hover.sh"
#
#So, here must be a method   dns_hover_add()
#So, here must be a method   dns_hover_rm()
#
#Which will be called by acme.sh to add the txt record to your api system.
#returns 0 means success, otherwise error.
#
#Author: Neilpang
#Report Bugs here: https://github.com/Neilpang/acme.sh
#
########  Public functions #####################

HOVER_Api="https://www.hover.com/api"

#Usage: dns_hover_add   _acme-challenge.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_hover_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Using HOVER"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  ########### Login first ###########
   if ! _HOVER_login; then
    _err "Cannot Login"
    return 1
  fi

  ########### Now detect current config ###########
  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _cf_rest GET "domains/$_domain_id/dns"

  if ! printf "%s" "$response" | grep \"succeeded\":true >/dev/null; then
    _err "Error"
    return 1
  fi

  ########### ADD or UPDATE ###########
  count=$(printf "%s\n" "$response" | _egrep_o ",\"name\":\"$_sub_domain\",\"type\":\"TXT\"[^,]*" | cut -d : -f 2| wc -l )
  _debug count "$count"
  if [ "$count" -eq "0" ]; then
    _info "Adding record"

    if _cf_rest POST "domains/$_domain_id/dns" "{\"name\":\"$_sub_domain\",\"type\":\"TXT\",\"content\":\"$txtvalue\",\"ttl\":120,\"is_default\":false,\"can_revert\":false}"; then

      if ! _contains "$response" "\"succeeded\":true"; then
        _err "Add txt record error."
        return 1
      else
        _info "Added, OK"
        return 0
      fi
    fi
    _err "Add txt record error."
  fi

#  else
#    _info "Updating record"
#    record_id=$(printf "%s\n" "$response" | _egrep_o "\"id\":\"[^\"]*\",\"name\":\"$_sub_domain\",\"type\":\"TXT\"" | tr -d \" | tr "," ":" | cut -d : -f 2  | head -n 1)
#    _debug "record_id" "$record_id"
#
#    _cf_rest PUT "domains/$_domain_id/dns/$record_id" "{\"id\":\"$record_id\",\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"content\":\"$txtvalue\",\"zone_id\":\"$_domain_id\",\"zone_name\":\"$_domain\"}"
#    if [ "$?" = "0" ]; then
#      _info "Updated, OK"
#      return 0
#    fi
#    _err "Update error"
#    return 1

  # verify response
  if ! _contains "$response" "\"succeeded\":true"; then
    _err "Error"
    return 1
  fi

}

########### DELETE ###########
#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_hover_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "Using hover"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  ########### Login first ###########
  if ! _HOVER_login; then
    _err "Cannot Login"
    return 1
  fi

  ########### Now detect current config ###########
  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _cf_rest GET "domains/$_domain_id/dns"

  # verify response
  if ! _contains "$response" "\"succeeded\":true"; then
    _err "Error"
    return 1
  fi

  ########### DELETE ###########
  count=$(printf "%s\n" "$response" | _egrep_o ",\"name\":\"$_sub_domain\",\"type\":\"TXT\",\"content\":\"$txtvalue\"" | cut -d : -f 2| wc -l )
  _debug count "$count"

  if [ "$count" -eq "0" ]; then
    _info "Don't need to remove."
  else
        # Get the record id to delete
    record_id=$(printf "%s\n" "$response" | _egrep_o "\"id\":\"[^\"]*\",\"name\":\"$_sub_domain\",\"type\":\"TXT\",\"content\":\"$txtvalue\"" | tr -d \" | tr "," ":" | cut -d : -f 2  | head -n 1)
    _debug "record_id" "$record_id"
    if [ -z "$record_id" ]; then
      _err "Can not get record id to remove."
      return 1
    fi
        # Delete the record
    if ! _cf_rest DELETE "domains/$_domain_id/dns/$record_id"; then
      _err "Delete record error in call."
      return 1
    fi
        # verify response
        if ! _contains "$response" "\"succeeded\":true"; then
          _err "Delete record error in response."
      return 1
        fi

  fi

}

################################################################################
####################  Private functions below ##################################
################################################################################

# usage: _HOVER_login
# returns 0 success
_HOVER_login() {

#save the credentials to the account conf file required for testing
# _saveaccountconf_mutable HOVER_Username  "$HOVER_Username"
# _saveaccountconf_mutable HOVER_Password  "$HOVER_Password"

  if [ -z "$HOVER_COOKIE" ]; then

    HOVER_Username="${HOVER_Username:-$(_readaccountconf_mutable HOVER_Username)}"
    HOVER_Password="${HOVER_Password:-$(_readaccountconf_mutable HOVER_Password)}"

        if [ -z "$HOVER_Username" ] || [ -z "$HOVER_Password" ]; then

          _err "You did not specify the HOVER username and password yet."
          _err "Please export as HOVER_Username / HOVER_Password and try again."
      HOVER_Username=""
      HOVER_Password=""
          return 1
        else

          _debug "Login to HOVER as user $HOVER_Username"
      _cf_rest POST "login" "username=$(printf '%s' "$HOVER_Username")&password=$(printf '%s' "$HOVER_Password")"
          if [ "$?" != "0" ]; then
                _err "HOVER login failed for user $username bad RC from _post"
                return 1
          fi

          export HOVER_COOKIE="$(grep -i '^.*Cookie:.*hoverauth=.*$' "$HTTP_HEADER" | _head_n 1 | tr -d "\r\n" | cut -d ":" -f 2)"

          if [ -z "$HOVER_COOKIE" ]; then
                _debug3 response "$response"
                _err "HOVER login failed for user $username. Check $HTTP_HEADER file"
            return 1
          else
            _debug "HOVER login cookies: $HOVER_COOKIE (cached = $using_cached_cookies)"
                return 0
          fi
        fi
  else
    # use Cookie
        return 0
  fi

return 1

}


#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1
  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _cf_rest GET "domains"; then
      return 1
    fi

    if _contains "$response" "\"domain_name\":\"$h\"" >/dev/null; then
      _domain_id=$(printf "%s\n" "$response" | _egrep_o '\[.\"id\":\"[^\"]*\"' | head -n 1 | cut -d : -f 2 | tr -d \")
      if [ -n "$_domain_id" ]; then
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

  if [ "$ep" != "login" ]; then
        _H1="Cookie:$HOVER_COOKIE"
        _H3="Content-Type: application/json"
  fi

        _H2="Accept-Language:en-US"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$HOVER_Api/$ep" "" "$m")"
  else
    response="$(_get "$HOVER_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

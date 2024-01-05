#!/usr/bin/env sh

# DNS API for acme.sh for Core-Networks (https://beta.api.core-networks.de/doc/).
# created by 5ll and francis

CN_API="https://beta.api.core-networks.de"

########  Public functions  #####################

dns_cn_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _cn_login; then
    _err "login failed"
    return 1
  fi

  _debug "First detect the root zone"
  if ! _cn_get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug "_sub_domain $_sub_domain"
  _debug "_domain $_domain"

  _info "Adding record"
  curData="{\"name\":\"$_sub_domain\",\"ttl\":120,\"type\":\"TXT\",\"data\":\"$txtvalue\"}"
  curResult="$(_post "${curData}" "${CN_API}/dnszones/${_domain}/records/")"

  _debug "curData $curData"
  _debug "curResult $curResult"

  if _contains "$curResult" ""; then
    _info "Added, OK"

    if ! _cn_commit; then
      _err "commiting changes failed"
      return 1
    fi
    return 0

  else
    _err "Add txt record error."
    _debug "curData is $curData"
    _debug "curResult is $curResult"
    _err "error adding text record, response was $curResult"
    return 1
  fi
}

dns_cn_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _cn_login; then
    _err "login failed"
    return 1
  fi

  _debug "First detect the root zone"
  if ! _cn_get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _info "Deleting record"
  curData="{\"name\":\"$_sub_domain\",\"data\":\"$txtvalue\"}"
  curResult="$(_post "${curData}" "${CN_API}/dnszones/${_domain}/records/delete")"
  _debug curData is "$curData"

  _info "commiting changes"
  if ! _cn_commit; then
    _err "commiting changes failed"
    return 1
  fi

  _info "Deletet txt record"
  return 0
}

###################  Private functions below  ##################################
_cn_login() {
  CN_User="${CN_User:-$(_readaccountconf_mutable CN_User)}"
  CN_Password="${CN_Password:-$(_readaccountconf_mutable CN_Password)}"
  if [ -z "$CN_User" ] || [ -z "$CN_Password" ]; then
    CN_User=""
    CN_Password=""
    _err "You must export variables: CN_User and CN_Password"
    return 1
  fi

  #save the config variables to the account conf file.
  _saveaccountconf_mutable CN_User "$CN_User"
  _saveaccountconf_mutable CN_Password "$CN_Password"

  _info "Getting an AUTH-Token"
  curData="{\"login\":\"${CN_User}\",\"password\":\"${CN_Password}\"}"
  curResult="$(_post "${curData}" "${CN_API}/auth/token")"
  _debug "Calling _CN_login: '${curData}' '${CN_API}/auth/token'"

  if _contains "${curResult}" '"token":"'; then
    authToken=$(echo "${curResult}" | cut -d ":" -f2 | cut -d "," -f1 | sed 's/^.\(.*\).$/\1/')
    export _H1="Authorization: Bearer $authToken"
    _info "Successfully acquired AUTH-Token"
    _debug "AUTH-Token: '${authToken}'"
    _debug "_H1 '${_H1}'"
  else
    _err "Couldn't acquire an AUTH-Token"
    return 1
  fi
}

# Commit changes
_cn_commit() {
  _info "Commiting changes"
  _post "" "${CN_API}/dnszones/$h/records/commit"
}

_cn_get_root() {
  domain=$1
  i=2
  p=1
  while true; do

    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    _debug _H1 "${_H1}"

    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    _cn_zonelist="$(_get ${CN_API}/dnszones/)"
    _debug _cn_zonelist "${_cn_zonelist}"

    if [ "$?" != "0" ]; then
      _err "something went wrong while getting the zone list"
      return 1
    fi

    if _contains "$_cn_zonelist" "\"name\":\"$h\"" >/dev/null; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain=$h
      return 0
    else
      _debug "Zonelist does not contain domain - iterating "
    fi
    p=$i
    i=$(_math "$i" + 1)

  done
  _err "Zonelist does not contain domain - exiting"
  return 1
}

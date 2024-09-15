
#!/usr/bin/env bash

# We highly recommend to create a new user in the Servercow CP to only grant access to the DNS API
# https://cp.servercow.de/client/contacts/add/

#SCOW_User="username"
#SCOW_Pass="pass"

dns_scow_add() {
  fulldomain=$1
  txtvalue=$2
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  _info "Using Servercow DNS API"

  if ! which dig > /dev/null; then
    _err "Cannot find dig (Debian and derivates: dnsutils; CentOS, Arch, Alpine: bind-tools)"
  fi

  if [[ -z "$SCOW_Pass" ]] || [[ -z "$SCOW_User" ]]; then
    SCOW_Pass=""
    SCOW_User=""
    _err "No Servercow login data provided."
    _err "Please create a new user with access to the DNS API."
    return 1
  fi

  if ! _get_root_domain "${fulldomain}"; then
    _err "Cannot determine root domain"
    return 1
  fi
  _info "Found zone ${_root_domain} for ${fulldomain}"

  if _scow_api POST; then
    _info "OK, added txt record to zone, please wait a few seconds..."
  else
    _err "Error, exiting."
    return 1
  fi
  return 0
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_scow_rm() {
  fulldomain=$1
  txtvalue=$2
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  _get_root_domain "${fulldomain}"
  if [[ -z ${_root_domain} ]]; then
    _err "Cannot determine root domain"
    return 1
  fi
  _info "Found zone ${_root_domain} for ${fulldomain}"
  if _scow_api DELETE; then
    _info "OK, removed txt record from zone."
  else
    _err "Error, exiting."
    return 1
  fi
  return 0
}

####################  Private functions below ##################################
_get_root_domain() {
  local domain=${1}
  until [[ ! -z $(dig ns ${domain} +short | grep -iE 'ns.+\.servercow\.de') ]]; do
    domain=${domain#*.}
    [ $(echo ${domain} | awk -F. '{print NF-1}') -lt 1 ] && return 1
  done
  _root_domain=${domain}
  return 0
}
_scow_api() {
  method=${1}
  if [[ ${method} == "POST" ]]; then
    api_return=$(curl -sX POST "https://api.servercow.de/dns/v1/domains/${_root_domain}" \
      -H "X-Auth-Username: ${SCOW_User}" \
      -H "X-Auth-Password: ${SCOW_Pass}" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"TXT\",\"name\":\"${fulldomain}\",\"content\":\"${txtvalue}\",\"ttl\":10}")
    echo ${api_return} | grep -qi '{"message":"ok"}'
    if [[ $? != 0 ]]; then
      _err "Post to API failed: ${api_return}"
      return 1
    fi
    _debug "API: ${api_return}"
  elif [[ ${method} == "DELETE" ]]; then
    api_return=$(curl -sX DELETE "https://api.servercow.de/dns/v1/domains/${_root_domain}" \
      -H "X-Auth-Username: ${SCOW_User}" \
      -H "X-Auth-Password: ${SCOW_Pass}" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"TXT\",\"name\":\"${fulldomain}\"}")
    echo ${api_return} | grep -qi '{"message":"ok"}'
    if [[ $? != 0 ]]; then
      _err "Delete request to API failed: ${api_return}"
      return 1
    fi
     _debug "API: ${api_return}"
  fi
  return 0
}

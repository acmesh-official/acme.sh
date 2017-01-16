#!/usr/bin/env bash

linode_cmd="/usr/bin/linode"

########  Public functions #####################

#Usage: dns_linode_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_linode_add() {
  fulldomain="${1}"
  txtvalue="${2}"

  _info "Using Linode"
  _debug "Calling: dns_linode_add() '${fulldomain}' '${txtvalue}'"

  domain=$(printf "%s" "${fulldomain}" | cut -d . -f 3-999)
  name=$(printf "%s" "${fulldomain}" | cut -d . -f 1-2)
  _debug name "${name}"
  _debug domain "${domain}"

  _Linode_CLI && _Linode_addTXT
}

#Usage: dns_linode_rm   _acme-challenge.www.domain.com
dns_linode_rm() {
  fulldomain="${1}"

  _info "Using Linode"
  _debug "Calling: dns_linode_rm() '${fulldomain}'"

  domain=$(printf "%s" "${fulldomain}" | cut -d . -f 3-999)
  name=$(printf "%s" "${fulldomain}" | cut -d . -f 1-2)
  _debug name "${name}"
  _debug domain "${domain}"

  _Linode_CLI && _Linode_rmTXT
}

####################  Private functions below ##################################

_Linode_CLI() {
  if [ ! -f "${linode_cmd}" ]; then
    _err "Please install the Linode CLI package and set it up accordingly before using this DNS API."
    return 1
  fi
}

_Linode_addTXT() {
  _debug "$linode_cmd domain record-update ${domain} TXT ${name} --target ${txtvalue}"
  $linode_cmd domain record-update ${domain} TXT ${name} --target ${txtvalue}

  if [ $? -ne 0 ]; then
    _debug "$linode_cmd domain record-create ${domain} TXT ${name} ${txtvalue}"
    $linode_cmd domain record-create ${domain} TXT ${name} ${txtvalue}
  fi
}

_Linode_rmTXT() {
  _debug "$linode_cmd domain record-delete ${domain} TXT ${name}"
  $linode_cmd domain record-delete ${domain} TXT ${name}
}

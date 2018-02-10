#!/usr/bin/env sh

########  Public functions #####################

#Usage: dns_nsupdate_l_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_nsupdate_l_add() {
  fulldomain=$1
  txtvalue=$2
  _info "adding ${fulldomain}. 60 in txt \"${txtvalue}\""
  nsupdate -l <<EOF
update add ${fulldomain}. 60 in txt "${txtvalue}"
send
EOF
  if [ $? -ne 0 ]; then
    _err "error updating domain"
    return 1
  fi

  return 0
}

#Usage: dns_nsupdate_l_rm   _acme-challenge.www.domain.com
dns_nsupdate_l_rm() {
  fulldomain=$1
  _info "removing ${fulldomain}. txt"
  nsupdate -l <<EOF
update delete ${fulldomain}. txt
send
EOF
  if [ $? -ne 0 ]; then
    _err "error updating domain"
    return 1
  fi

  return 0
}

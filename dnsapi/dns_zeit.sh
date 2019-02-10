#!/usr/bin/bash

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_zeit_add() {
  fulldomain=$1
  txtvalue=$2
  subdomain=$(echo $fulldomain | node -e "process.stdin.on('data',e=>console.log(e.toString().split('.').slice(0,-2).join('.')))")
  domain=$(echo $fulldomain | node -e "process.stdin.on('data',e=>console.log(e.toString().split('.').slice(-2).join('.').trim()))")
  now dns add $domain $subdomain TXT $txtvalue
}

#fulldomain txtvalue
dns_zeit_rm() {
  fulldomain=$1
  txtvalue=$2

}

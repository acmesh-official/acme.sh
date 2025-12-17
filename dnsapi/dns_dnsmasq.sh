#!/usr/bin/env sh

#This is useful when the server is running its own authzone on dnsmasq
#This file name is "dns_dnsmasq.sh"
#returns 0 means success, otherwise error.
#
#Author: rodvlopes
#Report Bugs here: https://github.com/acmesh-official/acme.sh
#
########  Public functions #####################

# Please Read this guide first: https://github.com/acmesh-official/acme.sh/wiki/DNS-API-Dev-Guide

#Usage: dns_dnsmasq_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dnsmasq_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using dnsmasq"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  _add_txt_to_dnsmasqconf "$fulldomain" "$txtvalue"
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_dnsmasq_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using dnsmasq"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  _rm_txt_from_dnsmasqconf "$fulldomain"
}

####################  Private functions below ##################################

_add_txt_to_dnsmasqconf() {
  fulldomain=$1
  txtvalue=$2
  echo "txt-record=$1,\"$2\"" >> /etc/dnsmasq.conf
  systemctl restart dnsmasq.service
}

_rm_txt_from_dnsmasqconf() {
  fulldomain=$1
  sed -i "/$fulldomain/d" /etc/dnsmasq.conf
  systemctl restart dnsmasq.service
}

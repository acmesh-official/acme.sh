#!/usr/bin/env sh

#Here is a sample custom api script.
#This file name is "dns_myapi.sh"
#So, here must be a method   dns_myapi_add()
#Which will be called by acme.sh to add the txt record to your api system.
#returns 0 means success, otherwise error.
#
#Author: Neilpang
#Report Bugs here: https://github.com/acmesh-official/acme.sh
#
########  Public functions #####################

# Please Read this guide first: https://github.com/acmesh-official/acme.sh/wiki/DNS-API-Dev-Guide

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_myapi_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using myapi"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  _err "Not implemented!"
  return 1
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_myapi_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using myapi"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
}

####################  Private functions below ##################################

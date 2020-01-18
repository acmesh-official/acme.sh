#!/usr/bin/env sh
#Author StefanAbl
#Usage specify a private keyfile to use with dynv6 'export KEY="path/to/keyfile"'
#if no keyfile is specified, you will be asked if you want to create one in /home/$USER/.ssh/dynv6 and /home/$USER/.ssh/dynv6.pub
########  Public functions #####################
# Please Read this guide first: https://github.com/Neilpang/acme.sh/wiki/DNS-API-Dev-Guide
#Usage: dns_myapi_add  _acme-challenge.www.domain.com  "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dynv6_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using dynv6 api"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  _get_keyfile
  _info "using keyfile $dynv6_keyfile"
  _get_domain "$fulldomain"
  _your_hosts="$(ssh -i "$dynv6_keyfile" api@dynv6.com hosts)"
  if ! _contains "$_your_hosts" "$_host"; then
    _debug "The host is $_host and the record $_record"
    _debug "Dynv6 returned $_your_hosts"
    _err "The host $_host does not exists on your dynv6 account"
    return 1
  fi
  _debug "found host on your account"
  returnval="$(ssh -i "$dynv6_keyfile" api@dynv6.com hosts \""$_host"\" records set \""$_record"\" txt data \""$txtvalue"\")"
  _debug "Dynv6 returend this after record was added: $returnval"
  if _contains "$returnval" "created"; then
    return 0
  elif _contains "$returnval" "updated"; then
    return 0
  else
    _err "Something went wrong! it does not seem like the record was added succesfully"
    return 1
  fi
  return 1
}
#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_dynv6_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using dynv6 api"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  _get_keyfile
  _info "using keyfile $dynv6_keyfile"
  _get_domain "$fulldomain"
  _your_hosts="$(ssh -i "$dynv6_keyfile" api@dynv6.com hosts)"
  if ! _contains "$_your_hosts" "$_host"; then
    _debug "The host is $_host and the record $_record"
    _debug "Dynv6 returned $_your_hosts"
    _err "The host $_host does not exists on your dynv6 account"
    return 1
  fi
  _debug "found host on your account"
  _info "$(ssh -i "$dynv6_keyfile" api@dynv6.com hosts "\"$_host\"" records del "\"$_record\"" txt)"
  return 0

}
#################### Private functions below ##################################
#Usage: No Input required
#returns
#dynv6_keyfile the path to the new keyfile that has been generated
_generate_new_key() {
  dynv6_keyfile="$(eval echo ~"$USER")/.ssh/dynv6"
  _info "Path to key file used: $dynv6_keyfile"
  if [ ! -f "$dynv6_keyfile" ] && [ ! -f "$dynv6_keyfile.pub" ]; then
    _debug "generating key in $dynv6_keyfile and $dynv6_keyfile.pub"
    ssh-keygen -f "$dynv6_keyfile" -t ssh-ed25519 -N ''
  else
    _err "There is already a file in $dynv6_keyfile or $dynv6_keyfile.pub"
    return 1
  fi
}
#Usage: _acme-challenge.www.example.dynv6.net
#returns
#_host= example.dynv6.net
#_record=_acme-challenge.www
#aborts if not a valid domain
_get_domain() {
  _full_domain="$1"
  _debug "getting domain for $_full_domain"
  if ! _contains "$_full_domain" 'dynv6.net' && ! _contains "$_full_domain" 'dns.army' && ! _contains "$_full_domain" 'dns.navy'; then
    _err "The hosts does not seem to be a dynv6 host"
    return 1
  fi
  _record="${_full_domain%.*}"
  _record="${_record%.*}"
  _record="${_record%.*}"
  _debug "The record we are ging to use is $_record"
  _host="$_full_domain"
  while [ "$(echo "$_host" | grep -o '\.' | wc -l)" != "2" ]; do
    _host="${_host#*.}"
  done
  _debug "And the host is $_host"
  return 0

}

# Usage: No input required
#returns
#dynv6_keyfile path to the key that will be used
_get_keyfile() {
  _debug "get keyfile method called"
  dynv6_keyfile="${dynv6_keyfile:-$(_readaccountconf_mutable dynv6_keyfile)}"
  _debug Your key is "$dynv6_keyfile"
  if [ -z "$dynv6_keyfile" ]; then
    if [ -z "$KEY" ]; then
      _err "You did not specify a key to use with dynv6"
      _info "Creating new dynv6 api key to add to dynv6.com"
      _generate_new_key
      _info "Please add this key to dynv6.com $(cat "$dynv6_keyfile.pub")"
      _info "Hit Enter to contiue"
      read -r _
      #save the credentials to the account conf file.
    else
      dynv6_keyfile="$KEY"
    fi
    _saveaccountconf_mutable dynv6_keyfile "$dynv6_keyfile"
  fi
}

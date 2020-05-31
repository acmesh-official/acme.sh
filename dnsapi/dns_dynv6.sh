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
  _your_hosts="$(ssh -i "$dynv6_keyfile" api@dynv6.com hosts)"
  
  if ! _get_domain "$fulldomain" "$_your_hosts"; then
  	_err "Host not found on your account"
  	return 1
  fi
#  if ! _contains "$_your_hosts" "$_host"; then
#    _debug "The host is $_host and the record $_record"
#    _debug "Dynv6 returned $_your_hosts"
#    _err "The host $_host does not exists on your dynv6 account"
#    return 1
#  fi
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
  _your_hosts="$(ssh -i "$dynv6_keyfile" api@dynv6.com hosts)"
  if ! _get_domain "$fulldomain" "$_your_hosts"; then
  	_err "Host not found on your account"
  	return 1
  fi
#  if ! _contains "$_your_hosts" "$_host"; then
#    _debug "The host is $_host and the record $_record"
#   _debug "Dynv6 returned $_your_hosts"
#    _err "The host $_host does not exists on your dynv6 account"
#    return 1
#  fi
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

#Usage: _acme-challenge.www.example.dynv6.net "$_your_hosts"
#where _your_hosts is the output of ssh -i ~/.ssh/dynv6.pub api@dynv6.com hosts
#returns
#_host= example.dynv6.net
#_record=_acme-challenge.www
#aborts if not a valid domain
_get_domain() {
  #_your_hosts="$(ssh -i ~/.ssh/dynv6.pub api@dynv6.com hosts)"
  _full_domain="$1"
  _your_hosts="$2"

  _your_hosts="$(echo "$_your_hosts" | awk '/\./ {print $1}')"
  for l in $_your_hosts; do
  	#echo "host: $l"
  	if test "${_full_domain#*$l}" != "$_full_domain"; then
  	  _record="${_full_domain%.$l}"
  	  _host=$l
  	  _debug "The host is $_host and the record $_record"
  	  return 0
  	fi
  done
  _err "Either their is no such host on your dnyv6 account or it cannot be accessed with this key"
  return 1
}

# Usage: No input required
#returns
#dynv6_keyfile path to the key that will be used
_get_keyfile() {
  _debug "get keyfile method called"
  dynv6_keyfile="${dynv6_keyfile:-$(_readaccountconf_mutable dynv6_keyfile)}"
  _debug "Your key is $dynv6_keyfile"
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

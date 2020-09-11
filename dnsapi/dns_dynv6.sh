#!/usr/bin/env sh
#Author StefanAbl
#Usage specify a private keyfile to use with dynv6 'export KEY="path/to/keyfile"'
#or use the HTTP REST API by by specifying a token 'export DYNV6_TOKEN="value"
#if no keyfile is specified, you will be asked if you want to create one in /home/$USER/.ssh/dynv6 and /home/$USER/.ssh/dynv6.pub

dynv6_api="https://dynv6.com/api/v2"
########  Public functions #####################
# Please Read this guide first: https://github.com/Neilpang/acme.sh/wiki/DNS-API-Dev-Guide
#Usage: dns_dynv6_add  _acme-challenge.www.domain.com  "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dynv6_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using dynv6 api"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  _get_authentication
  if [ "$dynv6_token" ]; then
    _dns_dynv6_add_http
    return $?
  else
    _info "using key file $dynv6_keyfile"
    _your_hosts="$(ssh -i "$dynv6_keyfile" api@dynv6.com hosts)"
    if ! _get_domain "$fulldomain" "$_your_hosts"; then
      _err "Host not found on your account"
      return 1
    fi
    _debug "found host on your account"
    returnval="$(ssh -i "$dynv6_keyfile" api@dynv6.com hosts \""$_host"\" records set \""$_record"\" txt data \""$txtvalue"\")"
    _debug "Dynv6 returned this after record was added: $returnval"
    if _contains "$returnval" "created"; then
      return 0
    elif _contains "$returnval" "updated"; then
      return 0
    else
      _err "Something went wrong! it does not seem like the record was added successfully"
      return 1
    fi
    return 1
  fi
  return 1
}
#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_dynv6_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using dynv6 API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  _get_authentication
  if [ "$dynv6_token" ]; then
    _dns_dynv6_rm_http
    return $?
  else
    _info "using key file $dynv6_keyfile"
    _your_hosts="$(ssh -i "$dynv6_keyfile" api@dynv6.com hosts)"
    if ! _get_domain "$fulldomain" "$_your_hosts"; then
      _err "Host not found on your account"
      return 1
    fi
    _debug "found host on your account"
    _info "$(ssh -i "$dynv6_keyfile" api@dynv6.com hosts "\"$_host\"" records del "\"$_record\"" txt)"
    return 0
  fi
}
#################### Private functions below ##################################
#Usage: No Input required
#returns
#dynv6_keyfile the path to the new key file that has been generated
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
_get_authentication() {
  dynv6_token="${DYNV6_TOKEN:-$(_readaccountconf_mutable dynv6_token)}"
  if [ "$dynv6_token" ]; then
    _debug "Found HTTP Token. Going to use the HTTP API and not the SSH API"
    if [ "$DYNV6_TOKEN" ]; then
      _saveaccountconf_mutable dynv6_token "$dynv6_token"
    fi
  else
    _debug "no HTTP token found. Looking for an SSH key"
    dynv6_keyfile="${dynv6_keyfile:-$(_readaccountconf_mutable dynv6_keyfile)}"
    _debug "Your key is $dynv6_keyfile"
    if [ -z "$dynv6_keyfile" ]; then
      if [ -z "$KEY" ]; then
        _err "You did not specify a key to use with dynv6"
        _info "Creating new dynv6 API key to add to dynv6.com"
        _generate_new_key
        _info "Please add this key to dynv6.com $(cat "$dynv6_keyfile.pub")"
        _info "Hit Enter to continue"
        read -r _
        #save the credentials to the account conf file.
      else
        dynv6_keyfile="$KEY"
      fi
      _saveaccountconf_mutable dynv6_keyfile "$dynv6_keyfile"
    fi
  fi
}

_dns_dynv6_add_http() {
  _debug "Got HTTP token form _get_authentication method. Going to use the HTTP API"
  if ! _get_zone_id "$fulldomain"; then
    _err "Could not find a matching zone for $fulldomain. Maybe your HTTP Token is not authorized to access the zone"
    return 1
  fi
  _get_zone_name "$_zone_id"
  record="${fulldomain%%.$_zone_name}"
  _set_record TXT "$record" "$txtvalue"
  if _contains "$response" "$txtvalue"; then
    _info "Successfully added record"
    return 0
  else
    _err "Something went wrong while adding the record"
    return 1
  fi
}

_dns_dynv6_rm_http() {
  _debug "Got HTTP token form _get_authentication method. Going to use the HTTP API"
  if ! _get_zone_id "$fulldomain"; then
    _err "Could not find a matching zone for $fulldomain. Maybe your HTTP Token is not authorized to access the zone"
    return 1
  fi
  _get_zone_name "$_zone_id"
  record="${fulldomain%%.$_zone_name}"
  _get_record_id "$_zone_id" "$record" "$txtvalue"
  _del_record "$_zone_id" "$_record_id"
  if [ -z "$response" ]; then
    _info "Successfully deleted record"
    return 0
  else
    _err "Something went wrong while deleting the record"
    return 1
  fi
}

#get the zoneid for a specifc record or zone
#usage: _get_zone_id §record
#where $record is the record to get the id for
#returns _zone_id the id of the zone
_get_zone_id() {
  record="$1"
  _debug "getting zone id for $record"
  _dynv6_rest GET zones

  zones="$(echo "$response" | tr '}' '\n' | tr ',' '\n' | grep name | sed 's/\[//g' | tr -d '{' | tr -d '"')"
  #echo $zones

  selected=""
  for z in $zones; do
    z="${z#name:}"
    _debug zone: "$z"
    if _contains "$record" "$z"; then
      _debug "$z found in $record"
      selected="$z"
    fi
  done
  if [ -z "$selected" ]; then
    _err "no zone found"
    return 1
  fi

  zone_id="$(echo "$response" | tr '}' '\n' | grep "$selected" | tr ',' '\n' | grep id | tr -d '"')"
  _zone_id="${zone_id#id:}"
  _debug "zone id: $_zone_id"
}

_get_zone_name() {
  _zone_id="$1"
  _dynv6_rest GET zones/"$_zone_id"
  _zone_name="$(echo "$response" | tr ',' '\n' | tr -d '{' | grep name | tr -d '"')"
  _zone_name="${_zone_name#name:}"
}

#usaage _get_record_id $zone_id $record
# where zone_id is thevalue returned by _get_zone_id
# and record ist in the form _acme.www for an fqdn of _acme.www.example.com
# returns _record_id
_get_record_id() {
  _zone_id="$1"
  record="$2"
  value="$3"
  _dynv6_rest GET "zones/$_zone_id/records"
  if ! _get_record_id_from_response "$response"; then
    _err "no such record $record found in zone $_zone_id"
    return 1
  fi
}

_get_record_id_from_response() {
  response="$1"
  _record_id="$(echo "$response" | tr '}' '\n' | grep "\"name\":\"$record\"" | grep "\"data\":\"$value\"" | tr ',' '\n' | grep id | tr -d '"' | tr -d 'id:')"
  #_record_id="${_record_id#id:}"
  if [ -z "$_record_id" ]; then
    _err "no such record: $record found in zone $_zone_id"
    return 1
  fi
  _debug "record id: $_record_id"
  return 0
}
#usage: _set_record TXT _acme_challenge.www longvalue 12345678
#zone id is optional can also be set as vairable bevor calling this method
_set_record() {
  type="$1"
  record="$2"
  value="$3"
  if [ "$4" ]; then
    _zone_id="$4"
  fi
  data="{\"name\": \"$record\", \"data\": \"$value\", \"type\": \"$type\"}"
  #data='{ "name": "acme.test.thorn.dynv6.net", "type": "A", "data": "192.168.0.1"}'
  echo "$data"
  #"{\"type\":\"TXT\",\"name\":\"$fulldomain\",\"content\":\"$txtvalue\",\"ttl\":120}"
  _dynv6_rest POST "zones/$_zone_id/records" "$data"
}
_del_record() {
  _zone_id=$1
  _record_id=$2
  _dynv6_rest DELETE zones/"$_zone_id"/records/"$_record_id"
}

_dynv6_rest() {
  m=$1    #method GET,POST,DELETE or PUT
  ep="$2" #the endpoint
  data="$3"
  _debug "$ep"

  token_trimmed=$(echo "$dynv6_token" | tr -d '"')

  export _H1="Authorization: Bearer $token_trimmed"
  export _H2="Content-Type: application/json"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$dynv6_api/$ep" "" "$m")"
  else
    response="$(_get "$dynv6_api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

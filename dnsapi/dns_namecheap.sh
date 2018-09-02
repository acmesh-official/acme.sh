#!/usr/bin/env sh

# Namecheap API
# https://www.namecheap.com/support/api/intro.aspx
#
# Requires Namecheap API key set in NAMECHEAP_API_KEY and NAMECHEAP_USERNAME set as environment variable
#
########  Public functions #####################

NAMECHEAP_API="https://api.sandbox.namecheap.com/xml.response"

#Usage: dns_namecheap_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_namecheap_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _namecheap_check_config; then
     _err "$error"
     return 1
  fi

  _namecheap_set_publicip

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  _debug domain "$_domain"
  _debug sub_domain "$_sub_domain"

  _set_namecheap_TXT "$_domain" "$_sub_domain" "$txtvalue"
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_namecheap_rm() {
  fulldomain=$1
  txtvalue=$2

  _namecheap_set_publicip

  if ! _namecheap_check_config; then
     _err "$error"
     return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  _debug domain "$_domain"
  _debug sub_domain "$_sub_domain"

  _del_namecheap_TXT "$_domain" "$_sub_domain" "$txtvalue"

}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1

  if ! _namecheap_post "namecheap.domains.getList"; then
     _err "$error"
     return 1
  fi

  i=2
  p=1

  while true; do
    
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _contains "$response" "$h"; then
      _debug "$h not found"
    else
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain="$h"
      return 0
    fi
    p="$i"
    i=$(_math "$i" + 1)
  done
  return 1
}

_namecheap_set_publicip() {
  _publicip="$(_get https://ifconfig.co/ip)"
}

_namecheap_post() {
  command=$1
  data="ApiUser=${NAMECHEAP_USERNAME}&ApiKey=${NAMECHEAP_API_KEY}&ClientIp=${_publicip}&UserName=${NAMECHEAP_USERNAME}&Command=${command}"
 
  response="$(_post "$data" "$NAMECHEAP_API" "" "POST")"
  _debug2 response "$response"

  if _contains "$response" "Status=\"ERROR\"" >/dev/null; then
    error=$(echo "$response" | _egrep_o ">.*<\\/Error>" | cut -d '<' -f 1 | tr -d '>')
    _err "error $error"
    return 1
  fi

  return 0
}


_namecheap_parse_host() {
  _host=$1

#HostID 	UniqueID of the host records
#Name 	The domain or subdomain for which host record is set
#Type 	The type of host record that is set
#Address 	The value that is set for the host record (IP address for A record, URL for URL redirects, etc.)
#MXPref 	MXPreference number
#TTL	TTL value for the host record

  _debug _host "$_host"

  _hostid=$(echo "$_host" | _egrep_o 'HostId=".*"' | cut -d '"' -f 2)
  _hostname=$(echo "$_host" | _egrep_o 'Name=".*"' | cut -d '"' -f 2)
  _hosttype=$(echo "$_host" | _egrep_o 'Type=".*"' | cut -d '"' -f 2)
  _hostaddress=$(echo "$_host" | _egrep_o 'Address=".*"' | cut -d '"' -f 2)
  _hostmxpref=$(echo "$_host" | _egrep_o 'MXPref=".*"' | cut -d '"' -f 2)
  _hostttl=$(echo "$_host" | _egrep_o 'TTL=".*"' | cut -d '"' -f 2)

  _debug hostid "$_hostid"
  _debug hostname "$_hostname"
  _debug hosttype "$_hosttype"
  _debug hostaddress "$_hostaddress"
  _debug hostmxpref "$_hostmxpref"
  _debug hostttl "$_hostttl"
 
}

_namecheap_check_config() {

  if [ -z "$NAMECHEAP_API_KEY" ]; then
    _err "No API key specified for Namecheap API."
    _err "Create your key and export it as NAMECHEAP_API_KEY"
    return 1
  fi

  if [ -z "$NAMECHEAP_USERNAME" ]; then
    _err "No username key specified for Namecheap API."
    _err "Create your key and export it as NAMECHEAP_USERNAME"
    return 1
  fi

  _saveaccountconf NAMECHEAP_API_KEY "$NAMECHEAP_API_KEY"
  _saveaccountconf NAMECHEAP_USERNAME "$NAMECHEAP_USERNAME"

  return 0
}

_set_namecheap_TXT() {
  subdomain=$2
  txt=$3
  tld=$(echo "$1" | cut -d '.' -f 2)
  sld=$(echo "$1" | cut -d '.' -f 1)
  request="namecheap.domains.dns.getHosts&SLD=$sld&TLD=$tld"

  if ! _namecheap_post "$request"; then
     _err "$error"
     return 1
  fi

  hosts=$(echo "$response" | _egrep_o '<host .+ />')
  _debug hosts "$hosts"

  if [ -z "$hosts" ]; then
     _error "Hosts not found"
     return 1
  fi

  i=0
  found=0

  while read host; do

    if _contains "$host" "<host"; then
      i=$(_math "$i" + 1)
      _namecheap_parse_host "$host"

      if [ "$_hosttype" = "TXT" ] && [ "$_hostname" = "$subdomain" ]; then
	hostrequest=$(printf '%s&HostName%d=%s&RecordType%d=%s&Address%d=%s&MXPref%d=%s&TTL%d=%s' "$hostrequest" $i "$_hostname" $i "$_hosttype" $i "$txt" $i "$_hostmxpref" $i "$_hostttl")
        found=1
      else
	hostrequest=$(printf '%s&HostName%d=%s&RecordType%d=%s&Address%d=%s&MXPref%d=%s&TTL%d=%s' "$hostrequest" $i "$_hostname" $i "$_hosttype" $i "$_hostaddress" $i "$_hostmxpref" $i "$_hostttl")
	_debug hostrequest "$hostrequest"
      fi 

    fi

  done <<EOT
$(echo -e "$hosts")
EOT

  if [ $found -eq 0 ]; then
    i=$(_math "$i" + 1)
    hostrequest=$(printf '%s&HostName%d=%s&RecordType%d=%s&Address%d=%s&MXPref%d=10&TTL%d=120' "$hostrequest" $i "$subdomain" $i "TXT" $i "$txt" $i $i)
    _debug "not found"
  fi

  _debug hostrequestfinal "$hostrequest"

  request="namecheap.domains.dns.setHosts&SLD=${sld}&TLD=${tld}${hostrequest}"

  if ! _namecheap_post "$request"; then
     _err "$error"
     return 1
  fi

  return 0
}


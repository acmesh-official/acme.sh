#!/usr/bin/env sh

# Namecheap API
# https://www.namecheap.com/support/api/intro.aspx
#
# Requires Namecheap API key set in
#NAMECHEAP_API_KEY,
#NAMECHEAP_USERNAME,
#NAMECHEAP_SOURCEIP
# Due to Namecheap's API limitation all the records of your domain will be read and re applied, make sure to have a backup of your records you could apply if any issue would arise.

########  Public functions #####################

NAMECHEAP_API="https://api.namecheap.com/xml.response"

#Usage: dns_namecheap_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_namecheap_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _namecheap_check_config; then
    _err "$error"
    return 1
  fi

  if ! _namecheap_set_publicip; then
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

  _set_namecheap_TXT "$_domain" "$_sub_domain" "$txtvalue"
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_namecheap_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _namecheap_set_publicip; then
    return 1
  fi

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
  fulldomain=$1

  if ! _get_root_by_getList "$fulldomain"; then
    _debug "Failed domain lookup via domains.getList api call. Trying domain lookup via domains.dns.getHosts api."
    # The above "getList" api will only return hosts *owned* by the calling user. However, if the calling
    # user is not the owner, but still has administrative rights, we must query the getHosts api directly.
    # See this comment and the official namecheap response: http://disq.us/p/1q6v9x9
    if ! _get_root_by_getHosts "$fulldomain"; then
      return 1
    fi
  fi

  return 0
}

_get_root_by_getList() {
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
    if ! _contains "$h" "\\."; then
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

_get_root_by_getHosts() {
  i=100
  p=99

  while [ $p -ne 0 ]; do

    h=$(printf "%s" "$1" | cut -d . -f $i-100)
    if [ -n "$h" ]; then
      if _contains "$h" "\\."; then
        _debug h "$h"
        if _namecheap_set_tld_sld "$h"; then
          _sub_domain=$(printf "%s" "$1" | cut -d . -f 1-$p)
          _domain="$h"
          return 0
        else
          _debug "$h not found"
        fi
      fi
    fi
    i="$p"
    p=$(_math "$p" - 1)
  done
  return 1
}

_namecheap_set_publicip() {

  if [ -z "$NAMECHEAP_SOURCEIP" ]; then
    _err "No Source IP specified for Namecheap API."
    _err "Use your public ip address or an url to retrieve it (e.g. https://ifconfig.co/ip) and export it as NAMECHEAP_SOURCEIP"
    return 1
  else
    _saveaccountconf NAMECHEAP_SOURCEIP "$NAMECHEAP_SOURCEIP"
    _debug sourceip "$NAMECHEAP_SOURCEIP"

    ip=$(echo "$NAMECHEAP_SOURCEIP" | _egrep_o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
    addr=$(echo "$NAMECHEAP_SOURCEIP" | _egrep_o '(http|https):\/\/.*')

    _debug2 ip "$ip"
    _debug2 addr "$addr"

    if [ -n "$ip" ]; then
      _publicip="$ip"
    elif [ -n "$addr" ]; then
      _publicip=$(_get "$addr")
    else
      _err "No Source IP specified for Namecheap API."
      _err "Use your public ip address or an url to retrieve it (e.g. https://ifconfig.co/ip) and export it as NAMECHEAP_SOURCEIP"
      return 1
    fi
  fi

  _debug publicip "$_publicip"

  return 0
}

_namecheap_post() {
  command=$1
  data="ApiUser=${NAMECHEAP_USERNAME}&ApiKey=${NAMECHEAP_API_KEY}&ClientIp=${_publicip}&UserName=${NAMECHEAP_USERNAME}&Command=${command}"
  _debug2 "_namecheap_post data" "$data"
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
  _debug _host "$_host"

  _hostid=$(echo "$_host" | _egrep_o ' HostId="[^"]*' | cut -d '"' -f 2)
  _hostname=$(echo "$_host" | _egrep_o ' Name="[^"]*' | cut -d '"' -f 2)
  _hosttype=$(echo "$_host" | _egrep_o ' Type="[^"]*' | cut -d '"' -f 2)
  _hostaddress=$(echo "$_host" | _egrep_o ' Address="[^"]*' | cut -d '"' -f 2 | _xml_decode)
  _hostmxpref=$(echo "$_host" | _egrep_o ' MXPref="[^"]*' | cut -d '"' -f 2)
  _hostttl=$(echo "$_host" | _egrep_o ' TTL="[^"]*' | cut -d '"' -f 2)

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

  if ! _namecheap_set_tld_sld "$1"; then
    return 1
  fi

  request="namecheap.domains.dns.getHosts&SLD=${_sld}&TLD=${_tld}"

  if ! _namecheap_post "$request"; then
    _err "$error"
    return 1
  fi

  hosts=$(echo "$response" | _egrep_o '<host[^>]*')
  _debug hosts "$hosts"

  if [ -z "$hosts" ]; then
    _error "Hosts not found"
    return 1
  fi

  _namecheap_reset_hostList

  while read -r host; do
    if _contains "$host" "<host"; then
      _namecheap_parse_host "$host"
      _debug2 _hostname "_hostname"
      _debug2 _hosttype "_hosttype"
      _debug2 _hostaddress "_hostaddress"
      _debug2 _hostmxpref "_hostmxpref"
      _hostaddress="$(printf "%s" "$_hostaddress" | _url_encode)"
      _debug2 "encoded _hostaddress" "_hostaddress"
      _namecheap_add_host "$_hostname" "$_hosttype" "$_hostaddress" "$_hostmxpref" "$_hostttl"
    fi
  done <<EOT
echo "$hosts"
EOT

  _namecheap_add_host "$subdomain" "TXT" "$txt" 10 120

  _debug hostrequestfinal "$_hostrequest"

  request="namecheap.domains.dns.setHosts&SLD=${_sld}&TLD=${_tld}${_hostrequest}"

  if ! _namecheap_post "$request"; then
    _err "$error"
    return 1
  fi

  return 0
}

_del_namecheap_TXT() {
  subdomain=$2
  txt=$3

  if ! _namecheap_set_tld_sld "$1"; then
    return 1
  fi

  request="namecheap.domains.dns.getHosts&SLD=${_sld}&TLD=${_tld}"

  if ! _namecheap_post "$request"; then
    _err "$error"
    return 1
  fi

  hosts=$(echo "$response" | _egrep_o '<host[^>]*')
  _debug hosts "$hosts"

  if [ -z "$hosts" ]; then
    _error "Hosts not found"
    return 1
  fi

  _namecheap_reset_hostList

  found=0

  while read -r host; do
    if _contains "$host" "<host"; then
      _namecheap_parse_host "$host"
      if [ "$_hosttype" = "TXT" ] && [ "$_hostname" = "$subdomain" ] && [ "$_hostaddress" = "$txt" ]; then
        _debug "TXT entry found"
        found=1
      else
        _hostaddress="$(printf "%s" "$_hostaddress" | _url_encode)"
        _namecheap_add_host "$_hostname" "$_hosttype" "$_hostaddress" "$_hostmxpref" "$_hostttl"
      fi
    fi
  done <<EOT
echo "$hosts"
EOT

  if [ $found -eq 0 ]; then
    _debug "TXT entry not found"
    return 0
  fi

  _debug hostrequestfinal "$_hostrequest"

  request="namecheap.domains.dns.setHosts&SLD=${_sld}&TLD=${_tld}${_hostrequest}"

  if ! _namecheap_post "$request"; then
    _err "$error"
    return 1
  fi

  return 0
}

_namecheap_reset_hostList() {
  _hostindex=0
  _hostrequest=""
}

#Usage: _namecheap_add_host HostName RecordType Address MxPref TTL
_namecheap_add_host() {
  _hostindex=$(_math "$_hostindex" + 1)
  _hostrequest=$(printf '%s&HostName%d=%s&RecordType%d=%s&Address%d=%s&MXPref%d=%d&TTL%d=%d' "$_hostrequest" "$_hostindex" "$1" "$_hostindex" "$2" "$_hostindex" "$3" "$_hostindex" "$4" "$_hostindex" "$5")
}

_namecheap_set_tld_sld() {
  domain=$1
  _tld=""
  _sld=""

  i=2

  while true; do

    _tld=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug tld "$_tld"

    if [ -z "$_tld" ]; then
      _debug "invalid tld"
      return 1
    fi

    j=$(_math "$i" - 1)

    _sld=$(printf "%s" "$domain" | cut -d . -f 1-"$j")
    _debug sld "$_sld"

    if [ -z "$_sld" ]; then
      _debug "invalid sld"
      return 1
    fi

    request="namecheap.domains.dns.getHosts&SLD=$_sld&TLD=$_tld"

    if ! _namecheap_post "$request"; then
      _debug "sld($_sld)/tld($_tld) not found"
    else
      _debug "sld($_sld)/tld($_tld) found"
      return 0
    fi

    i=$(_math "$i" + 1)

  done

}

_xml_decode() {
  sed 's/&quot;/"/g'
}

#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_netcup_info='netcup.eu
Domains: netcup.de netcup.net
Site: netcup.eu/
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_netcup
Options:
 NC_Apikey API Key
 NC_Apipw API Password
 NC_CID Customer Number
Author: linux-insideDE
'

NC_Apikey="${NC_Apikey:-$(_readaccountconf_mutable NC_Apikey)}"
NC_Apipw="${NC_Apipw:-$(_readaccountconf_mutable NC_Apipw)}"
NC_CID="${NC_CID:-$(_readaccountconf_mutable NC_CID)}"
end="https://ccp.netcup.net/run/webservice/servers/endpoint.php?JSON"
client=""

dns_netcup_add() {
  _debug NC_Apikey "$NC_Apikey"
  _login
  if [ "$NC_Apikey" = "" ] || [ "$NC_Apipw" = "" ] || [ "$NC_CID" = "" ]; then
    _err "No Credentials given"
    return 1
  fi
  _saveaccountconf_mutable NC_Apikey "$NC_Apikey"
  _saveaccountconf_mutable NC_Apipw "$NC_Apipw"
  _saveaccountconf_mutable NC_CID "$NC_CID"
  fulldomain=$1
  txtvalue=$2
  domain=""
  exit=$(echo "$fulldomain" | tr -dc '.' | wc -c)
  exit=$(_math "$exit" + 1)
  i=$exit
  _nc_last=$(_nc_lastlevel "$i")
  _nc_found=""

  while
    [ "$exit" -ge "$_nc_last" ]
  do
    tmp=$(echo "$fulldomain" | cut -d'.' -f"$exit")
    if [ "$(_math "$i" - "$exit")" -eq 0 ]; then
      domain="$tmp"
    else
      domain="$tmp.$domain"
    fi
    if [ "$(_math "$i" - "$exit")" -ge 1 ]; then
      msg=$(_post "{\"action\": \"updateDnsRecords\", \"param\": {\"apikey\": \"$NC_Apikey\", \"apisessionid\": \"$sid\", \"customernumber\": \"$NC_CID\",\"clientrequestid\": \"$client\" , \"domainname\": \"$domain\", \"dnsrecordset\": { \"dnsrecords\": [ {\"id\": \"\", \"hostname\": \"$fulldomain.\", \"type\": \"TXT\", \"priority\": \"\", \"destination\": \"$txtvalue\", \"deleterecord\": \"false\", \"state\": \"yes\"} ]}}}" "$end" "" "POST")
      _debug "$msg"
      if [ "$(_getfield "$msg" "5" | sed 's/"statuscode"://g')" != 5028 ]; then
        if [ "$(_getfield "$msg" "4" | sed s/\"status\":\"//g | sed s/\"//g)" != "success" ]; then
          _err "$msg"
          return 1
        else
          _nc_found=1
          break
        fi
      fi
    fi
    exit=$(_math "$exit" - 1)
  done
  if [ -z "$_nc_found" ]; then
    _err "$msg"
    _nc_nozone "$fulldomain"
    return 1
  fi
  logout
}

dns_netcup_rm() {
  _login
  fulldomain=$1
  txtvalue=$2

  domain=""
  exit=$(echo "$fulldomain" | tr -dc '.' | wc -c)
  exit=$(_math "$exit" + 1)
  i=$exit
  rec=""
  _nc_last=$(_nc_lastlevel "$i")
  _nc_found=""

  while
    [ "$exit" -ge "$_nc_last" ]
  do
    tmp=$(echo "$fulldomain" | cut -d'.' -f"$exit")
    if [ "$(_math "$i" - "$exit")" -eq 0 ]; then
      domain="$tmp"
    else
      domain="$tmp.$domain"
    fi
    if [ "$(_math "$i" - "$exit")" -ge 1 ]; then
      msg=$(_post "{\"action\": \"infoDnsRecords\", \"param\": {\"apikey\": \"$NC_Apikey\", \"apisessionid\": \"$sid\", \"customernumber\": \"$NC_CID\", \"domainname\": \"$domain\"}}" "$end" "" "POST")
      rec=$(echo "$msg" | sed 's/\[//g' | sed 's/\]//g' | sed 's/{\"serverrequestid\".*\"dnsrecords\"://g' | sed 's/},{/};{/g' | sed 's/{//g' | sed 's/}//g')
      _debug "$msg"
      if [ "$(_getfield "$msg" "5" | sed 's/"statuscode"://g')" != 5028 ]; then
        if [ "$(_getfield "$msg" "4" | sed s/\"status\":\"//g | sed s/\"//g)" != "success" ]; then
          _err "$msg"
          return 1
        else
          _nc_found=1
          break
        fi
      fi
    fi
    exit=$(_math "$exit" - 1)
  done
  if [ -z "$_nc_found" ]; then
    _err "$msg"
    _nc_nozone "$fulldomain"
    return 1
  fi

  ida=0000
  idv=0001
  ids=0000000000
  i=1
  while
    [ "$i" -ne 0 ]
  do
    specrec=$(_getfield "$rec" "$i" ";")
    idv="$ida"
    ida=$(_getfield "$specrec" "1" "," | sed 's/\"id\":\"//g' | sed 's/\"//g')
    txtv=$(_getfield "$specrec" "5" "," | sed 's/\"destination\":\"//g' | sed 's/\"//g')
    i=$(_math "$i" + 1)
    if [ "$txtvalue" = "$txtv" ]; then
      i=0
      ids="$ida"
    fi
    if [ "$ida" = "$idv" ]; then
      i=0
    fi
  done
  msg=$(_post "{\"action\": \"updateDnsRecords\", \"param\": {\"apikey\": \"$NC_Apikey\", \"apisessionid\": \"$sid\", \"customernumber\": \"$NC_CID\",\"clientrequestid\": \"$client\" , \"domainname\": \"$domain\", \"dnsrecordset\": { \"dnsrecords\": [ {\"id\": \"$ids\", \"hostname\": \"$fulldomain.\", \"type\": \"TXT\", \"priority\": \"\", \"destination\": \"$txtvalue\", \"deleterecord\": \"TRUE\", \"state\": \"yes\"} ]}}}" "$end" "" "POST")
  _debug "$msg"
  if [ "$(_getfield "$msg" "4" | sed s/\"status\":\"//g | sed s/\"//g)" != "success" ]; then
    _err "$msg"
    return 1
  fi
  logout
}

# The zone is looked up by walking the challenge name from the right, one
# label at a time. The leftmost label is the challenge prefix, so the full
# name itself can never be a zone: asking netcup for it only returns 4013
# "Validation Error", which would then mask the real 5028 "zone could not be
# found". Stop one label short, unless the name is too short to have a
# challenge prefix at all (manual invocation).
# levels
_nc_lastlevel() {
  if [ "$1" -ge 3 ]; then
    echo 2
  else
    echo 1
  fi
}

# fulldomain
_nc_nozone() {
  _err "No DNS zone for $1 was found at netcup."
  _err "Check that the domain belongs to the account of the configured NC_CID and that its DNS is hosted at netcup."
}

_login() {
  tmp=$(_post "{\"action\": \"login\", \"param\": {\"apikey\": \"$NC_Apikey\", \"apipassword\": \"$NC_Apipw\", \"customernumber\": \"$NC_CID\"}}" "$end" "" "POST")
  sid=$(echo "$tmp" | tr '{}' '\n' | grep apisessionid | cut -d '"' -f 4)
  _debug "$tmp"
  if [ "$(_getfield "$tmp" "4" | sed s/\"status\":\"//g | sed s/\"//g)" != "success" ]; then
    _err "$tmp"
    return 1
  fi
}
logout() {
  tmp=$(_post "{\"action\": \"logout\", \"param\": {\"apikey\": \"$NC_Apikey\", \"apisessionid\": \"$sid\", \"customernumber\": \"$NC_CID\"}}" "$end" "" "POST")
  _debug "$tmp"
  if [ "$(_getfield "$tmp" "4" | sed s/\"status\":\"//g | sed s/\"//g)" != "success" ]; then
    _err "$tmp"
    return 1
  fi
}

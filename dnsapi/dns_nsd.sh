#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_nsd_info='NLnetLabs NSD Server
Site: github.com/NLnetLabs/nsd
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#nsd
Options:
 Nsd_ZoneFile Zone File path. E.g. "/etc/nsd/zones/example.com.zone"
 Nsd_Command Command. E.g. "sudo nsd-control reload"
Issues: github.com/acmesh-official/acme.sh/issues/2245
'

# args: zonefile
_local_nsd_get_serial()
{
    local _zone_file="$1"
    cat "$_zone_file" | \
	sed -n '/IN[ \t]*SOA.*/,/[)]/p' | \
	sed 's/\([^;]\);\(.*\)/\1/g' | \
	sed -z 's/\n//g' | \
	sed 's/\([^(]*\)[(]\([^)]*\)[)]/\2/g' | \
	sed 's/\([ \t]*\)\([0-9]*\)\(.*\)/\2/g'
}

# args: fulldomain txtvalue
dns_nsd_add() {
  fulldomain=$1
  txtvalue=$2
  ttlvalue=300

  Nsd_ZoneFile="${Nsd_ZoneFile:-$(_readdomainconf Nsd_ZoneFile)}"
  Nsd_Command="${Nsd_Command:-$(_readdomainconf Nsd_Command)}"

  # Arg checks
  if [ -z "$Nsd_ZoneFile" ] || [ -z "$Nsd_Command" ]; then
    Nsd_ZoneFile=""
    Nsd_Command=""
    _err "Specify ENV vars Nsd_ZoneFile and Nsd_Command"
    return 1
  fi

  if [ ! -f "$Nsd_ZoneFile" ]; then
    Nsd_ZoneFile=""
    Nsd_Command=""
    _err "No such file: $Nsd_ZoneFile"
    return 1
  fi

  _savedomainconf Nsd_ZoneFile "$Nsd_ZoneFile"
  _savedomainconf Nsd_Command "$Nsd_Command"

  echo "$fulldomain. $ttlvalue IN TXT \"$txtvalue\"" >>"$Nsd_ZoneFile"

  # Updating serial. The idea is that we'll parse out the old serial first,
  # generate a new one by incrementing, then sed-replace the old by the new one.
  local zone_serial=$(_local_nsd_get_serial "$Nsd_ZoneFile")
  local zone_serial_next=$[$zone_serial+1]
  local tmp_zonefile=$(mktemp)
  cat "$Nsd_ZoneFile" | sed "s/$zone_serial/$zone_serial_next/" > "$tmp_zonefile"
  mv "$tmp_zonefile" "$Nsd_ZoneFile"
  rm -rf "$tmp_zonefile"
  
  _info "Added TXT record for $fulldomain"
  _debug "Running $Nsd_Command"
  if eval "$Nsd_Command"; then
    _info "Successfully updated the zone"
    return 0
  else
    _err "Problem updating the zone"
    return 1
  fi
}

# args: fulldomain txtvalue
dns_nsd_rm() {
  fulldomain=$1
  txtvalue=$2
  ttlvalue=300

  Nsd_ZoneFile="${Nsd_ZoneFile:-$(_readdomainconf Nsd_ZoneFile)}"
  Nsd_Command="${Nsd_Command:-$(_readdomainconf Nsd_Command)}"

  _sed_i "/$fulldomain. $ttlvalue IN TXT \"$txtvalue\"/d" "$Nsd_ZoneFile"
  _info "Removed TXT record for $fulldomain"
  _debug "Running $Nsd_Command"
  if eval "$Nsd_Command"; then
    _info "Successfully reloaded NSD "
    return 0
  else
    _err "Problem reloading NSD"
    return 1
  fi
}

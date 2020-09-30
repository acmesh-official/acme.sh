#!/usr/bin/env sh

#Nsd_ZoneFile="/etc/nsd/zones/example.com.zone"
#Nsd_Command="sudo nsd-control reload"

########  Public functions #####################

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

  _increment_serial || return 1
  echo "$fulldomain. $ttlvalue IN TXT \"$txtvalue\"" >>"$Nsd_ZoneFile"
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

  _increment_serial || return 1
  sed -i "/$fulldomain. $ttlvalue IN TXT \"$txtvalue\"/d" "$Nsd_ZoneFile"
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

####################  Private functions below ##################################

_increment_serial() {
  tmpfile=$(mktemp) || return 1
  awk '$3 == "SOA" {
    if ($6 == "(") {
      print "Multi-line SOA record not supported yet";
      exit 1
    } else
      $6++
  }
  { print }' "$Nsd_ZoneFile" >"$tmpfile" || return 1
  awk '{print}' "$tmpfile" >"$Nsd_ZoneFile"
  rm -f "$tmpfile"
}

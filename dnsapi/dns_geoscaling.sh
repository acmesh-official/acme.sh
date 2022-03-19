#!/usr/bin/env sh

########################################################################
# Geoscaling hook script for acme.sh
#
# Environment variables:
#
#  - $GEOSCALING_Username  (your Geoscaling username - this is usually NOT an amail address)
#  - $GEOSCALING_Password  (your Geoscaling password)

#-- dns_geoscaling_add() - Add TXT record --------------------------------------
# Usage: dns_geoscaling_add _acme-challenge.subdomain.domain.com "XyZ123..."

dns_geoscaling_add() {
  full_domain=$1
  txt_value=$2
  _info "Using DNS-01 Geoscaling DNS2 hook"

  GEOSCALING_Username="${GEOSCALING_Username:-$(_readaccountconf_mutable GEOSCALING_Username)}"
  GEOSCALING_Password="${GEOSCALING_Password:-$(_readaccountconf_mutable GEOSCALING_Password)}"
  if [ -z "$GEOSCALING_Username" ] || [ -z "$GEOSCALING_Password" ]; then
    GEOSCALING_Username=
    GEOSCALING_Password=
    _err "No auth details provided. Please set user credentials using the \$GEOSCALING_Username and \$GEOSCALING_Password environment variables."
    return 1
  fi
  _saveaccountconf_mutable GEOSCALING_Username "${GEOSCALING_Username}"
  _saveaccountconf_mutable GEOSCALING_Password "${GEOSCALING_Password}"

  # Fills in the $zone_id and $zone_name
  find_zone "${full_domain}" || return 1
  _debug "Zone id '${zone_id}' will be used."

  # We're logged in here

  # we should add ${full_domain} minus the trailing ${zone_name}

  prefix=$(echo "${full_domain}" | sed "s|\\.${zone_name}\$||")

  body="id=${zone_id}&name=${prefix}&type=TXT&content=${txt_value}&ttl=300&prio=0"

  do_post "$body" "https://www.geoscaling.com/dns2/ajax/add_record.php"
  exit_code="$?"
  if [ "${exit_code}" -eq 0 ]; then
    _info "TXT record added successfully."
  else
    _err "Couldn't add the TXT record."
  fi
  do_logout
  return "${exit_code}"
}

#-- dns_geoscaling_rm() - Remove TXT record ------------------------------------
# Usage: dns_geoscaling_rm _acme-challenge.subdomain.domain.com "XyZ123..."

dns_geoscaling_rm() {
  full_domain=$1
  txt_value=$2
  _info "Cleaning up after DNS-01 Geoscaling DNS2 hook"

  # fills in the $zone_id
  find_zone "${full_domain}" || return 1
  _debug "Zone id '${zone_id}' will be used."

  # Here we're logged in
  # Find the record id to clean

  # get the domain
  response=$(do_get "https://www.geoscaling.com/dns2/index.php?module=domain&id=${zone_id}")
  _debug2 "response" "$response"

  table="$(echo "${response}" | tr -d '\n' | sed 's|.*<div class="box"><div class="boxtitle">Basic Records</div><div class="boxtext"><table|<table|; s|</table>.*|</table>|')"
  _debug2 table "${table}"
  names=$(echo "${table}" | _egrep_o 'id="[0-9]+\.name">[^<]*</td>' | sed 's|</td>||; s|.*>||')
  ids=$(echo "${table}" | _egrep_o 'id="[0-9]+\.name">[^<]*</td>' | sed 's|\.name">.*||; s|id="||')
  types=$(echo "${table}" | _egrep_o 'id="[0-9]+\.type">[^<]*</td>' | sed 's|</td>||; s|.*>||')
  values=$(echo "${table}" | _egrep_o 'id="[0-9]+\.content">[^<]*</td>' | sed 's|</td>||; s|.*>||')

  _debug2 names "${names}"
  _debug2 ids "${ids}"
  _debug2 types "${types}"
  _debug2 values "${values}"

  # look for line whose name is ${full_domain}, whose type is TXT, and whose value is ${txt_value}
  line_num="$(echo "${values}" | grep -F -n -- "${txt_value}" | _head_n 1 | cut -d ':' -f 1)"
  _debug2 line_num "${line_num}"
  found_id=
  if [ -n "$line_num" ]; then
    type=$(echo "${types}" | sed -n "${line_num}p")
    name=$(echo "${names}" | sed -n "${line_num}p")
    id=$(echo "${ids}" | sed -n "${line_num}p")

    _debug2 type "$type"
    _debug2 name "$name"
    _debug2 id "$id"
    _debug2 full_domain "$full_domain"

    if [ "${type}" = "TXT" ] && [ "${name}" = "${full_domain}" ]; then
      found_id=${id}
    fi
  fi

  if [ "${found_id}" = "" ]; then
    _err "Can not find record id."
    return 0
  fi

  # Remove the record
  body="id=${zone_id}&record_id=${found_id}"
  response=$(do_post "$body" "https://www.geoscaling.com/dns2/ajax/delete_record.php")
  exit_code="$?"
  if [ "$exit_code" -eq 0 ]; then
    _info "Record removed successfully."
  else
    _err "Could not clean (remove) up the record. Please go to Geoscaling administration interface and clean it by hand."
  fi
  do_logout
  return "${exit_code}"
}

########################## PRIVATE FUNCTIONS ###########################

do_get() {
  _url=$1
  export _H1="Cookie: $geoscaling_phpsessid_cookie"
  _get "${_url}"
}

do_post() {
  _body=$1
  _url=$2
  export _H1="Cookie: $geoscaling_phpsessid_cookie"
  _post "${_body}" "${_url}"
}

do_login() {

  _info "Logging in..."

  username_encoded="$(printf "%s" "${GEOSCALING_Username}" | _url_encode)"
  password_encoded="$(printf "%s" "${GEOSCALING_Password}" | _url_encode)"
  body="username=${username_encoded}&password=${password_encoded}"

  response=$(_post "$body" "https://www.geoscaling.com/dns2/index.php?module=auth")
  _debug2 response "${response}"

  #retcode=$(grep '^HTTP[^ ]*' "${HTTP_HEADER}" | _head_n 1 | _egrep_o '[0-9]+$')
  retcode=$(grep '^HTTP[^ ]*' "${HTTP_HEADER}" | _head_n 1 | cut -d ' ' -f 2)

  if [ "$retcode" != "302" ]; then
    _err "Geoscaling login failed for user ${GEOSCALING_Username}. Check ${HTTP_HEADER} file"
    return 1
  fi

  geoscaling_phpsessid_cookie="$(grep -i '^set-cookie:' "${HTTP_HEADER}" | _egrep_o 'PHPSESSID=[^;]*;' | tr -d ';')"
  return 0

}

do_logout() {
  _info "Logging out."
  response="$(do_get "https://www.geoscaling.com/dns2/index.php?module=auth")"
  _debug2 response "$response"
  return 0
}

find_zone() {
  domain="$1"

  # do login
  do_login || return 1

  # get zones
  response="$(do_get "https://www.geoscaling.com/dns2/index.php?module=domains")"

  table="$(echo "${response}" | tr -d '\n' | sed 's|.*<div class="box"><div class="boxtitle">Your domains</div><div class="boxtext"><table|<table|; s|</table>.*|</table>|')"
  _debug2 table "${table}"
  zone_names="$(echo "${table}" | _egrep_o '<b>[^<]*</b>' | sed 's|<b>||;s|</b>||')"
  _debug2 _matches "${zone_names}"
  # Zone names and zone IDs are in same order
  zone_ids=$(echo "${table}" | _egrep_o '<a href=.index\.php\?module=domain&id=[0-9]+. onclick="javascript:show_loader\(\);">' | sed 's|.*id=||;s|. .*||')

  _debug2 "These are the zones on this Geoscaling account:"
  _debug2 "zone_names" "${zone_names}"
  _debug2 "And these are their respective IDs:"
  _debug2 "zone_ids" "${zone_ids}"
  if [ -z "${zone_names}" ] || [ -z "${zone_ids}" ]; then
    _err "Can not get zone names or IDs."
    return 1
  fi
  # Walk through all possible zone names
  strip_counter=1
  while true; do
    attempted_zone=$(echo "${domain}" | cut -d . -f ${strip_counter}-)

    # All possible zone names have been tried
    if [ -z "${attempted_zone}" ]; then
      _err "No zone for domain '${domain}' found."
      return 1
    fi

    _debug "Looking for zone '${attempted_zone}'"

    line_num="$(echo "${zone_names}" | grep -n "^${attempted_zone}\$" | _head_n 1 | cut -d : -f 1)"
    _debug2 line_num "${line_num}"
    if [ "$line_num" ]; then
      zone_id=$(echo "${zone_ids}" | sed -n "${line_num}p")
      zone_name=$(echo "${zone_names}" | sed -n "${line_num}p")
      if [ -z "${zone_id}" ]; then
        _err "Can not find zone id."
        return 1
      fi
      _debug "Found relevant zone '${attempted_zone}' with id '${zone_id}' - will be used for domain '${domain}'."
      return 0
    fi

    _debug "Zone '${attempted_zone}' doesn't exist, let's try a less specific zone."
    strip_counter=$(_math "${strip_counter}" + 1)
  done
}
# vim: et:ts=2:sw=2:

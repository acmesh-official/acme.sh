#! /usr/bin/env sh
#######################################################
# GeoScaling DNS2 hook script for acme.sh
#
# Environment variables:
#
#  - $GEOS_Username  (your geoscaling.com username)
#  - $GEOS_Password  (your geoscaling.com password)
#
# Author: Jinhill
# GEOS DNS: https://www.geoscaling.com
# Git repo: https://github.com/jinhill/acme.sh
#######################################################
COOKIE_FILE="/tmp/.geos.cookie"
#Add cookie to request
export _CURL="curl -s -c ${COOKIE_FILE} -b ${COOKIE_FILE}"
SESSION_TIMEOUT=300
log(){
	echo "$@" 1>&2
}

#$1:url
url_encode() {
	echo "$1" | awk -v ORS="" '{ gsub(/./,"&\n") ; print }' | while read -r l;
	do
		case "$l" in
	    [-_.~a-zA-Z0-9] ) printf '%s' "$l" ;;
	    "" ) printf '%%20' ;;
	    * )  printf '%%%02X' "'$l"
	  esac
	done
}

#$1:string,$2:char, if $2 not set return array len,$ret:count
count() {
	if [ -n "$2" ];then
		echo "$1" | awk -F"$2" '{print NF-1}'
	else
		echo "$1" | wc -w
	fi
}

#$1:seesion mode,$2:username,$3:password
login() {
  if [ -n "$1" ] && [ "$1" = "1" ] && [ -f "${COOKIE_FILE}" ];then
    c_t=$(date -r "${COOKIE_FILE}"  "+%s")
    now=$(date "+%s")
    s_t=$(( now - c_t ))
    if [ ${s_t} -lt ${SESSION_TIMEOUT} ];then
    	return 0
    fi
  fi

  GEOS_Username="${GEOS_Username:-$(_readaccountconf_mutable GEOS_Username)}"
  GEOS_Password="${GEOS_Password:-$(_readaccountconf_mutable GEOS_Password)}"
  if [ -z "${GEOS_Username}" ] || [ -z "${GEOS_Password}" ]; then
    GEOS_Username=
    GEOS_Password=
    _err "No auth details provided. Please set user credentials using the \$GEOS_Username and \$GEOS_Password environment variables."
    return 1
  fi
  _saveaccountconf_mutable GEOS_Username "${GEOS_Username}"
  _saveaccountconf_mutable GEOS_Password "${GEOS_Password}"
  enc_username=$(url_encode "${GEOS_Username}")
  enc_password=$(url_encode "${GEOS_Password}")
  body="username=${enc_username}&password=${enc_password}"
  http_code=$($_CURL -X POST -d "$body" -o /dev/null -w "%{http_code}" "https://www.geoscaling.com/dns2/index.php?module=auth")

  if [ "${http_code}" = "302" ]; then
    return 0
  fi
  _err "geoscaling login failed for user ${GEOS_Username} bad RC from post"
  return 1
}

#$1:full domain name,_acme-challenge.www.domain.com
#ret:
# sub_domain=_acme-challenge.www
# zone_id=xxxxxx
get_zone() {
  resp=$($_CURL "https://www.geoscaling.com/dns2/index.php?module=domains")
	table=$(echo "${resp}" | grep -oE "<table[^>]+ class=\"threecolumns\">.*</table>")
  items=$(echo "${table}" | grep -oE '<a [^>]+><b>[^>]+>')
  i=1
  c=$(count "$1" ".")
  while [ $i -le $c ]; do
    d=$(echo "$1" | cut -d . -f $i-)
    if [ -z "$d" ]; then
      return 1
    fi
    zone_id=$(echo "${items}" | grep -oE "id=[0-9]*.*$d" | cut -d "=" -f 2 | cut -d "'" -f 1)
    if [ -n "${zone_id}" ]; then
      sub_domain=$(echo "$1" | sed "s/.$d//")
      return 0
    fi
    i=$(( i + 1 ))
  done
  return 1
}

#$1:domain id,$2:dns fullname
get_record_id() {
  resp=$($_CURL "https://www.geoscaling.com/dns2/index.php?module=domain&id=$1")
	ids=$(echo "${resp}" | tr -d "\n" | grep -oE "<table id='records_table'.*</a></td></tr></table>" | grep -oE "id=\"[0-9]*.name\">$2" | cut -d '"' -f 2 | cut -d '.' -f 1)
  if [ -z "${ids}" ]; then
    _err "DNS record $2 not found."
    return 1
  fi
  echo "${ids}"
  return 0
}

########################## PUBLIC FUNCTIONS ###########################

# Usage: dns_geos_add _acme-challenge.subdomain.domain.com "XyZ123..."
dns_geos_add() {
  full_domain=$1
  value=$2
  type=$3
  [ -n "${type}" ] || type="TXT"
  _info "Using GeoScaling DNS2 hook"
  login 1 || return 1
  get_zone "${full_domain}" || return 1

  body="id=${zone_id}&name=${sub_domain}&type=${type}&content=${value}&ttl=300&prio=0"
  resp=$($_CURL -X POST -d "$body" "https://www.geoscaling.com/dns2/ajax/add_record.php")
  if _contains "${resp}" '"code":"OK"'; then
    _info "${type} record added successfully."
  else
    _err "Couldn't add the ${type} record."
    return 1
  fi
  return 0
}

# Usage: dns_geos_rm _acme-challenge.subdomain.domain.com "XyZ123..."
dns_geos_rm() {
  full_domain=$1
  value=$2
  _info "Cleaning up after GeoScaling DNS2 hook"
  login 1 || return 1
  get_zone "${full_domain}" || return 1
  log "zone id \"${zone_id}\" will be used."

  # Find the record id to clean
  subdomain_id=$(get_record_id "${zone_id}" "${full_domain}") || return 1
  body="id=${zone_id}&record_id=${subdomain_id}"
  resp=$($_CURL -X POST -d "$body" "https://www.geoscaling.com/dns2/ajax/delete_record.php")
  if _contains "${resp}" '"code":"OK"'; then
    _info "Record removed successfully."
  else
    _err "Could not clean (remove) up the record. Please go to https://www.geoscaling.com and clean it by hand."
    return 1
  fi
  return 0
}

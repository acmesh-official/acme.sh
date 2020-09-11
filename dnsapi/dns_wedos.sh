#!/usr/bin/env sh

# This script has been created at June 2020, based on knowledge base of wedos.com provider.
# It is intended to allow DNS-01 challenges for acme.sh using wedos's WAPI using XML.

# Author Michal Tuma <mxtuma@gmail.com>
# For issues send me an email

WEDOS_WAPI_ENDPOINT="https://api.wedos.com/wapi/xml"
TESTING_STAGE=

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_wedos_add() {
  fulldomain=$1
  txtvalue=$2

  WEDOS_Username="${WEDOS_Username:-$(_readaccountconf_mutable WEDOS_Username)}"
  WEDOS_Wapipass="${WEDOS_Wapipass:-$(_readaccountconf_mutable WEDOS_Wapipass)}"
  WEDOS_Authtoken="${WEDOS_Authtoken:-$(_readaccountconf_mutable WEDOS_Authtoken)}"

  if [ "${WEDOS_Authtoken}" ]; then
    _debug "WEDOS Authtoken was already saved, using saved one"
    _saveaccountconf_mutable WEDOS_Authtoken "${WEDOS_Authtoken}"
  else
    if [ -z "${WEDOS_Username}" ] || [ -z "${WEDOS_Wapipass}" ]; then
      WEDOS_Username=""
      WEDOS_Wapipass=""
      _err "You didn't specify a WEDOS's username and wapi key yet."
      _err "Please type: export WEDOS_Username=<your user name to login to wedos web account>"
      _err "And: export WEDOS_Wapipass=<your WAPI passwords you setup using wedos web pages>"
      _err "After you export those variables, run the script again, the values will be saved for future"
      return 1
    fi

    #build WEDOS_Authtoken
    _debug "WEDOS Authtoken were not saved yet, building"
    WEDOS_Authtoken=$(printf '%s' "${WEDOS_Wapipass}" | sha1sum | head -c 40)
    _debug "WEDOS_Authtoken step 1, WAPI PASS sha1 sum: '${WEDOS_Authtoken}'"
    WEDOS_Authtoken="${WEDOS_Username}${WEDOS_Authtoken}"
    _debug "WEDOS_Authtoken step 2, username concat with token without hours: '${WEDOS_Authtoken}'"

    #save details

    _saveaccountconf_mutable WEDOS_Username "${WEDOS_Username}"
    _saveaccountconf_mutable WEDOS_Wapipass "${WEDOS_Wapipass}"
    _saveaccountconf_mutable WEDOS_Authtoken "${WEDOS_Authtoken}"
  fi

  if ! _get_root "${fulldomain}"; then
    _err "WEDOS Account do not contain primary domain to fullfill add of ${fulldomain}!"
    return 1
  fi

  _debug _sub_domain "${_sub_domain}"
  _debug _domain "${_domain}"

  if _wapi_row_add "${_domain}" "${_sub_domain}" "${txtvalue}" "300"; then
    _info "WEDOS WAPI: dns record added and dns changes were commited"
    return 0
  else
    _err "FAILED TO ADD DNS RECORD OR COMMIT DNS CHANGES"
    return 1
  fi
}

#fulldomain txtvalue
dns_wedos_rm() {
  fulldomain=$1
  txtvalue=$2

  WEDOS_Username="${WEDOS_Username:-$(_readaccountconf_mutable WEDOS_Username)}"
  WEDOS_Wapipass="${WEDOS_Wapipass:-$(_readaccountconf_mutable WEDOS_Wapipass)}"
  WEDOS_Authtoken="${WEDOS_Authtoken:-$(_readaccountconf_mutable WEDOS_Authtoken)}"

  if [ "${WEDOS_Authtoken}" ]; then
    _debug "WEDOS Authtoken was already saved, using saved one"
    _saveaccountconf_mutable WEDOS_Authtoken "${WEDOS_Authtoken}"
  else
    if [ -z "${WEDOS_Username}" ] || [ -z "${WEDOS_Wapipass}" ]; then
      WEDOS_Username=""
      WEDOS_Wapipass=""
      _err "You didn't specify a WEDOS's username and wapi key yet."
      _err "Please type: export WEDOS_Username=<your user name to login to wedos web account>"
      _err "And: export WEDOS_Wapipass=<your WAPI passwords you setup using wedos web pages>"
      _err "After you export those variables, run the script again, the values will be saved for future"
      return 1
    fi

    #build WEDOS_Authtoken
    _debug "WEDOS Authtoken were not saved yet, building"
    WEDOS_Authtoken=$(printf '%s' "${WEDOS_Wapipass}" | sha1sum | head -c 40)
    _debug "WEDOS_Authtoken step 1, WAPI PASS sha1 sum: '${WEDOS_Authtoken}'"
    WEDOS_Authtoken="${WEDOS_Username}${WEDOS_Authtoken}"
    _debug "WEDOS_Authtoken step 2, username concat with token without hours: '${WEDOS_Authtoken}'"

    #save details

    _saveaccountconf_mutable WEDOS_Username "${WEDOS_Username}"
    _saveaccountconf_mutable WEDOS_Wapipass "${WEDOS_Wapipass}"
    _saveaccountconf_mutable WEDOS_Authtoken "${WEDOS_Authtoken}"
  fi

  if ! _get_root "${fulldomain}"; then
    _err "WEDOS Account do not contain primary domain to fullfill add of ${fulldomain}!"
    return 1
  fi

  _debug _sub_domain "${_sub_domain}"
  _debug _domain "${_domain}"

  if _wapi_find_row "${_domain}" "${_sub_domain}" "${txtvalue}"; then
    _info "WEDOS WAPI: dns record found with id '${_row_id}'"

    if _wapi_delete_row "${_domain}" "${_row_id}"; then
      _info "WEDOS WAPI: dns row were deleted and changes commited!"
      return 0
    fi
  fi

  _err "Requested dns row were not found or was imposible to delete it, do it manually"
  _err "Delete: ${fulldomain}"
  _err "Value: ${txtvalue}"
  return 1
}

####################  Private functions below ##################################

# Function _wapi_post(), only takes data, prepares auth token and provide result
# $1 - WAPI command string, like 'dns-domains-list'
# $2 - WAPI data for given command, is not required
# returns WAPI response if request were successfully delivered to WAPI endpoint
_wapi_post() {
  command=$1
  data=$2

  _debug "Command : ${command}"
  _debug "Data : ${data}"

  if [ -z "${command}" ]; then
    _err "No command were provided, implamantation error!"
    return 1
  fi

  # Prepare authentification token
  hour=$(date +%H)
  token=$(printf '%s' "${WEDOS_Authtoken}${hour}" | sha1sum | head -c 40)
  _debug "Authentification token is '${token}'"

  # Build xml request

  request="request=<?xml version=\"1.0\" encoding=\"UTF-8\"?>\
<request>\
  <user>${WEDOS_Username}</user>\
  <auth>${token}</auth>\
  <command>${command}</command>"

  if [ -z "${data}" ]; then
    echo "" 1>/dev/null
  else
    request="${request}${data}"
  fi

  if [ -z "$TESTING_STAGE" ]; then
    echo "" 1>/dev/null
  else
    request="${request}\
  <test>1</test>"
  fi

  request="${request}\
</request>"

  _debug "Request to WAPI is: ${request}"

  if ! response="$(_post "${request}" "$WEDOS_WAPI_ENDPOINT")"; then
    _err "Error contacting WEDOS WAPI with command ${command}"
    return 1
  fi

  _debug "Response : ${response}"
  echo "${response}" | grep "<code>1000</code>" 1>/dev/null 2>/dev/null

  return "$?"
}

# _get_root() function, for provided full domain, like _acme_challenge.www.example.com verify if WEDOS contains a primary active domain and found what is subdomain
# $1 - full domain to verify, ie _acme_challenge.www.example.com
# build ${_domain} found at WEDOS, like example.com and ${_sub_domain} from provided full domain, like _acme_challenge.www
_get_root() {
  domain=$1

  if [ -z "${domain}" ]; then
    _err "Function _get_root was called without argument, implementation error!"
    return 1
  fi

  _debug "Get root for domain: ${domain}"

  _debug "Getting list of domains using WAPI ..."

  if ! _wapi_post "dns-domains-list"; then
    _err "Error on WAPI request for list of domains, response : ${response}"
    return 1
  else
    _debug "DNS list were successfully retrieved, response : ${response}"
  fi

  for xml_domain in $(echo "${response}" | tr -d '\012\015' | grep -o -E "<domain>( )*<name>.*</name>( )*<type>primary</type>( )*<status>active</status>" | grep -o -E "<name>.*</name>"); do
    _debug "Active and primary XML DOMAIN found: ${xml_domain}"
    end_of_name=$((${#xml_domain} - 7))
    xml_domain_name=$(echo "${xml_domain}" | cut -c 7-${end_of_name})
    _debug "Found primary active domain: ${xml_domain_name}"
    regex=".*\\."$(echo "${xml_domain_name}" | sed 's/\./\\./g')
    _debug "Regex for matching domain: '${regex}'"

    if ! echo "${domain}" | grep -E "${regex}" 1>/dev/null 2>/dev/null; then
      _debug "found domain do not match required"
    else
      end_of_name=$((${#domain} - ${#xml_domain_name} - 1))
      _domain=${xml_domain_name}
      _sub_domain=$(echo "${domain}" | cut -c -${end_of_name})
      _info "Domain '${_domain}' was found at WEDOS account as primary, and subdomain is '${_sub_domain}'!"
      return 0
    fi
  done

  return 1
}

# for provided domain, it commites all performed changes
_wapi_dns_commit() {
  domain=$1

  if [ -z "${domain}" ]; then
    _err "Invalid request to commit dns changes, domain is empty, implementation error!"
    return 1
  fi

  data="  <data>\
    <name>${domain}</name>\
  </data>"

  if ! _wapi_post "dns-domain-commit" "${data}"; then
    _err "Error on WAPI request to commit DNS changes, response : ${response}"
    _err "PLEASE USE WEB ACCESS TO CHECK IF CHANGES ARE REQUIRED TO COMMIT OR ROLLBACKED IMMEDIATELLY!"
    return 1
  else
    _debug "DNS CHANGES COMMITED, response : ${response}"
    _info "WEDOS DNS WAPI: Changes were commited to domain '${domain}'"
  fi

  return 0

}

# add one TXT dns row to a specified fomain
_wapi_row_add() {
  domain=$1
  sub_domain=$2
  value=$3
  ttl=$4

  if [ -z "${domain}" ] || [ -z "${sub_domain}" ] || [ -z "${value}" ] || [ -z "${ttl}" ]; then
    _err "Invalid request to add record, domain: '${domain}', sub_domain: '${sub_domain}', value: '${value}' and ttl: '${ttl}', on of required input were not provided, implementation error!"
    return 1
  fi

  # Prepare data for request to WAPI
  data="  <data>\
    <domain>${domain}</domain>\
    <name>${sub_domain}</name>\
    <ttl>${ttl}</ttl>\
    <type>TXT</type>\
    <rdata>${value}</rdata>\
    <auth_comment>Created using WAPI from acme.sh</auth_comment>\
  </data>"

  _debug "Adding row using WAPI ..."

  if ! _wapi_post "dns-row-add" "${data}"; then
    _err "Error on WAPI request to add new TXT row, response : ${response}"
    return 1
  else
    _debug "ROW ADDED, response : ${response}"
    _info "WEDOS DNS WAPI: Row to domain '${domain}' with name '${sub_domain}' were successfully added with value '${value}' and ttl set to ${ttl}"
  fi

  # Now we have to commit
  _wapi_dns_commit "${domain}"

  return "$?"

}

_wapi_find_row() {
  domain=$1
  sub_domain=$2
  value=$3

  if [ -z "${domain}" ] || [ -z "${sub_domain}" ] || [ -z "${value}" ]; then
    _err "Invalud request to finad a row, domain: '${domain}', sub_domain: '${sub_domain}' and value: '${value}', one of required input were not provided, implementation error!"
    return 1
  fi

  data="  <data>\
    <domain>${domain}</domain>\
  </data>"

  _debug "Searching rows using WAPI ..."

  if ! _wapi_post "dns-rows-list" "${data}"; then
    _err "Error on WAPI request to list domain rows, response : ${response}"
    return 1
  fi

  _debug "Domain rows found, response : ${response}"

  sub_domain_regex=$(echo "${sub_domain}" | sed "s/\./\\\\./g")

  _debug "Subdomain regex '${sub_domain_regex}'"

  for xml_row in $(echo "${response}" | tr -d '\012\015' | grep -o -E "<row>( )*<ID>[0-9]*</ID>( )*<name>${sub_domain_regex}</name>( )*<ttl>[0-9]*</ttl>( )*<rdtype>TXT</rdtype>( )*<rdata>${value}</rdata>" | grep -o -e "<ID>[0-9]*</ID>"); do
    _debug "Found row in DNS with ID : ${xml_row}"
    _row_id=$(echo "${xml_row}" | grep -o -E "[0-9]*")
    _info "WEDOS API: Found DNS row id ${_row_id} for domain ${domain}"
    return 0
  done

  _info "WEDOS API: No TXT row found for domain '${domain}' with name '${sub_domain}' and value '${value}'"

  return 1
}

_wapi_delete_row() {
  domain=$1
  row_id=$2

  if [ -z "${domain}" ] || [ -z "${row_id}" ]; then
    _err "Invalid request to delete domain dns row, domain: '${domain}' and row_id: '${row_id}', one of required input were not provided, implementation error!"
    return 1
  fi

  data="  <data>\
    <domain>${domain}</domain>
    <row_id>${row_id}</row_id>
</data>"

  _debug "Deleting dns row using WAPI ..."

  if ! _wapi_post "dns-row-delete" "${data}"; then
    _err "Error on WAPI request to delete dns row, response: ${response}"
    return 1
  fi

  _debug "DNS row were deleted, response: ${response}"

  _info "WEDOS API: Required dns domain row with row_id '${row_id}'  were correctly deleted at domain '${domain}'"

  # Now we have to commit changes
  _wapi_dns_commit "${domain}"

  return "$?"

}

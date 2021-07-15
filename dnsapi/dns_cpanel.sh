#!/usr/bin/env sh
# CPANEL API
#
#CPANEL_SERVER,
#CPANEL_USER,
#CPANEL_PASS


########  Public functions #####################


#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "asdafevbcfdaswerfdxczxcvs"
dns_cpanel_add() {
    fulldomain="$1"
    txtvalue="$2"
    _info "Using cPanel add"
    _debug "fulldomain: ${fulldomain}"
    _debug "txtvalue: ${txtvalue}"
    if ! _check_configuration; then
        return 1
    fi
    _get_root
    _cpanel_get "ZoneEdit" "add_zone_record" "domain=${_domain}&name=${_sub_domain}&txtdata=${txtvalue}&ttl=300&type=TXT"
    if ! _check_result "${response}" ; then
        return 1
    fi
    return 0
}


#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_cpanel_rm() {
    fulldomain=$1
    txtvalue=$2
    _info "Using cpanel rm"
    _debug "fulldomain ${fulldomain}"
    _debug "txtvalue ${txtvalue}"
    _get_root

    _cpanel_get "ZoneEdit" "fetchzone_records" "domain=${_domain}&name=${fulldomain}.&txtdata=${txtvalue}&ttl=300&type=TXT"
    line=$(echo ${response}| grep -Eo 'line":[0-9]+' | cut -d ':' -f 2 | head -n 1)
    if [[ "${line}X" != "X" ]]; then
        _cpanel_get "ZoneEdit" "remove_zone_record" "domain=${_domain}&line=${line}"
        if ! _check_result "${response}" ; then
            return 1
        fi
    else
        _err "unable to find ${fulldomain} with TXT ${txtvalue}"
    fi
}

####################  Private functions below ##################################


#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
    domain="$fulldomain"
    _cpanel_get "ZoneEdit" "fetchzones"
    _root_domains=$(echo ${response} | _egrep_o '"[^"]+"\:\[' | cut -d '"' -f 2 | grep -v -E "^data$")
    _sort_domains=$(echo "${_root_domains}" | _get_lenght_pipe | sort -r | cut -d " " -f 2)
    _number_of_dot=$(echo ${domain} | _egrep_o '\.' | wc -l)
    #Since the domains list are sorts by length
    #We can assume the first match is the right domain.
    for cpanel_domain in ${_sort_domains}; do
        idx=1
        while [ ${idx} -le ${_number_of_dot} ]; do
            _domain_test=$(printf ${domain} | cut -d "." -f ${idx}-$((_number_of_dot + 1)))
            if [ ${cpanel_domain} == ${_domain_test} ]; then
                    _domain=${cpanel_domain}
                    _sub_domain=$(printf ${domain} | cut -d "." -f 1-$((idx - 1)))
                    _debug "domain ${_domain}"
                    _debug "subdomain ${_sub_domain}"
                    return 0
            fi
            idx=$((idx + 1))
        done
    done

    return 1
}


_get_lenght_pipe(){
    while read data; do
      printf "%d %s\n" ${#data}  "${data}"
    done
}

_cpanel_get() {
  _load_configuration
  MODULE=$1
  FUNC=$2
  ARGS=$3
  mycredentials="$(printf "%s" "${CPANEL_USER}:${CPANEL_PASS}" | _base64)"
  export _H1="Authorization: Basic ${mycredentials}"
  baseURL="https://${CPANEL_SERVER}:2083/json-api/cpanel?cpanel_jsonapi_apiversion=2&cpanel_jsonapi_func=${FUNC}&cpanel_jsonapi_module=${MODULE}&cpanel_jsonapi_user=${CPANEL_USER}"
  if [ ${#ARGS} -ge 0 ]; then
    baseURL="${baseURL}&${ARGS}"
  fi
  _debug2 "_cpanel_get MODULE=${MODULE} FUNC=${FUNC} ARGS=${ARGS}"
  response="$(_get "${baseURL}")"
  _debug2 "response ${response}"
  return 0
}

_check_result(){
    result="$1"
    if echo "${result}" | _egrep_o '\"status\"\:1' >/dev/null ; then
        return 0
    else
        _mesg=$(echo ${response} | grep -Eo 'statusmsg"\:"[^"]*' | cut -d '"' -f 3)
        _err "${_mesg}"
        _debug "${response}"
        return 1
    fi
    result
}

_load_configuration(){
    if [ -z "${CPANEL_SERVER}" ] || [ -z "${CPANEL_USER}" ] || [ -z "${CPANEL_PASS}" ]; then
        if ! _check_configuration; then
            return 1
        fi
    fi
    return 0
}

_check_configuration () {
    CPANEL_SERVER="${CPANEL_SERVER:-$(_readaccountconf_mutable CPANEL_SERVER)}"
    CPANEL_USER="${CPANEL_USER:-$(_readaccountconf_mutable CPANEL_USER)}"
    CPANEL_PASS="${CPANEL_PASS:-$(_readaccountconf_mutable CPANEL_PASS)}"
    if [ -z "${CPANEL_SERVER}" ] || [ -z "${CPANEL_USER}" ] || [ -z "${CPANEL_PASS}" ]; then
        CPANEL_SERVER=""
        CPANEL_USER=""
        CPANEL_PASS=""
        _err "You don't specify cpanel server, username and password."
        _err "Please create you key and try again."
        return 1
    fi
    _saveaccountconf_mutable CPANEL_SERVER "${CPANEL_SERVER}"
    _saveaccountconf_mutable CPANEL_USER "${CPANEL_USER}"
    _saveaccountconf_mutable CPANEL_PASS "${CPANEL_PASS}"
}

#!/usr/bin/env sh

# HUAWEICLOUD_Username
# HUAWEICLOUD_Password
# HUAWEICLOUD_DomainName

iam_api="https://iam.myhuaweicloud.com"
dns_api="https://dns.ap-southeast-1.myhuaweicloud.com" # Should work

########  Public functions #####################

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
#
# Ref: https://support.huaweicloud.com/intl/zh-cn/api-dns/zh-cn_topic_0132421999.html
#
# About "DomainName" parameters see: https://support.huaweicloud.com/api-iam/iam_01_0006.html
#

dns_huaweicloud_add() {
  fulldomain=$1
  txtvalue=$2

  HUAWEICLOUD_Username="${HUAWEICLOUD_Username:-$(_readaccountconf_mutable HUAWEICLOUD_Username)}"
  HUAWEICLOUD_Password="${HUAWEICLOUD_Password:-$(_readaccountconf_mutable HUAWEICLOUD_Password)}"
  HUAWEICLOUD_DomainName="${HUAWEICLOUD_DomainName:-$(_readaccountconf_mutable HUAWEICLOUD_DomainName)}"

  # Check information
  if [ -z "${HUAWEICLOUD_Username}" ] || [ -z "${HUAWEICLOUD_Password}" ] || [ -z "${HUAWEICLOUD_DomainName}" ]; then
    _err "Not enough information provided to dns_huaweicloud!"
    return 1
  fi

  unset token # Clear token
  token="$(_get_token "${HUAWEICLOUD_Username}" "${HUAWEICLOUD_Password}" "${HUAWEICLOUD_DomainName}")"
  if [ -z "${token}" ]; then # Check token
    _err "dns_api(dns_huaweicloud): Error getting token."
    return 1
  fi
  _secure_debug "Access token is:" "${token}"

  unset zoneid
  zoneid="$(_get_zoneid "${token}" "${fulldomain}")"
  if [ -z "${zoneid}" ]; then
    _err "dns_api(dns_huaweicloud): Error getting zone id."
    return 1
  fi
  _debug "Zone ID is:" "${zoneid}"

  _debug "Adding Record"
  _add_record "${token}" "${fulldomain}" "${txtvalue}"
  ret="$?"
  if [ "${ret}" != "0" ]; then
    _err "dns_api(dns_huaweicloud): Error adding record."
    return 1
  fi

  # Do saving work if all succeeded
  _saveaccountconf_mutable HUAWEICLOUD_Username "${HUAWEICLOUD_Username}"
  _saveaccountconf_mutable HUAWEICLOUD_Password "${HUAWEICLOUD_Password}"
  _saveaccountconf_mutable HUAWEICLOUD_DomainName "${HUAWEICLOUD_DomainName}"
  return 0
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
#
# Ref: https://support.huaweicloud.com/intl/zh-cn/api-dns/dns_api_64005.html
#

dns_huaweicloud_rm() {
  fulldomain=$1
  txtvalue=$2

  HUAWEICLOUD_Username="${HUAWEICLOUD_Username:-$(_readaccountconf_mutable HUAWEICLOUD_Username)}"
  HUAWEICLOUD_Password="${HUAWEICLOUD_Password:-$(_readaccountconf_mutable HUAWEICLOUD_Password)}"
  HUAWEICLOUD_DomainName="${HUAWEICLOUD_DomainName:-$(_readaccountconf_mutable HUAWEICLOUD_DomainName)}"

  # Check information
  if [ -z "${HUAWEICLOUD_Username}" ] || [ -z "${HUAWEICLOUD_Password}" ] || [ -z "${HUAWEICLOUD_DomainName}" ]; then
    _err "Not enough information provided to dns_huaweicloud!"
    return 1
  fi

  unset token # Clear token
  token="$(_get_token "${HUAWEICLOUD_Username}" "${HUAWEICLOUD_Password}" "${HUAWEICLOUD_DomainName}")"
  if [ -z "${token}" ]; then # Check token
    _err "dns_api(dns_huaweicloud): Error getting token."
    return 1
  fi
  _secure_debug "Access token is:" "${token}"

  unset zoneid
  zoneid="$(_get_zoneid "${token}" "${fulldomain}")"
  if [ -z "${zoneid}" ]; then
    _err "dns_api(dns_huaweicloud): Error getting zone id."
    return 1
  fi
  _debug "Zone ID is:" "${zoneid}"

  record_id="$(_get_recordset_id "${token}" "${fulldomain}" "${zoneid}")"
  _recursive_rm_record "${token}" "${fulldomain}" "${zoneid}" "${record_id}"
  ret="$?"
  if [ "${ret}" != "0" ]; then
    _err "dns_api(dns_huaweicloud): Error removing record."
    return 1
  fi

  return 0
}

###################  Private functions below ##################################

# _recursive_rm_record
# remove all records from the record set
#
# _token=$1
# _domain=$2
# _zoneid=$3
# _record_id=$4
#
# Returns 0 on success
_recursive_rm_record() {
  _token=$1
  _domain=$2
  _zoneid=$3
  _record_id=$4

  # Most likely to have problems will huaweicloud side if more than 50 attempts but still cannot fully remove the record set
  # Maybe can be removed manually in the dashboard
  _retry_cnt=50

  # Remove all records
  # Therotically HuaweiCloud does not allow more than one record set
  # But remove them recurringly to increase robusty

  while [ "${_record_id}" != "0" ] && [ "${_retry_cnt}" != "0" ]; do
    _debug "Removing Record"
    _retry_cnt=$((_retry_cnt - 1))
    _rm_record "${_token}" "${_zoneid}" "${_record_id}"
    _record_id="$(_get_recordset_id "${_token}" "${_domain}" "${_zoneid}")"
    _debug2 "Checking record exists: record_id=${_record_id}"
  done

  # Check if retry count is reached
  if [ "${_retry_cnt}" = "0" ]; then
    _debug "Failed to remove record after 50 attempts, please try removing it manually in the dashboard"
    return 1
  fi

  return 0
}

# _get_zoneid
#
# _token=$1
# _domain_string=$2
#
# printf "%s" "${_zoneid}"
_get_zoneid() {
  _token=$1
  _domain_string=$2
  export _H1="X-Auth-Token: ${_token}"

  i=1
  while true; do
    h=$(printf "%s" "${_domain_string}" | cut -d . -f "$i"-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi
    _debug "$h"
    response=$(_get "${dns_api}/v2/zones?name=${h}")
    _debug2 "$response"
    if _contains "${response}" '"id"'; then
      zoneidlist=$(echo "${response}" | _egrep_o "\"id\": *\"[^\"]*\"" | cut -d : -f 2 | tr -d \" | tr -d " ")
      zonenamelist=$(echo "${response}" | _egrep_o "\"name\": *\"[^\"]*\"" | cut -d : -f 2 | tr -d \" | tr -d " ")
      _debug2 "Returned Zone ID(s):" "${zoneidlist}"
      _debug2 "Returned Zone Name(s):" "${zonenamelist}"
      zoneidnum=0
      zoneidcount=$(echo "${zoneidlist}" | grep -c '^')
      _debug "Returned Zone ID(s) Count:" "${zoneidcount}"
      while [ "${zoneidnum}" -lt "${zoneidcount}" ]; do
        zoneidnum=$(_math "$zoneidnum" + 1)
        _zoneid=$(echo "${zoneidlist}" | sed -n "${zoneidnum}p")
        zonename=$(echo "${zonenamelist}" | sed -n "${zoneidnum}p")
        _debug "Check Zone Name" "${zonename}"
        if [ "${zonename}" = "${h}." ]; then
          _debug "Get Zone ID Success."
          _debug "ZoneID:" "${_zoneid}"
          printf "%s" "${_zoneid}"
          return 0
        fi
      done
    fi
    i=$(_math "$i" + 1)
  done
  return 1
}

_get_recordset_id() {
  _token=$1
  _domain=$2
  _zoneid=$3
  export _H1="X-Auth-Token: ${_token}"

  response=$(_get "${dns_api}/v2/zones/${_zoneid}/recordsets?name=${_domain}")
  if _contains "${response}" '"id"'; then
    _id="$(echo "${response}" | _egrep_o "\"id\": *\"[^\"]*\"" | cut -d : -f 2 | tr -d \" | tr -d " ")"
    printf "%s" "${_id}"
    return 0
  fi
  printf "%s" "0"
  return 1
}

_add_record() {
  _token=$1
  _domain=$2
  _txtvalue=$3

  # Get Existing Records
  export _H1="X-Auth-Token: ${_token}"
  response=$(_get "${dns_api}/v2/zones/${zoneid}/recordsets?name=${_domain}")

  _debug2 "${response}"
  _exist_record=$(echo "${response}" | _egrep_o '"records":[^]]*' | sed 's/\"records\"\:\[//g')
  _debug "${_exist_record}"

  # Check if record exist
  # Generate body data
  if [ -z "${_exist_record}" ]; then
    _post_body="{
      \"name\": \"${_domain}.\",
      \"description\": \"ACME Challenge\",
      \"type\": \"TXT\",
      \"ttl\": 1,
      \"records\": [
        \"\\\"${_txtvalue}\\\"\"
      ]
    }"
  else
    _post_body="{
      \"name\": \"${_domain}.\",
      \"description\": \"ACME Challenge\",
      \"type\": \"TXT\",
      \"ttl\": 1,
      \"records\": [
        ${_exist_record},\"\\\"${_txtvalue}\\\"\"
      ]
    }"
  fi

  _record_id="$(_get_recordset_id "${_token}" "${_domain}" "${zoneid}")"
  _debug "Record Set ID is:" "${_record_id}"

  # Add brand new records with all old and new records
  export _H2="Content-Type: application/json"
  export _H1="X-Auth-Token: ${_token}"

  _debug2 "${_post_body}"
  if [ -z "${_exist_record}" ]; then
    _post "${_post_body}" "${dns_api}/v2/zones/${zoneid}/recordsets" >/dev/null
  else
    _post "${_post_body}" "${dns_api}/v2/zones/${zoneid}/recordsets/${_record_id}" false "PUT" >/dev/null
  fi
  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  if [ "$_code" != "202" ]; then
    _err "dns_huaweicloud: http code ${_code}"
    return 1
  fi
  return 0
}

# _rm_record $token $zoneid $recordid
# assume ${dns_api} exist
# no output
# return 0
_rm_record() {
  _token=$1
  _zone_id=$2
  _record_id=$3

  export _H2="Content-Type: application/json"
  export _H1="X-Auth-Token: ${_token}"

  _post "" "${dns_api}/v2/zones/${_zone_id}/recordsets/${_record_id}" false "DELETE" >/dev/null
  return $?
}

_get_token() {
  _username=$1
  _password=$2
  _domain_name=$3

  _debug "Getting Token"
  body="{
    \"auth\": {
      \"identity\": {
        \"methods\": [
          \"password\"
        ],
        \"password\": {
          \"user\": {
            \"name\": \"${_username}\",
            \"password\": \"${_password}\",
            \"domain\": {
              \"name\": \"${_domain_name}\"
            }
          }
        }
      },
      \"scope\": {
        \"project\": {
          \"name\": \"ap-southeast-1\"
        }
      }
    }
  }"
  export _H1="Content-Type: application/json;charset=utf8"
  _post "${body}" "${iam_api}/v3/auth/tokens" >/dev/null
  _code=$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")
  _token=$(grep "^X-Subject-Token" "$HTTP_HEADER" | cut -d " " -f 2-)
  _secure_debug "${_code}"
  printf "%s" "${_token}"
  return 0
}

#!/usr/bin/env sh
#
# DNS Integration for IBM Bluemix (formerly SoftLayer)
#
# Author: luizgn
# Based on sample from Neilpang
# Report Bugs here: https://github.com/luizgn/acme.sh
#
########  Public functions #####################

BLUEMIX_API_URL="https://${BLUEMIX_USER}:${BLUEMIX_KEY}@api.softlayer.com/rest/v3"

domainId=
domain=
host=
recordId=

dns_bluemix_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Attempting to add ${fulldomain} with ${txtvalue} into Bluemix's DNS."

  # BLUEMIX_USER is required
  if [ -z "${BLUEMIX_USER}" ]; then
    _err "Environment variable BLUEMIX_USER not defined"
    return 1
  fi

  # BLUEMIX_KEY is required
  if [ -z "${BLUEMIX_KEY}" ]; then
    _err "Environment variable BLUEMIX_KEY not defined"
    return 1
  fi

  # Check BLUEMIX_USER and BLUEMIX_KEY access
  if ! hasAccess; then
    _err "Error accessing BlueMix API. Check \$BLUEMIX_USER and \$BLUEMIX_KEY and ensure there is access to https://api.softlayer.com/"
    return 1
  fi

  # Get right domain and domain id
  if ! getDomain ${fulldomain}; then
    _err "Domain for ${fulldomain} was not found in this Bluemix account"
    return 1
  fi

  # Check if this DNS entry already exists
  if getRecordId "${domainId}" "${host}"; then
    # Update Record if it already exists
    updateTxtRecord "${recordId}" "${txtvalue}"
  else
    # Create record if it doesn't exist
    createTxtRecord "${domainId}" "${host}" "${txtvalue}"
  fi

  return 0
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_bluemix_rm() {
  fulldomain=$1

  _info "Attempting to delete ${fulldomain} from Bluemix"

  # BLUEMIX_USER is required
  if [ -z "${BLUEMIX_USER}" ]; then
    _err "Environment variable BLUEMIX_USER not defined"
    return 1
  fi

  # BLUEMIX_KEY is required
  if [ -z "${BLUEMIX_KEY}" ]; then
    _err "Environment variable BLUEMIX_KEY not defined"
    return 1
  fi

  # Check BLUEMIX_USER and BLUEMIX_KEY access
  if ! hasAccess; then
    _err "Error accessing BlueMix API. Check \$BLUEMIX_USER and \$BLUEMIX_KEY and ensure there is access to https://api.softlayer.com/"
    return 1
  fi

  # Get Domain ID
  if ! getDomain ${fulldomain}; then
    _err "Domain for ${fulldomain} was not found in this Bluemix account"
    return 1
  fi

  # Get DNS entry in this Domain
  if getRecordId "${domainId}" "${host}"; then

    # Remove record
    deleteRecordId "${recordId}"

  fi

  return 0

}

####################  Private functions below ##################################

function hasAccess {
  response=$(_get "${BLUEMIX_API_URL}/SoftLayer_Account/getDomains")

  if [[ -z "${response}" || "${response}" =~ 'Access Denied' ]]; then
    _debug "Code=${code}, Response=${response}"
    return 1
  else
    return 0
  fi
}

function getDomain {
  fulldomain=$1

  response=$(_get "${BLUEMIX_API_URL}/SoftLayer_Account/getDomains")
  _debug "Code=${code}, Response=${response}"

  for domain_item in $(echo "${response}" | tr , \\n | grep "^\"name\":" | cut -f4 -d'"'); do
    if [[ "${fulldomain}" =~ ${domain_item}$ ]]; then
      domain="${domain_item}"
      break
    fi
  done

  if [ -z "${domain}" ]; then
    return 1
  fi

  domainId=$(echo "${response}" | tr \} \\n | grep "\"name\":\"${domain}\"" | sed -n 's/.*\"id\":\([0-9]*\).*/\1/p')

  host=$(echo "${fulldomain}" | sed "s/\.${domain}\$//g")
  
  _debug "Host is ${host}, domain is ${domain} and domain id is ${domainId}"

  return 0
}

function getRecordId {
  domainId=$1
  host=$2

  response=$(_get "${BLUEMIX_API_URL}/SoftLayer_Dns_Domain/${domainId}/getResourceRecords")
  _debug "Code=${code}, Response=${response}"

  recordId=$(echo "${response}" | tr \} \\n | grep "\"host\":\"${host}\"" | sed -n 's/.*\"id\":\([0-9]*\).*/\1/p')

  if [ -z "${recordId}" ]; then
    return 1
  else
    _debug "RecordId is ${recordId}"
    return 0
  fi

}

function createTxtRecord {
  domainId=$1
  host=$2
  txtvalue=$3

  payload="{\"parameters\":[{\"host\":\"${host}\",\"data\":\"${txtvalue}\",\"ttl\":\"60\",\"type\":\"txt\",\"domainId\":\"${domainId}\"}]}"
  response=$(_post "${payload}" "${BLUEMIX_API_URL}/SoftLayer_Dns_Domain_ResourceRecord" "")
  _debug "Code=${code}, Response=${response}"

  if [[ "${response}" =~ \"host\":\"${host}\" ]]; then
    _info "${fulldomain} added into Bluemix's DNS."
    return 0
  else
    _err "Error adding ${fulldomain} in Bluemix's DNS. Details: ${response}"
    return 1
  fi

}

function updateTxtRecord {
  recordId=$1
  txtvalue=$2

  payload="{\"parameters\":[{\"data\":\"${txtvalue}\"}]}"
  response=$(_post "${payload}" "${BLUEMIX_API_URL}/SoftLayer_Dns_Domain_ResourceRecord/${recordId}" "" "PUT")
  _debug "Code=${code}, Response=${response}"

  if [ "${response}" == "true" ]; then
    _info "${fulldomain} updated in Bluemix's DNS."
    return 0
  else
    _err "Error adding ${fulldomain} in Bluemix's DNS. Details: ${response}"
    return 1
  fi

}

function deleteRecordId {
  recordId=$1

  response=$(_post "" "${BLUEMIX_API_URL}/SoftLayer_Dns_Domain_ResourceRecord/${recordId}" "" "DELETE")
  _debug "Code=${code}, Response=${response}"

  if [ "${response}" == "true" ]; then
    _info "${fulldomain} deleted from Bluemix's DNS."
    return 0
  else
    _err "Error deleting ${fulldomain}. Details: ${response}."
    return 1
  fi

}


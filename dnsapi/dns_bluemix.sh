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

  # Curl is required
  if ! type curl >/dev/null; then
    _err "curl missing. Please isntall curl"
    return 1
  fi

  # BLUEMIX_USER is required
  if [[ -z "${BLUEMIX_USER}" ]]; then
    _err "Environment variable BLUEMIX_USER not defined"
    return 1
  fi

  # BLUEMIX_KEY is required
  if [[ -z "${BLUEMIX_KEY}" ]]; then
    _err "Environment variable BLUEMIX_KEY not defined"
    return 1
  fi

  # Get right domain and domain id
  getDomain ${fulldomain}

  # Did we find domain?
  if [[ -z "${domain}" ]]; then
    return 1
  fi

  # Check if this DNS entry already exists
  getRecordId "${domainId}" "${host}"

  if [[ -z "${recordId}" ]]; then
    # Create record if it doesn't exist
    createTxtRecord "${domainId}" "${host}" "${txtvalue}"
  else
    # Update Record if it already exists
    updateTxtRecord "${recordId}" "${txtvalue}"
  fi


  return 0
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_bluemix_rm() {
  fulldomain=$1

  _info "Attempting to delete ${fulldomain} from Bluemix"

  # Curl is required
  if ! type curl >/dev/null; then
    _err "curl missing. Please isntall curl"
    return 1
  fi

  # BLUEMIX_USER is required
  if [[ -z "${BLUEMIX_USER}" ]]; then
    _err "Environment variable BLUEMIX_USER not defined"
    return 1
  fi

  # BLUEMIX_KEY is required
  if [[ -z "${BLUEMIX_KEY}" ]]; then
    _err "Environment variable BLUEMIX_KEY not defined"
    return 1
  fi

  # Get Domain ID
  getDomain ${fulldomain}

  if [[ -z "${domain}" ]]; then
    return 1
  fi

  # Get DNS entry in this Domain
  getRecordId "${domainId}" "${host}"

  if [[ -z "${recordId}" ]]; then
    _info "recordId for ${fulldomain} not found."
    return 1
  fi

  # Remove record
  deleteRecordId "${recordId}"

  return 0

}

####################  Private functions below ##################################

function getDomain {
  fulldomain=$1

  output=$(curl -s -X GET "${BLUEMIX_API_URL}/SoftLayer_Account/getDomains")

  if [[ "${output}" =~ '"error":"Access Denied. "' ]]; then
    _err "Access Denied, check BLUEMIX_USER and BLUEMIX_KEY environment variables. Details: ${output}"
    return 1
  fi

  for domain_item in $(echo "${output}" | awk 'BEGIN{RS=","}/"name"/' | cut -f4 -d'"'); do
    if [[ "${fulldomain}" =~ ${domain_item}$ ]]; then
      domain="${domain_item}"
      break
    fi
  done

  if [[ -z "${domain}" ]]; then
    _err "Domain for ${fulldomain} was not found in this Bluemix account"
    return 1
  fi

  domainId=$(echo "${output}" | \
    awk -v DOMAIN=${domain} '
      BEGIN {
        RS=",";
        FS=":";
      }
      {
        if($1~"\"id\"") {
          id=$2;
        } else if($1~"\"name\"") {
          split($2,d,"\"");
          domain=d[2];
        }
        if($0~/\}$/ && domain==DOMAIN) {
          print id;
        }
      }
    ')

  host=$(echo "${fulldomain}" | sed "s/\.${domain}\$//g")
  
  _debug "Host is ${host}, domain is ${domain} and domain id is ${domainId}"

}

function getRecordId {
  domainId=$1
  host=$2

  output=$(curl -s -X GET "${BLUEMIX_API_URL}/SoftLayer_Dns_Domain/${domainId}/getResourceRecords")

  recordId=$(echo "${output}" | \
    awk -v HOST=${host} '
      BEGIN {
        RS=",";
        FS=":";
      }
      {
        if($1=="\"host\"") {
          host=$2;
        } else if($1=="\"id\"") {
          id=$2;
        }
        if($0~/[\}|\]]$/ && host==("\"" HOST "\"")) {
          print id;
        }
      }
    ')

  _debug "RecordId is ${recordId}"

}

function createTxtRecord {
  domainId=$1
  host=$2
  txtvalue=$3

  payload="{\"parameters\":[{\"host\":\"${host}\",\"data\":\"${txtvalue}\",\"ttl\":\"900\",\"type\":\"txt\",\"domainId\":\"${domainId}\"}]}"
  output=$(curl -s -X POST -d "${payload}" "${BLUEMIX_API_URL}/SoftLayer_Dns_Domain_ResourceRecord")
  rc=$?

  if [[ "${rc}" == "0" && "${output}" =~ \"host\":\"${host}\" ]]; then
    _info "${fulldomain} added into Bluemix's DNS."
    _debug ${output}
  else
    _err "Error adding ${fulldomain} in Bluemix's DNS. Details: ${output}"
  fi
}

function updateTxtRecord {
  recordId=$1
  txtvalue=$2

  payload="{\"parameters\":[{\"data\":\"${txtvalue}\"}]}"
  output=$(curl -s -X PUT -d "${payload}" "${BLUEMIX_API_URL}/SoftLayer_Dns_Domain_ResourceRecord/${recordId}")
  rc=$?

  if [[ "${rc}" == "0" && "${output}" == "true" ]]; then
    _info "${fulldomain} updated in Bluemix's DNS."
  else
    _err "Error adding ${fulldomain} in Bluemix's DNS. Details: ${output}"
  fi
}

function deleteRecordId {
  recordId=$1

  output=$(curl -s -X DELETE "${BLUEMIX_API_URL}/SoftLayer_Dns_Domain_ResourceRecord/${recordId}")
  rc=$?
 
  if [[ "${rc}" == "0" && "${output}" == "true" ]]; then
    _info "${fulldomain} deleted from Bluemix's DNS."
  else
    _err "Error deleting ${fulldomain}. Details: ${output}."
  fi
}


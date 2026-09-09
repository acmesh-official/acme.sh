#!/usr/bin/env sh

# shellcheck disable=SC2034
# shellcheck disable=SC2016
dns_gcloud_rest_info='Google Cloud DNS (REST)
Site: cloud.google.com/dns
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_gcloud_rest
Options:
 GCP_PROJECT GCP Project. The project that owns the DNS record sets. Name or number.
 GCP_SERVICE_ACCOUNT GCP service account name. Example: my-dns-service-account@my-dns-project.iam.gserviceaccount.com
 GCP_SERVICE_ACCOUNT_KEY GCP service account key. Accepts a literal key or a path to a key file.
Author: Chris Barrick <chrisbarrick@google.com> <cbarrick1@gmail.com>
'

# Notes:
#  You can paste the service account key directly into GCP_SERVICE_ACCOUNT_KEY
#  or set this variable to a path to the key file. This script supports JSON
#  keys or the raw private key as a PEM file. P12 keys are not supported. File
#  names must end with `*.json` or `*.pem`.
#
#  This script does not support DNS Security Extensions (RFC 4034). Any
#  signatures stored on the resource record set in Cloud DNS will be
#  stripped when the resource record set is updated.

# Public functions
# ---------------------------------------------------------------------------

dns_gcloud_rest_add() {
  domain="$1"
  record="$2"

  _info "Using gcloud_rest"
  _load_config || return 1
  _save_config || return 1

  access_token=$(_get_access_token) || return 1
  zone=$(_pick_zone "${access_token}" "${domain}") || return 1

  _debug "Adding TXT record for ${domain}: ${record}"

  # If a matching ResourceRecordSet exists, the record is inserted into it.
  # Otherwise a new ResourceRecordSet is created.
  if _has_rrset "${access_token}" "${zone}" "${domain}" TXT; then
    _patch_add_rrset "${access_token}" "${zone}" "${domain}" TXT "${record}"
  else
    _create_rrset "${access_token}" "${zone}" "${domain}" TXT "${record}"
  fi
}

dns_gcloud_rest_rm() {
  domain="$1"
  record="$2"

  _info "Using gcloud_rest"
  _load_config || return 1
  _save_config || return 1

  access_token=$(_get_access_token) || return 1
  zone=$(_pick_zone "${access_token}" "${domain}") || return 1

  _debug "Removing TXT record for ${domain}: ${record}"

  # If the ResourceRecordSet has more than one record, the record is removed
  # from it. Otherwise, if the ResourceRecordSet contains only this record,
  # the entire ResourceRecordSet deleted.
  if _has_many_records "${access_token}" "${zone}" "${domain}" TXT; then
    _patch_remove_rrset "${access_token}" "${zone}" "${domain}" TXT "${record}"
  elif _has_record "${access_token}" "${zone}" "${domain}" TXT "${record}"; then
    _delete_rrset "${access_token}" "${zone}" "${domain}" TXT
  fi
}

# Helpers
# ---------------------------------------------------------------------------

# Literal newline.
# Some implementations of sed do not support escapes in the replacement
# pattern (e.g. OpenBSD). So we can use "\\${NL}" instead of '\n'. Note that
# a literal newline (`${NL}`) must be prefixed by a backslash (`\`) in a sed
# replacement pattern.
NL='
'

# Populates the global variables:
# - GCP_PROJECT
# - GCP_SERVICE_ACCOUNT
# - GCP_SERVICE_ACCOUNT_KEY
#
# This will read the variables if they are set in the environment or try to
# read them from the account config.
_load_config() {
  GCP_PROJECT="${GCP_PROJECT:-$(_readaccountconf_mutable GCP_PROJECT)}"
  GCP_SERVICE_ACCOUNT="${GCP_SERVICE_ACCOUNT:-$(_readaccountconf_mutable GCP_SERVICE_ACCOUNT)}"
  GCP_SERVICE_ACCOUNT_KEY="${GCP_SERVICE_ACCOUNT_KEY:-$(_readaccountconf_mutable GCP_SERVICE_ACCOUNT_KEY)}"

  if [ "${GCP_PROJECT}" = "" ]; then
    _err "GCP_PROJECT is not set."
    return 1
  fi

  if [ "${GCP_SERVICE_ACCOUNT}" = "" ]; then
    _err "GCP_SERVICE_ACCOUNT is not set."
    return 1
  fi

  if [ "${GCP_SERVICE_ACCOUNT_KEY}" = "" ]; then
    _err "GCP_SERVICE_ACCOUNT_KEY is not set."
    return 1
  fi

  _debug GCP_PROJECT "$GCP_PROJECT"
  _debug GCP_SERVICE_ACCOUNT "$GCP_SERVICE_ACCOUNT"
  _secure_debug GCP_SERVICE_ACCOUNT_KEY "$GCP_SERVICE_ACCOUNT_KEY"
  return 0 # _secure_debug seems to be returning non-zero, so we override it.
}

# Saves the global variables to the account config:
# - GCP_PROJECT
# - GCP_SERVICE_ACCOUNT
# - GCP_SERVICE_ACCOUNT_KEY
_save_config() {
  _saveaccountconf_mutable GCP_PROJECT "${GCP_PROJECT}" || return 1
  _saveaccountconf_mutable GCP_SERVICE_ACCOUNT "${GCP_SERVICE_ACCOUNT}" || return 1
  _saveaccountconf_mutable GCP_SERVICE_ACCOUNT_KEY "${GCP_SERVICE_ACCOUNT_KEY}" || return 1
}

# Print without interpreting escape sequences. No trailing newline.
_print() {
  printf "%s" "$1"
}

# Extract a JSON string value for a given key.
#
# The JSON is passed on stdin, and the key is passed as $1.
#
# WARNING: This is regex based and does not parse the JSON. It only looks for
# the last instance of the key, regardless of how deeply nested, and extracts
# its value. This should not be used on complex payloads.
_get_json_str() {
  # _json_encode puts "\\n" (i.e. 0x5c 0x6e) at the end of the string.
  # This always happens, whether or not stdin contains a newline,
  # e.g. regardless of whether we use `echo` or `_print`.
  # So we use `sed` to strip those last two bytes.
  key=$(_print "$1" | _json_encode | sed 's/..$//')

  # WARNING: THIS IS A HEURISTIC THAT DOES NOT PARSE THE JSON.
  #
  # Algorithm:
  # 1. Extract the string `"key": "value"`. This assumes that there is no
  #    newline between the key and value. If the key is present multiple
  #    times, each key/value pair will be printed on separate lines.
  # 2. Separate all quoted strings, i.e. print `"key"` and `"value"` onto
  #    separate lines.
  # 3. Take the last line, i.e. the last `"value"`.
  # 4. Strip the leading and trailing quotes.
  # 5. Decode the JSON. The _json_decode function doesn't unescape
  #    everything, so there are multiple steps of escape handling.
  _egrep_o '"'"${key}"'"[ \t\r\n]*:[ \t\r\n]*"([^"]|\\")*"' |
    sed "s/[ \t\r\n]*:[ \t\r\n]*/\\${NL}/g" |
    tail -n 1 |
    sed 's/"\(.*\)"/\1/' |
    _json_decode |
    sed 's/\\"/"/g' |
    sed "s/\\\n/\\${NL}/g"
}

# Extract a JSON number value for a given key.
#
# The JSON is passed on stdin, and the key is passed as $1.
#
# WARNING: This is regex based and does not parse the JSON. It only looks for
# the last instance of the key, regardless of how deeply nested, and extracts
# its value. This should not be used on complex payloads.
_get_json_num() {
  # _json_encode puts "\\n" (i.e. 0x5c 0x6e) at the end of the string.
  # This always happens, whether or not stdin contains a newline,
  # e.g. regardless of whether we use `echo` or `_print`.
  # So we use `sed` to strip those last two bytes.
  key=$(_print "$1" | _json_encode | sed 's/..$//')

  # WARNING: THIS IS A HEURISTIC THAT DOES NOT PARSE THE JSON.
  #
  # Algorithm:
  # 1. Extract the string `"key": value`. This assumes that there is no
  #    newline between the key and value. If the key is present multiple
  #    times, each key/value pair will be printed on separate lines.
  # 2. Extract values.
  # 3. Take the last line, i.e. the last `value`.
  _egrep_o '"'"${key}"'"[ \t\r\n]*:[ \t\r\n]*(-?[0-9]*\.?[0-9]*e?[0-9]*)' |
    sed -E 's/.*:[ \t\r\n]*(.*)/\1/g' |
    tail -n 1
}

# Check if a given key is present in a JSON payload.
#
# The key can be present at any level.
#
# The JSON is passed on stdin, and the key is passed as $1.
_json_has_key() {
  # _json_encode puts "\\n" (i.e. 0x5c 0x6e) at the end of the string.
  # This always happens, whether or not stdin contains a newline,
  # e.g. regardless of whether we use `echo` or `_print`.
  # So we use `sed` to strip those last two bytes.
  key=$(_print "$1" | _json_encode | sed 's/..$//')

  match=$(_egrep_o '"'"${key}"'"[ \t\r\n]*:')
  if [ "${match}" = "" ]; then
    return 1
  fi
}

# Returns true if $1 is a JSON error response.
_is_error() {
  echo "$1" | _json_has_key "error"
}

# Prints a JSON array of strings.
# Does not print a trailing newline.
_format_json_array() {
  if [ "$#" = 0 ]; then
    _print "[]"
    return 0
  fi

  _print "["

  # _json_encode puts two byes '\n' (i.e. 0x5c 0x6e) at the end of the string.
  # So we use `sed` to strip those last two bytes.
  value=$(_print "$1" | _json_encode | sed 's/..$//')
  _print "\"${value}\""
  shift 1

  for value in "$@"; do
    value=$(_print "${value}" | _json_encode | sed 's/..$//')
    _print ",\"${value}\""
  done

  _print "]"
}

# Authentication
# ---------------------------------------------------------------------------
# The authentication flow works like this:
#
#   1. Construct a JWT claim for access to the DNS readwrite scope.
#   2. Sign the JWT with the service accout key, proving we have access.
#   3. Exchange the JWT for an access token, valid for 5m.
#   4. The access token may be used for future API calls.
#
# See https://developers.google.com/identity/protocols/oauth2/service-account

# A URL-safe variant of base64 encoding, used by JWTs.
_base64_urlencode() {
  _base64 | _url_replace
}

# Prints the service account private key in PEM format.
_get_service_account_key() {
  # The "GCP_SERVICE_ACCOUNT_KEY" variable provides us with the service
  # account key. We accept a few different formats.
  #
  # 1. If $GCP_SERVICE_ACCOUNT_KEY is a string ending in `*.json`, it is a
  #    file path, pointing to a JSON service account key.
  #
  # 2. If $GCP_SERVICE_ACCOUNT_KEY is a string ending with `*.pem`, it is a
  #    PEM private key, extracted from the JSON service account key.
  #
  # 3. If $GCP_SERVICE_ACCOUNT_KEY starts with `{`, then the JSON service
  #    account key was pasted directly into the variable.
  #
  # 4. If $GCP_SERVICE_ACCOUNT_KEY starts with `---`, then the PEM private
  #    key was pasted directly into the variable.
  #
  # 5. If $GCP_SERVICE_ACCOUNT_KEY starts with `base64:`, then the private
  #    key was pasted directly into the variable as base64. This is similar to
  #    the PEM format except that the PEM header and footer are removed, all
  #    newlines and whitespace are removed, and the prefix "base64:" is added.
  #    This format is useful with acmetest, the test suite used in CI, because
  #    acmetest does not support parameters with newlines.
  #
  # We do not support P12 service account keys.
  # shellcheck disable=SC2002
  case "${GCP_SERVICE_ACCOUNT_KEY}" in
  *".json")
    _debug "Loading service account key from JSON file: ${GCP_SERVICE_ACCOUNT_KEY}."
    cat "${GCP_SERVICE_ACCOUNT_KEY}" | _get_json_str "private_key"
    ;;
  *".pem")
    _debug "Loading service account key from PEM file: ${GCP_SERVICE_ACCOUNT_KEY}."
    cat "${GCP_SERVICE_ACCOUNT_KEY}"
    ;;
  "{"*)
    _debug "Loading service account key from JSON literal."
    echo "${GCP_SERVICE_ACCOUNT_KEY}" | _get_json_str "private_key"
    ;;
  "---"*)
    _debug "Loading service account key from PEM literal."
    echo "${GCP_SERVICE_ACCOUNT_KEY}"
    ;;
  "base64:"*)
    _debug "Loading service account key from base64 literal."
    echo "-----BEGIN PRIVATE KEY-----"
    echo "${GCP_SERVICE_ACCOUNT_KEY}" | sed 's/^base64://'
    echo "-----END PRIVATE KEY-----"
    ;;
  *)
    _err "Could not parse the service account key."
    return 1
    ;;
  esac
}

# Sign stdin using the service account key. Prints the signature.
# The trailing newline on stdin is ignored.
_sign_with_sa() {
  # Dump the private key to a tmp file so openssl can get to it.
  keyfile="$(_mktemp)" || return 1
  _debug "Copying service account key to ${keyfile}."
  chmod 600 "${keyfile}"
  _get_service_account_key >"${keyfile}" || return 1

  # Sign stdin, excluding the final newline.
  _debug "Signing JWT with service account key."
  payload=$(cat) # strips trailing newline
  sig="$(_print "${payload}" | _sign "${keyfile}" sha256)"
  ret="$?"

  # Delete the temp keyfile before returning.
  rm "${keyfile}"
  if [ "${ret}" != '0' ]; then
    _err "Failed to sign the JWT."
    return "${ret}"
  fi

  _print "${sig}" | _url_replace
  echo
}

# Print the JWT header in JSON format. Does not include a trailing newline.
# Currently, Google only supports RS256.
_jwt_header() {
  _print "{"
  _print "\"alg\":\"RS256\","
  _print "\"typ\":\"JWT\""
  _print "}"
}

# Prints the JWT claim-set in JSON format. Does not include a trailing newline.
# The claim is for 5m of readwrite access to the Cloud DNS API.
_jwt_claim_set() {
  iat=$(_time)       # Current UNIX time, UTC.
  exp=$((iat + 300)) # Expiration is 5m in the future.

  _print "{"
  _print "\"iss\":\"${GCP_SERVICE_ACCOUNT}\","
  _print "\"scope\":\"https://www.googleapis.com/auth/ndev.clouddns.readwrite\","
  _print "\"aud\":\"https://oauth2.googleapis.com/token\","
  _print "\"iat\":${iat},"
  _print "\"exp\":${exp}"
  _print "}"
}

# Generate a JWT signed by the service account key, which can be exchanged for
# a Google Cloud access token, authorized for Cloud DNS.
_get_jwt() {
  _debug "Building JWT."
  header=$(_jwt_header | _base64_urlencode)
  payload=$(_jwt_claim_set | _base64_urlencode)
  signature=$(echo "${header}.${payload}" | _sign_with_sa) || return 1
  echo "${header}.${payload}.${signature}"
}

# Request an access token for the Google Cloud service account.
_get_access_token() {
  _debug "Exchanging JWT for GCP access token."
  grant_type=$(_print "urn:ietf:params:oauth:grant-type:jwt-bearer" | _url_encode)
  assertion=$(_get_jwt) || return 1
  request="grant_type=${grant_type}&assertion=${assertion}"
  response=$(_post "${request}" "https://oauth2.googleapis.com/token" "" "POST" "application/x-www-form-urlencoded")

  if [ "$?" != '0' ] || _is_error "${response}"; then
    _err "Failed to request access token. Response: ${response}"
    return 1
  fi

  access_token=$(echo "${response}" | _get_json_str "access_token")
  _secure_debug access_token "${access_token}"
  echo "${access_token}"
}

# Google Cloud DNS API
# ---------------------------------------------------------------------------
# Cloud DNS offers a straight forward RESTful API.
#
# - The main class is a ResourceRecordSet. It's a collection of DNS records
#   that share the same domain, type, TTL, etc. Within a record set, the only
#   difference between the records are their values.
#
# - The record sets live under a ManagedZone, which in turn lives under a
#   Project. All we need to know about these are their names. The project is
#   given as a global argument, $GCP_PROJECT, and we have logic to lookup the
#   correct zone from the API.

# Prints a ResourceRecordSet in JSON format.
# The record values are supplied on stdin.
_format_rrset() {
  domain="$1"
  record_type="$2"
  ttl="$3"

  while IFS= read -r line; do
    rrdatas=$(printf "%s\n%s" "${rrdatas}" "${line}")
  done

  _print "{"
  _print "\"kind\":\"dns#resourceRecordSet\","
  _print "\"name\":\"${domain}.\"," # trailing dot on the domain
  _print "\"type\":\"${record_type}\","
  _print "\"ttl\":${ttl},"
  _print "\"rrdatas\":"
  # shellcheck disable=SC2086
  _format_json_array ${rrdatas}
  _print "}"
  echo
}

# List all managedZones in the given GCP project.
_list_zones() {
  access_token="$1"

  _debug "Fetching list of zones from GCP."
  _H1="Authorization: Bearer ${access_token}"
  response=$(_get "https://dns.googleapis.com/dns/v1/projects/${GCP_PROJECT}/managedZones")

  if [ "$?" != '0' ] || _is_error "${response}"; then
    _err "Failed to list DNS zones. Response: ${response}"
    return 1
  fi

  # Extract the names of the zones.
  # WARNING: This does not parse the JSON. It merely uses regex to extract a
  # known key. This is sensitive to the formatting of the response from GCP.
  echo "${response}" |
    _egrep_o "\"name\"[ \t\r\n]*:[ \t\r\n]*\"([^\"]|\\\")*\"" |
    sed -E 's/.*:.*"(.*)"/\1/g'
}

# Lookup the DNS suffix for a zone given its API name.
_get_dns_suffix_for_zone() {
  access_token="$1"
  zone="$2"

  _H1="Authorization: Bearer ${access_token}"
  response=$(_get "https://dns.googleapis.com/dns/v1/projects/${GCP_PROJECT}/managedZones/${zone}")

  if [ "$?" != '0' ] || _is_error "${response}"; then
    _err "Failed to list DNS zones. Response: ${response}"
    return 1
  fi

  # Extract the names of the zones.
  # WARNING: This does not parse the JSON. It merely uses regex to extract a
  # known key. This is sensitive to the formatting of the response from GCP.
  echo "${response}" |
    _egrep_o "\"dnsName\"[ \t\r\n]*:[ \t\r\n]*\"([^\"]|\\\")*\"" |
    sed -E 's/.*:.*"(.*)"/\1/g'
}

# Determine which managed zone should contain the record sets for this domain.
_pick_zone() {
  access_token="$1"
  domain="$2"

  zones=$(_list_zones "${access_token}")
  if [ "$?" != 0 ]; then
    return 1
  fi

  # Find the zone whose name is the longest suffix of the given domain.
  _debug "Determining the correct zone for DNS record."
  suffix_len=0
  for z in ${zones}; do
    dns_suffix=$(_get_dns_suffix_for_zone "${access_token}" "${z}")
    _debug dns_suffix "${dns_suffix}"
    case "${domain}." in # Include trailing dot in the pattern to match.
    *.${dns_suffix})
      if [ "${#dns_suffix}" -gt "${suffix_len}" ]; then
        zone="${z}"
        suffix_len="${#dns_suffix}"
      fi
      ;;
    esac
  done

  if [ "${zone}" = "" ]; then
    _err "No matching zone for domain ${domain}."
    return 1
  fi

  echo "${zone}"
}

# Fetch a ResourceRecordSet from the Cloud DNS API.
_get_rrset() {
  access_token="$1"
  zone="$2"
  domain="$3"
  record_type="$4"

  _debug "Fetching RRSet: ${domain} ${record_type}."
  _H1="Authorization: Bearer ${access_token}"
  response=$(_get "https://dns.googleapis.com/dns/v1/projects/${GCP_PROJECT}/managedZones/${zone}/rrsets/${domain}./${record_type}")

  if [ "$?" != '0' ] || _is_error "${response}"; then
    _err "Failed to get RRSet for ${domain} ${record_type}. Response: ${response}"
    return 1
  fi

  echo "${response}"
}

# Determine if a ResourceRecordSet exists.
# Like _get_rrset but quieter.
_has_rrset() {
  access_token="$1"
  zone="$2"
  domain="$3"
  record_type="$4"

  _debug "Fetching RRSet: ${domain} ${record_type}."
  _H1="Authorization: Bearer ${access_token}"
  response=$(_get "https://dns.googleapis.com/dns/v1/projects/${GCP_PROJECT}/managedZones/${zone}/rrsets/${domain}./${record_type}")

  if [ "$?" != '0' ] || _is_error "${response}"; then
    return 1
  fi
}

# Determine if a ResourceRecordSet has multiple records.
_has_many_records() {
  access_token="$1"
  zone="$2"
  domain="$3"
  record_type="$4"

  rrset=$(_get_rrset "${access_token}" "${zone}" "${domain}" "${record_type}") || return 1
  count=$(echo "${rrset}" | _extract_records | wc -l)
  if [ "${count}" -lt 2 ]; then
    return 1
  fi
}

# Determine if a ResourceRecordSet has a given record.
_has_record() {
  access_token="$1"
  zone="$2"
  domain="$3"
  record_type="$4"
  record="$5"

  rrset=$(_get_rrset "${access_token}" "${zone}" "${domain}" "${record_type}") || return 1
  echo "${rrset}" | _extract_records | grep -F "${record}" >/dev/null
}

# Extract the record data from a ResourceRecordSet JSON.
# WARNING: This uses regex and does not parse the JSON
# It is sensitive to the response formatting.
_extract_records() {
  # NOTE: _json_decode doesn't unescape quotes, so that an an extra step.
  sed -n '/"rrdatas"[ \t\r\n]*:[ \t\r\n]*\[/,/\]/p' |
    _egrep_o '"([^\"]|\\\")*"' |
    tail -n +2 |
    sed -E 's/^"(.*)"$/\1/g' |
    sed 's/\\"/"/g' |
    _json_decode
}

# Add a record to a ResourceRecordSet JSON.
# The ResourceRecordSet JSON is passed on stdin.
_add_rrdata() {
  rrset="$(cat)"
  rrdata="$1"

  if [ "${rrdata}" = "" ]; then
    _err "No record provided"
    return 1
  fi

  # Use `sed` to strip the trailing dot on the domain.
  domain=$(echo "${rrset}" | _get_json_str "name" | sed 's/\.$//')
  record_type=$(echo "${rrset}" | _get_json_str "type")
  ttl=$(echo "${rrset}" | _get_json_num "ttl")

  echo "${rrset}" |
    _extract_records |
    (cat && echo "${rrdata}") |
    _format_rrset "${domain}" "${record_type}" "${ttl}"
}

# Remove a record from a ResourceRecordSet JSON.
# The ResourceRecordSet JSON is passed on stdin.
_remove_rrdata() {
  rrset="$(cat)"
  rrdata="$1"

  if [ "${rrdata}" = "" ]; then
    _err "No record provided"
    return 1
  fi

  domain=$(echo "${rrset}" | _get_json_str "name" | sed 's/\.$//')
  record_type=$(echo "${rrset}" | _get_json_str "type")
  ttl=$(echo "${rrset}" | _get_json_num "ttl")

  echo "${rrset}" |
    _extract_records |
    grep -Fv "${rrdata}" |
    _format_rrset "${domain}" "${record_type}" "${ttl}"
}

# Create a new ResourceRecordSet with the given record.
_create_rrset() {
  access_token="$1"
  zone="$2"
  domain="$3"
  record_type="$4"
  record="$5"
  ttl="300" # 5 minutes

  request="$(echo "${record}" | _format_rrset "${domain}" "${record_type}" "${ttl}")"

  _debug "Creating new RRSet: ${domain} ${record_type} ${record}."
  _H1="Authorization: Bearer ${access_token}"
  response=$(
    _post \
      "${request}" \
      "https://dns.googleapis.com/dns/v1/projects/${GCP_PROJECT}/managedZones/${zone}/rrsets/" \
      "" \
      "POST" \
      "application/json"
  )

  if [ "$?" != '0' ] || _is_error "${response}"; then
    _err "Failed to create RRSet for ${domain} ${record_type}. Response: ${response}"
    return 1
  fi

  _debug "Created RRSet: ${response}"
}

# Delete a ResourceRecordSet.
_delete_rrset() {
  access_token="$1"
  zone="$2"
  domain="$3"
  record_type="$4"

  _debug "Deleting RRSet: ${domain} ${record_type}."
  _H1="Authorization: Bearer ${access_token}"
  response=$(
    _post \
      "" \
      "https://dns.googleapis.com/dns/v1/projects/${GCP_PROJECT}/managedZones/${zone}/rrsets/${domain}./${record_type}" \
      "" \
      "DELETE" \
      "application/json"
  )

  if [ "$?" != '0' ] || _is_error "${response}"; then
    _err "Failed to delete RRSet for ${domain} ${record_type}. Response: ${response}"
    return 1
  fi

  _debug "Deleted RRSet: ${response}"
}

# Add a record to an ResourceRecordSet.
_patch_add_rrset() {
  access_token="$1"
  zone="$2"
  domain="$3"
  record_type="$4"
  record="$5"

  rrset=$(_get_rrset "${access_token}" "${zone}" "${domain}" "${record_type}") || return 1
  request="$(echo "${rrset}" | _add_rrdata "${record}")"

  _debug "Adding record to existing RRSet: ${domain} ${record_type} ${record}."
  _H1="Authorization: Bearer ${access_token}"
  response=$(
    _post \
      "${request}" \
      "https://dns.googleapis.com/dns/v1/projects/${GCP_PROJECT}/managedZones/${zone}/rrsets/${domain}./${record_type}" \
      "" \
      "PATCH" \
      "application/json"
  )

  if [ "$?" != '0' ] || _is_error "${response}"; then
    _err "Failed to update RRSet for ${domain} ${record_type}. Response: ${response}"
    return 1
  fi

  _debug "Updated RRSet: ${response}"
}

# Remove a record to an ResourceRecordSet.
_patch_remove_rrset() {
  access_token="$1"
  zone="$2"
  domain="$3"
  record_type="$4"
  record="$5"

  rrset=$(_get_rrset "${access_token}" "${zone}" "${domain}" "${record_type}") || return 1
  request="$(echo "${rrset}" | _remove_rrdata "${record}")"

  _debug "Removing record from existing RRSet: ${domain} ${record_type} ${record}."
  _H1="Authorization: Bearer ${access_token}"
  response=$(
    _post \
      "${request}" \
      "https://dns.googleapis.com/dns/v1/projects/${GCP_PROJECT}/managedZones/${zone}/rrsets/${domain}./${record_type}" \
      "" \
      "PATCH" \
      "application/json"
  )

  if [ "$?" != '0' ] || _is_error "${response}"; then
    _err "Failed to update RRSet for ${domain} ${record_type}. Response: ${response}"
    return 1
  fi

  _debug "Updated RRSet: ${response}"
}

#!/usr/bin/env sh

# Name: dns_pleskxml.sh
# Created by Stilez.
# Uses Plesk XML API to add/remove text records
# Repository: https://github.com/Neilpang/acme.sh

# v0.1 alpha - 2018-08-13

# This DNS01 method allows acme.sh to set DNS TXT records
# using the Plesk XML API described at:
#   https://docs.plesk.com/en-US/12.5/api-rpc/about-xml-api.28709
#   and more specifically: https://docs.plesk.com/en-US/12.5/api-rpc/reference.28784

# This may be needed if the DNS provider doesn't make the standard Plesk API available to a user.
# As a result, Plesk can't be configured using usual means or RFC1236. But the XML API is often
# still left accessible, and is well documented, so it can be used instead, for acme.sh purposes.

# API NOTES:

# 1) The API uses a user/password combination. It should therefore require cURL over HTTPS
#  with a MAXIMALLY SECURE TLS CIPHER AND GOOD CERT + REVOCATION CHECKS ON THE API URI,
#  in (almost) all cases.

#  Acceptable/valid ciphers and certificate checks can be specified via optional cURL variables (see below).
#  Note that edge cases may exist where SSL is not yet set up
#  (e.g. testing Plesk on ones own network), so although highly recommended, this can be OVERRIDDEN.

# 2) --anyauth is used with cURL, to ensure the highest available level of encryption.

# 3) The API references domains by a domain ID, when manipulating records. So the code must
#  initially convert domain names (string) to Plesk domain IDs (numeric).

# REQUIRED VARIABLES:

# You need to provide the Plesk URI and login (username and password) as follows:

#   export pleskxml_uri="https://www.plesk_uri.org:8443/enterprise/control/agent.php"
#             (or something similar)
#   export pleskxml_user="johndoe"
#   export pleskxml_pass="XXXXX"

# OPTIONAL VARIABLES:

# To use an insecure Plesk URI, set the following:
#   export pleskxml_allow_insecure_uri=yes

# Extra cURL args (for certificate handling, timeout etc):
#   export pleskxml_optional_curl_args=LIST_OF_ARGS
#                    (eg =-v   or ="-H 'HEADER STRINGS'")

# Debug level (0/absent=none, 1=all, 2=major msgs only, 3=minimum msgs/most severe only)
# If debug level is nonzero, all DBG messages equal to or more severe than this, are displayed.
# By design if DBG level is 9 for a message, it is ALWAYS shown, this is used for _info and _err
#   export pleskxml_debug_min_level=2

############  Before anything else, define dedug functions to be sure they are detected even if while testing #####################

_pleskxml_DBG_EARLY_CHECK_MODE() {

  if printf '%s' "${pleskxml_debug_min_level:-0}" | grep -qE '^[0-3]$'; then
    _pleskxml_pleskxml_DBG_LEVEL="${pleskxml_debug_min_level:-0}"
    _pleskxml_pleskxml_DBG_COUNT=0
  else
    _err "Invalid debug level, exiting. \$pleskxml_debug_min_level = '${pleskxml_debug_min_level}' "
    return 1
  fi

  if [ "$_pleskxml_pleskxml_DBG_LEVEL" -gt 0 ]; then
    _info "plesk XML running in debug mode. Debug level =  '${_pleskxml_pleskxml_DBG_LEVEL}' "
    # This won't display if DBG level was set to zero.
  fi
}

# arg1 = severity level (1=least serious, 3=most serious)
#   By design if DBG level is 9 for a MESSAGE, the message is ALWAYS shown, this is used for _info and _err
# arg2 = message
_pleskxml_DBG() {
  if [ "$1" -eq 9 ] || ([ "$_pleskxml_pleskxml_DBG_LEVEL" -gt 0 ] && [ "$1" -ge "$_pleskxml_pleskxml_DBG_LEVEL" ]); then
    case $1 in
      1) _pleskxml_severity='MAX_DETAIL' ;;
      2) _pleskxml_severity='DETAIL' ;;
      3) _pleskxml_severity='INFO' ;;
      9) _pleskxml_severity='ACME.SH' ;;
    esac
    _pleskxml_pleskxml_DBG_COUNT=$((_pleskxml_pleskxml_DBG_COUNT + 1))
    printf '%04d DEBUG [%s/%d]:\n%s\n\n' "$_pleskxml_pleskxml_DBG_COUNT" "$_pleskxml_severity" "$1" "$2"
  fi
}

# Used by _pleskxml_DBG_VARDUMP to capture all _pleskxml_* variables for debug output
# Credit to/based on Stephanie Chazelas' snippet:
# https://unix.stackexchange.com/questions/462280/listing-shell-variables-with-a-fixed-prefix
_pleskxml_DBG_GET_VAR() {
  case "$1" in _pleskxml_*)
    __pleskxml_vars="${__pleskxml_vars}$(printf '%s' "$1" | sed 's/^_pleskxml_DBG_GET_VAR //' | sed -E '1 s~^([^=]+)=~    \1 --> "~')\"${_pleskxml_newline}"
    ;;
  esac
  # Old code in case:
  #   if printf '%s' "$1" | grep -qE '^_pleskxml_'; then
  #     __pleskxml_vars="${__pleskxml_vars}$(printf '%s' "$1" | sed 's/^_pleskxml_DBG_GET_VAR //' | sed -E '1 s~^([^=]+)=~    \1 --> ~')${_pleskxml_newline}"
  #   fi
}

# arg1 = severity level (1=least serious, 3=most serious)
_pleskxml_DBG_VARDUMP() {
  __pleskxml_vars=''
  eval "$(set | sed 's/^/_pleskxml_DBG_GET_VAR /')"
  _pleskxml_DBG "$1" "$(printf 'Currently defined _pleskxml_* variables are:\n%s\n\n' "$__pleskxml_vars")"
  #  Old code in case:
  #  _pleskxml_DBG "$1" "$(printf '1st lines of current defined variables are now:\n%s\n\n' "$(set | grep '_pleskxml' | sort)")"
}

_pleskxml_DBG_ERR_TRAP() {
  echo "Error on line $1"
}

############ Start of module itself ##############################

# Trap errors and perform early check for debug mode.
# Traps currently ignored

# set -e
# trap '_pleskxml_DBG_ERR_TRAP ${LINENO:-NO_LINE}' .....

_pleskxml_DBG_EARLY_CHECK_MODE

############  Set up static/private variables #####################

_pleskxml_curlpath=/usr/local/bin/curl

_pleskxml_newline='
'

# Plesk XML templates.
#   Note ALL TEMPLATES MUST HAVE EXACTLY 3 %s PLACEHOLDERS
#   (otherwise printf repeats the string causing the API call to fail)

_pleskxml_tplt_get_domain_id="<packet><webspace><get><filter><name>%s</name></filter><dataset></dataset></get></webspace></packet>"
#  Convert domain name to a Plesk internal domain ID
#  Args:
#    the domain name to query

_pleskxml_tplt_add_txt_record="<packet><dns><add_rec><site-id>%s</site-id><type>TXT</type><host>%s</host><value>%s</value></add_rec></dns></packet>"
#  Adds a TXT record to a domain
#  Args:
#    the Plesk internal domain ID for the domain
#    the "host" entry within the domain, to add this to (eg '_acme_challenge')
#    the TXT record value

_pleskxml_tplt_rmv_dns_record="<packet><dns><del_rec><filter><id>%s</id></filter></del_rec></dns></packet>"
#  Adds a TXT record to a domain
#  Args:
#    the Plesk internal ID for the dns record to delete

_pleskxml_tplt_get_dns_records="<packet><dns><get_rec><filter><site-id>%s</site-id></filter></get_rec></dns></packet>"
#  Gets all DNS records for a Plesk domain ID
#  Args:
#    the domain id to query

############  Define public functions #####################

# Usage: dns_pleskxml_add _acme-challenge.domain.org "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"

dns_pleskxml_add() {

  _pleskxml_DBG 3 "Entered dns_pleskxml_add($*)..."

  _pleskxml_FQDN="$1"
  _pleskxml_TXT_string="$2"

  # validate variables set by user.
  # If valid, then matching internal variables will be set with the appropriate checked values
  # Otherwise exit with an error

  _info "Plesk XML: Requested action: Add DNS TXT string '$_pleskxml_TXT_string' to domain: '$_pleskxml_FQDN'."
  _info "Plesk XML: Checking login and other variables supplied by user"

  _pleskxml_get_variables
  _pleskxml_retcode=$?

  _pleskxml_DBG 3 'Returned from _pleskxml_get_variables(). Back in dns_pleskxml_add().'
  _pleskxml_DBG_VARDUMP 2

  if [ $_pleskxml_retcode -ne 0 ] || [ "$_pleskxml_errors" != '' ]; then
    _err "$_pleskxml_errors"
    return 1
  fi

  if [ "$_pleskxml_allow_insecure" -eq 1 ]; then
    _info 'Plesk XML: You have allowed insecure http connections to Plesk. Passwords and logins may be sent in plain text.\nPlease do not use this setting unless very sure of security!'
  fi

  # Try to convert the domain name to a plesk domain ID. This also lets us know if the URI and authentication are OK.

  _info "Plesk XML: Variables are valid and loaded."
  _info "Trying to connect to Plesk ($_pleskxml_uri), and request Plesk's internal reference ID for domain '${_pleskxml_domain}'"

  _pleskxml_DBG 3 "Calling API to get domain ID for $_pleskxml_domain"

  _pleskxml_get_domain_ID "$_pleskxml_domain"
  _pleskxml_retcode=$?

  _pleskxml_DBG 3 'Returned from API call. Back in dns_pleskxml_add().'
  _pleskxml_DBG_VARDUMP 2

  if [ $_pleskxml_retcode -ne 0 ] || [ "$_pleskxml_errors" != '' ] || [ "$_pleskxml_result" = '' ]; then
    # Really, just testing return code should be enough, based on above code, but let's go "all-in" and test all variables returned
    _err "$_pleskxml_errors"
    return 1
  fi

  # OK, valid response containing a valid domain ID must have been found
  # If not we should have got an error.

  # Try to add the TXT record

  _pleskxml_DBG 3 "Calling API to add TXT record to domain ID #$_pleskxml_domain_id ('$_pleskxml_domain')"

  _info "Plesk XML: Got ID for domain. Trying to add TXT record to domain ID $_pleskxml_domain_id ('$_pleskxml_domain'), host '$_pleskxml_host'. The TXT string is: '$_pleskxml_TXT_string'."

  _pleskxml_add_txt_record "$_pleskxml_domain_id" "$_pleskxml_host" "$_pleskxml_TXT_string"
  _pleskxml_retcode=$?

  _pleskxml_DBG 3 'Call has returned. dns_pleskxml_add().'
  _pleskxml_DBG_VARDUMP 2

  if [ $_pleskxml_retcode -ne 0 ] || [ "$_pleskxml_errors" != '' ] || [ "$_pleskxml_result" = '' ]; then
    # Really, just testing return code should be enough, based on above code, but let's go "all-in" and test all variables returned
    _err "$_pleskxml_errors"
    return 1
  fi

  _info 'An ACME Challenge TXT record for '"$_pleskxml_domain"' was added to Plesk. Plesk returned a successful response.\nThe TXT field was: '"'$_pleskxml_TXT_string'"

  _pleskxml_DBG 2 "SUCCESSFULLY exiting dns_pleskxml_add()..."

  return 0
}

# Usage: dns_pleskxml_rm _acme-challenge.domain.org "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Remove a TXT record after validation

dns_pleskxml_rm() {

  _pleskxml_DBG 2 "Entered dns_pleskxml_rm($*)..."

  _pleskxml_FQDN="$1"
  _pleskxml_TXT_string="$2"

  # validate variables set by user.
  # If valid, then matching internal variables will be set with the appropriate checked values
  # Otherwise exit with an error

  _info "Plesk XML: Requested action: Remove DNS TXT string '$_pleskxml_TXT_string' from domain: '$_pleskxml_FQDN'."
  _info "Plesk XML: Checking login and other variables supplied by user"

  _pleskxml_get_variables
  _pleskxml_retcode=$?

  _pleskxml_DBG 2 'Called _pleskxml_get_variables()'
  _pleskxml_DBG_VARDUMP 2

  if [ $_pleskxml_retcode -ne 0 ] || [ "$_pleskxml_errors" != '' ]; then
    _err "$_pleskxml_errors"
    return 1
  fi

  if [ "$_pleskxml_allow_insecure" -eq 1 ]; then
    _info 'Plesk XML: You have allowed insecure http connections to Plesk. Passwords and logins may be sent in plain text.\nPlease do not use this setting unless very sure of security!'
  fi

  # Try to convert the domain name to a plesk domain ID. This also lets us know if the URI and authentication are OK.

  _info "Plesk XML: Variables are valid and loaded."
  _info "Trying to connect to Plesk ($_pleskxml_uri), and request Plesk's internal reference ID for domain '${_pleskxml_domain}'"

  _pleskxml_DBG 2 "Calling API to get domain ID for $_pleskxml_domain"

  _pleskxml_get_domain_ID "$_pleskxml_domain"
  _pleskxml_retcode=$?

  _pleskxml_DBG 2 'Call has returned'
  _pleskxml_DBG_VARDUMP 2

  if [ $_pleskxml_retcode -ne 0 ] || [ "$_pleskxml_errors" != '' ] || [ "$_pleskxml_result" = '' ]; then
    # Really, just testing return code should be enough, based on above code, but let's go "all-in" and test all variables returned
    _err "$_pleskxml_errors"
    return 1
  fi

  # OK, valid response containing a valid domain ID must have been found
  # If not we should have got an error.

  # Try to remove the TXT record. First step - get all TXT records

  _info "Plesk XML: Got ID for domain. Trying to remove TXT record from domain ID $_pleskxml_domain_id ('$_pleskxml_domain'), host '$_pleskxml_host'."

  _pleskxml_DBG 2 "Calling API to remove TXT record from domain ID #$_pleskxml_domain_id ('$_pleskxml_domain')"

  _pleskxml_rmv_txt_record "$_pleskxml_domain_id" "$_pleskxml_host" "$_pleskxml_TXT_string"
  _pleskxml_retcode=$?

  _pleskxml_DBG 2 'Call has returned'
  _pleskxml_DBG_VARDUMP 2

  if [ $_pleskxml_retcode -ne 0 ] || [ "$_pleskxml_errors" != '' ] || [ "$_pleskxml_result" = '' ]; then
    # Really, just testing return code should be enough, based on above code, but let's go "all-in" and test all variables returned
    _err "$_pleskxml_errors"
    return 1
  fi

  _info 'A TXT record for '"$_pleskxml_domain"' was removed from Plesk. Plesk returned a successful response.\nThe TXT field was: '"'$_pleskxml_TXT_string'"

  _pleskxml_DBG 2 "SUCCESSFULLY exiting dns_pleskxml_rm()..."

  return 0
}

####################  Define private functions ##################################

####################  Plesk related functions

_pleskxml_get_variables() {

  _pleskxml_DBG 2 'Entered _pleskxml_get_variables()'
  _pleskxml_DBG_VARDUMP 2

  _pleskxml_errors=''

  # The Plesk XML API needs the base domain (mydomain.com) and host (_acme_challenge) split out from the FQDN
  # supplied to this module, to manage the relevant DNS records
  # We assume ACME.SH does most of the validation, but even so, let's check some basic character compliance.
  # Not checking just [a-z0-9] since the FQDN could be unicode, but this should be reasonably sane.
  # If not, it'll be over-cautious and block unicode based on bytes, and need fixing.
  # At most the check can be removed. But it needs to be able to split out a host and a domain.

  if printf '%s' "$_pleskxml_FQDN" | grep -iEq '^[^][/.:[:space:]^$*'\''"`-][^][/.:[:space:]^$*'\''"`]*(\.[^][/.:[:space:]^$*'\''"`_]+)+$'; then
    _pleskxml_host="$(printf '%s' "$_pleskxml_FQDN" | sed -E 's/^([^.]+)\..*$/\1/')"
    _pleskxml_domain="$(printf '%s' "$_pleskxml_FQDN" | sed -E 's/^[^.]+\.(.*)$/\1/')"
  else
    _pleskxml_errors="An invalid domain name (FQDN) was supplied."
  fi

  # Now process other variables

  _pleskxml_allow_insecure="${pleskxml_allow_insecure_uri:-no}"
  if [ "$_pleskxml_allow_insecure" = "yes" ] || [ "$_pleskxml_allow_insecure" = "Yes" ] || [ "$_pleskxml_allow_insecure" = "YES" ]; then
    # Allow insecure (non-SSL) URI for Plesk. "s" is optional within the "https" URI
    _pleskxml_allow_insecure=1
    _pleskxml_uri_prefix_match='https?://'
  else
    # Require secure (SSL) URI for Plesk. "s" is mandatory within the "https" URI
    _pleskxml_allow_insecure=0
    _pleskxml_uri_prefix_match='https://'
  fi

  if printf '%s' "${pleskxml_uri:-}" | grep -qiE "^${_pleskxml_uri_prefix_match}"'([a-z0-9][a-z0-9.:-]*|\[[a-f0-9][a-f0-9.:]+\])(:[0-9]{1,5})?(/|$)'; then
    # URI is "valid enough" to use, and uses https if this is mandatory (= pleskxml_allow_insecure_uri wasn't set)
    _pleskxml_uri="$pleskxml_uri"
  else
    _pleskxml_errors="$_pleskxml_errors"'\nBad or unacceptable URI (If non-SSL HTTP is required, did you set "pleskxml_allow_insecure_uri"?).\nYou should set and export '"$pleskxml_uri"', containing the URI for your Plesk XML API.\nThe URI usually looks like this: https://my_plesk_uri.tld:8443'
  fi

  if printf '%s' "${pleskxml_user:-}" | grep -qiE '^[a-z0-9@%._-]+$'; then
    # USER is "valid enough" to use - Plesk doesn't stipulate valid chars, but thewse are probably "safe enough". We will find out if they aren't, the hard way :)
    # Note, we cannot assume "safe" characters when we use this value!
    _pleskxml_user="$pleskxml_user"
  else
    _pleskxml_errors="$_pleskxml_errors"'\nBad or unacceptable USER ACCOUNT for Plesk authentication. You should set and export '"$pleskxml_user."
  fi

  if [ "${pleskxml_pass:-}" != "" ]; then
    # PASS is "valid enough" to use - Plesk doesn't stipulate valid chars, but thewse are probably "safe enough". We will find out if they aren't, the hard way :)
    # Note, we cannot assume "safe" characters when we use this value!
    _pleskxml_pass="$pleskxml_pass"
  else
    _pleskxml_errors="$_pleskxml_errors"'\nEmpty USER PASSWORD for Plesk authentication. You should set and export '"$pleskxml_pass."
  fi

  # Ensure if not supplied, optional curl args are an empty string
  _pleskxml_optional_curl_args="${pleskxml_optional_curl_args:-}"

  if [ "$_pleskxml_errors" != '' ]; then
    _pleskxml_DBG 2 "UNSUCCESSFULLY exiting _pleskxml_get_variables() (UNSUCCESSFUL CALL!)"
    _pleskxml_DBG_VARDUMP 2
    _err 'Can'\''t parse user-defined variables. Exiting.'
    return 1
  else
    _pleskxml_DBG 2 "SUCCESSFULLY exiting _pleskxml_get_variables()"
    _pleskxml_DBG_VARDUMP 2
    return 0
  fi
}

# Build a cURL request for the Plesk API
# ARGS:
# First arg is a Plesk XML API template. Further args (up to 3 items) are substituted into it via printf

_pleskxml_api_request() {

  _pleskxml_DBG 2 "Entered _pleskxml_api_request($*), to make an XML request.${_pleskxml_newline}  arg1=^$1^${_pleskxml_newline}  arg2=^$2^${_pleskxml_newline}  arg3=^$3^${_pleskxml_newline}  arg4=^$4^"

  _pleskxml_errors=''
  _pleskxml_result=''
  _pleskxml_prettyprint_result=''
  _pleskxml_result=''

  # Of all the API commands we use, just one of them can return multiple results sections
  # so the validation process after cURL returns, will differ for that case.....

  if [ "$1" = "$_pleskxml_tplt_get_dns_records" ]; then
    _pleskxml_multiple_results_allowed=1
  else
    _pleskxml_multiple_results_allowed=0
  fi

  # Sanitise user+pw for single quote enclosure, ands build Plesk arg string

  _pleskxml_user="$(printf '%s' "$_pleskxml_user" | sed "s/'/'\\''/g")"
  _pleskxml_pass="$(printf '%s' "$_pleskxml_pass" | sed "s/'/'\\''/g")"
  _pleskxml_APICMD="$(printf "$1 %0.0s%0.0s%0.0s" "$2" "$3" "$4")"
  # Add some %0.0s at the end of the format string in the 1st arg, to cope with ("absorb") variable number of further args
  # otherwise this will repeat the format string which we don't want.
  # If there weren't additional args, these will evaluate to empty strings/blank, and be harmless.

  _pleskxml_curlargs="--anyauth \
         -X POST \
         -H 'Content-Type: text/xml' \
         -H 'HTTP_PRETTY_PRINT: TRUE' \
         -H 'HTTP_AUTH_LOGIN: ${_pleskxml_user}' \
         -H 'HTTP_AUTH_PASSWD: ${_pleskxml_pass}' \
         -d '${_pleskxml_APICMD}' \
         ${_pleskxml_optional_curl_args}"

  _pleskxml_DBG 2 'About to call Plesk via cURL'
  _pleskxml_DBG_VARDUMP 2

  _pleskxml_DBG 2 "$(printf 'cURL command: %s %s %s' "$_pleskxml_curlpath" "$_pleskxml_curlargs" "$_pleskxml_uri")"
  _pleskxml_prettyprint_result="$(eval "$_pleskxml_curlpath" "$_pleskxml_curlargs" "$_pleskxml_uri" 2>/dev/null)"
  _pleskxml_retcode="$?"
  _pleskxml_DBG 1 "_pleskxml_prettyprint_result =${_pleskxml_newline}'$_pleskxml_prettyprint_result' "
  _pleskxml_DBG 2 "retcode = $_pleskxml_retcode"

  # BUGFIX TO CHECK - WILL RETCODE FROM cURL BE AVAILABLE HERE?

  # Abort if cURL failed

  if [ $_pleskxml_retcode -ne 0 ]; then
    _pleskxml_errors="Exiting due to cURL error when querying Plesk XML API. The cURL return code was: $_pleskxml_retcode."
    _err "$_pleskxml_errors"
    return 1
  fi

  # OK. Next, check XML reply was OK. Start by pushing it into one line, with leading/trailing space trimmed.

  #  _pleskxml_result="$( printf '%s' "$_pleskxml_prettyprint_result" | \
  #      awk '{$1=$1};1' | \
  #      tr -d '\n' \
  #      )"

  _pleskxml_result="$(printf '%s' "$_pleskxml_prettyprint_result" \
    | sed -E 's/(^[[:space:]]+|[[:space:]]+$)//g' \
    | tr -d '\n'
  )"

  _pleskxml_DBG 2 'cURL succeeded, valid cURL response obtained'
  _pleskxml_DBG_VARDUMP 2

  # Now we need to check item by item if it's OK.
  # As we go, we will strip out "known OK" stuff to leave the core reply.

  # XML header and packet version?

  _pleskxml_DBG 2 'Checking <?xml> and <packet> tags exist...'

  if printf '%s' "$_pleskxml_result" | grep -qiEv '^<\?xml version=[^>]+><packet version=[^>]+>.*</packet>$'; then
    # Error - should have <?xml><packet>...</packet>. Abort
    _pleskxml_errors="Error when querying Plesk XML API. The API did not return a valid XML response. The response was:${_pleskxml_newline}${_pleskxml_prettyprint_result}${_pleskxml_newline}The collapsed version was:${_pleskxml_newline}'${_pleskxml_result}'${_pleskxml_newline}"
    _err "$_pleskxml_errors"
    return 1
  else
    # So far so good. Strip the <?xml> and <packet>...</packet> tags and continue
    _pleskxml_result="$(printf '%s' "$_pleskxml_result" \
      | sed -E 's/^<\?xml version[^>]+><packet version[^>]+>(.*)<\/packet>$/\1/'
    )"
  fi

  _pleskxml_DBG 2 "Checking <system> tags don't exist..."

  # <system> section found anywhere in response?
  # This usually means some kind of basic API error such as login failure, bad XML request, etc

  if printf '%s' "$_pleskxml_result" | grep -qiE '<system>.*</system>'; then
    # Error - shouldn't contain <system>...</system>. Abort
    _pleskxml_errors='Error when querying Plesk XML API. The result contained a <system> tag.\nThis usually indicates an invalid login, badly formatted API request or other error. The response was:\n'"$_pleskxml_prettyprint_result"'\n'
    _err "$_pleskxml_errors"
    return 1
  fi

  _pleskxml_DBG 2 'Checking 1 or >=1 <result> tag (or tags) found, each containing 'status:ok'...'

  # Check results section. Most commands only have one results section.
  # But some (i.e., get all DNS records for a domain) have many results sections,
  # and we will need to check each <results>...</results> section separately.
  # So this gets a bit messy, especially as we don't have non-greedy regex
  # and we will have to work around that as well.

  # For this, we will split the string up again with exactly 1 <result> section per line.
  # We check there is at least one result section. Then we add newlines before and after
  # any <result>...</result> and ignore any lines that don't contain '<result>'.

  if printf '%s' "$_pleskxml_result" | grep -qiEv '<result>.*</result>'; then
    # Error - doesn't contain <result>...</result>. Abort
    _pleskxml_errors='Error when querying Plesk XML API. The result did not contain a <result> section.\nThis is unexpected: something has gone wrong. Please raise this as a bug/issue in the module. The response was:\n'"$_pleskxml_prettyprint_result"'\n'
    _err "$_pleskxml_errors"
    return 1
  fi

  _pleskxml_DBG 2 'Found at least 1 <result> section. Splitting each result section to a separate line'

  _pleskxml_result="$(printf '%s' "$_pleskxml_result" \
    | sed "s/<result>/\\${_pleskxml_newline}<result>/g" \
    | sed "s/<\/result>/<\/result>\\${_pleskxml_newline}/g" \
    | grep '<result>'
  )"

  # Detect and abort if there are >1 <result> sections and we're ponly expecting 1 section.

  _pleskxml_linecount=$(printf '%s\n' "$_pleskxml_result" | wc -l)

  _pleskxml_DBG 2 "Result is: '$_pleskxml_result' (${_pleskxml_linecount} line(s))"

  _pleskxml_DBG 2 'Testing <result> section linecount is OK (1 or >=1 as required)'
  _pleskxml_DBG_VARDUMP 2

  if [ $_pleskxml_multiple_results_allowed -eq 0 ] && [ "$_pleskxml_linecount" -gt 1 ]; then
    # Error - contains multiple <result> sections. Abort
    _pleskxml_errors='Error when querying Plesk XML API. The result contained more than one <result> section.\nThis is unexpected: something has gone wrong. Please raise this as a bug/issue in the module. The response was:\n'"$_pleskxml_prettyprint_result"'\n'
    _err "$_pleskxml_errors"
    return 1
  fi

  _pleskxml_DBG 2 "Found ${_pleskxml_linecount} <result> section(s), checking each has status:ok..."

  # Loop through each <result> section, checking every line has exactly one result section,
  # containing exactly one status section, which contains <status>ok</status>

  while IFS= read -r _pleskxml_line; do

    # _pleskxml_line *should* contain a single result section.
    # Check this is correct.

    # _pleskxml_DBG "Checking a <result> section... content is ${_pleskxml_line}"

    if printf '%s' "$_pleskxml_line" | grep -qiEv '^<result>.*</result>$'; then
      # Error - doesn't contain <result>...</result>. Abort
      _pleskxml_errors='Error when querying Plesk XML API. A <result> section was not found where expected.\nThis is unexpected: something has gone wrong. Please raise this as a bug/issue in the module. The response was:\n'"$_pleskxml_prettyprint_result"'\n'
      _err "$_pleskxml_errors"
      return 1
    fi

    # Now strip the <results> tag and check there is precisely one <status> section and its ciontents are "ok"

    _pleskxml_line="$(printf '%s' "$_pleskxml_line" | sed -E 's/^<result>(.*)<\/result>$/\1/')"

    if printf '%s' "$_pleskxml_line" | grep -qiEv '<status>.*</status>'; then
      # Error - doesn't contain <status>...</status>. Abort
      _pleskxml_errors='Error when querying Plesk XML API. A <result> section did not contain a <status> section.\nThis is unexpected: something has gone wrong. Please raise this as a bug/issue in the module. The response was:\n'"$_pleskxml_prettyprint_result"'\n'
      _pleskxml_DBG 2 "$_pleskxml_errors"
      return 1
    elif printf '%s' "$_pleskxml_line" | grep -qiE '<status>.*</status>.*<status>'; then
      # Error - contains <status>...</status>...<status>. Abort
      _pleskxml_errors='Error when querying Plesk XML API. A <result> section contained more than one <status> section.\nThis is unexpected: something has gone wrong. Please raise this as a bug/issue in the module. The response was:\n'"$_pleskxml_prettyprint_result"'\n'
      _pleskxml_DBG 2 "$_pleskxml_errors"
      return 1
    elif printf '%s' "$_pleskxml_line" | grep -qiEv '<status>ok</status>'; then
      # Error - doesn't contain <status>ok</status>. Abort
      _pleskxml_errors='Error when querying Plesk XML API. A <status> tag did not contain "<status>ok</status>". The response was:\n'"$_pleskxml_prettyprint_result"'\n'
      _err "$_pleskxml_errors"
      return 1
    fi

    # _pleskxml_DBG "Line is OK. Looping to next line or exiting..."

  done <<EOL
$_pleskxml_result
EOL

  # So far so good. Remove all <status>ok</status> sections as they're checked now.

  _pleskxml_DBG 2 "All results lines had status:ok. Exiting loop,  and removing all <status>ok</status> tags now they've been checked"

  _pleskxml_result="$(printf '%s' "$_pleskxml_result" \
    | sed -E 's/<status>ok<\/status>//g'
  )"

  # Result is OK. Remove any redundant self-closing tags, and <data> or </data> tags, and exit

  _pleskxml_DBG 2 'Now removing any self-closing tags, or <data>...</data> tags'

  _pleskxml_result="$(printf '%s' "$_pleskxml_result" \
    | sed -E 's/(<[a-zA-Z0-9._-]+[[:space:]]*\/>|<\/?data\/?>)//g'
  )"

  _pleskxml_DBG 2 "About to exit API function. Result = ${_pleskxml_newline}'${_pleskxml_result}' "

  _pleskxml_DBG 2 'Successfully exiting Plesk XML API function'
  _pleskxml_DBG_VARDUMP 2

  return 0

}

_pleskxml_get_domain_ID() {

  _pleskxml_DBG 2 "Entered Plesk get_domain_ID($*), to get the domain's Plesk ID."

  # Call cURL to convert a domain name to a plesk domain ID.

  _pleskxml_DBG 2 'About to make API request (domain name -> domain ID)'

  _pleskxml_api_request "$_pleskxml_tplt_get_domain_id" "$1"
  _pleskxml_retcode=$?
  # $1 is the domain name we wish to convert to a Plesk domain ID

  _pleskxml_DBG 2 'Returned from API request, now back in get_domain_ID()'

  if [ $_pleskxml_retcode -ne 0 ] || [ "$_pleskxml_errors" != '' ] || [ "$_pleskxml_result" = '' ]; then
    # Really, just testing return code should be enough, based on above code, but let's go "all-in" and test all variables returned
    _err "$_pleskxml_errors"
    return 1
  fi

  # OK, we should have a domain ID. Let's check and return it if so.

  # Result should comprise precisely one <result> section

  _pleskxml_DBG 2 'Testing API return data for one <result> and removing if so'

  if printf '%s' "$_pleskxml_result" | grep -qiEv '^<result>.*</result>$'; then
    # Error - doesn't comprise <result>DOMAINNAME</result>. Something's wrong. Abort
    _pleskxml_errors='Error when querying Plesk XML API. The API did not comprise a <result> section containing all other data.\nThis is unexpected: something has gone wrong. Please raise this as a bug/issue in the module. The response was:\n'"$_pleskxml_prettyprint_result"'\nand the exact test string was:\n'"$_pleskxml_result"'\n'
    _err "$_pleskxml_errors"
    return 1
  elif printf '%s' "$_pleskxml_result" | grep -qiE '<result>.*<result>'; then
    # Error - contains <result>...</result>...<result>. Abort
    _pleskxml_errors='Error when querying Plesk XML API. The API contained more than one <result> section.\nThis is unexpected: something has gone wrong. Please raise this as a bug/issue in the module. The response was:\n'"$_pleskxml_prettyprint_result"'\nand the exact test string was:\n'"$_pleskxml_result"'\n'
    _err "$_pleskxml_errors"
    return 1
  else
    # So far so good. Remove the <result>...</result> section and continue
    _pleskxml_result="$(printf '%s' "$_pleskxml_result" \
      | sed -E 's/(^<result>|<\/result>$)//g'
    )"
  fi

  # Result should contain precisely one <filter-id> section, containing the domain name inquired.

  _pleskxml_DBG 2 'Testing API return data for one <filter-id> and removing if so'

  if printf '%s' "$_pleskxml_result" | grep -qiv "<filter-id>$1</filter-id>"; then
    # Error - doesn't contain <filter-id>DOMAINNAME</filter-id>. Something's wrong. Abort
    _pleskxml_errors='Error when querying Plesk XML API. The API did not contain the expected <filter-id> section containing the domain name.\nThis is unexpected: something has gone wrong. Please raise this as a bug/issue in the module. The response was:\n'"$_pleskxml_prettyprint_result"'\nand the exact test string was:\n'"$_pleskxml_result"'\n'
    _err "$_pleskxml_errors"
    return 1
  elif printf '%s' "$_pleskxml_result" | grep -qiE '<filter-id>.*<filter-id>'; then
    # Error - contains <filter-id>...</filter-id>...<filter-id>. Abort
    _pleskxml_errors='Error when querying Plesk XML API. The API contained more than one <filter-id> section.\nThis is unexpected: something has gone wrong. Please raise this as a bug/issue in the module. The response was:\n'"$_pleskxml_prettyprint_result"'\nand the exact test string was:\n'"$_pleskxml_result"'\n'
    _err "$_pleskxml_errors"
    return 1
  else
    # So far so good. Remove the <filter-id>...</filter-id> section and continue
    _pleskxml_result="$(printf '%s' "$_pleskxml_result" \
      | sed "s/<filter-id>$1<\/filter-id>//"
    )"
  fi

  # All that should be left is one section, containing <id>DOMAIN_ID</id>

  _pleskxml_DBG 2 "Remaining part of result is now: '$_pleskxml_result' "

  if printf '%s' "$_pleskxml_result" | grep -qiEv '^<id>[0-9]+</id>$'; then
    # Error - doesn't contain just <id>NUMBERS</id>. Something's wrong. Abort
    _pleskxml_errors='Error when querying Plesk XML API. The API did not contain the expected <id>[NUMERIC_ID]</id> section, or contained other unexpected values as well.\nThis is unexpected: something has gone wrong. Please raise this as a bug/issue in the module. The response was:\n'"$_pleskxml_prettyprint_result"'\nand the exact test string was:\n'"$_pleskxml_result"'\n'
    _err "$_pleskxml_errors"
    return 1
  fi

  # SUCCESS! Remove the surrounding <id> tag and return the value!

  _pleskxml_result="$(printf '%s' "$_pleskxml_result" \
    | sed -E 's/^<id>([0-9]+)<\/id>$/\1/'
  )"

  _pleskxml_domain_id="$_pleskxml_result"

  _pleskxml_DBG 2 'SUCCESSFULLY exiting Plesk get_domain_ID'
  _pleskxml_DBG_VARDUMP 2

  return 0

}

# 1st arg is the domain ID
# 2nd arg (optional) is the TYPE of arg(s) to keep
#   format = valid regex WITHOUT ^ or $, such as TXT, or (A|AAAA|CNAME)

_pleskxml_get_dns_records() {

  _pleskxml_DBG 2 "Entered Plesk _pleskxml_get_dns_records($*)"

  # First, we need to get all DNS records, and check the list is valid

  _pleskxml_DBG 2 'About to make API request (get DNS records)'

  _pleskxml_api_request "$_pleskxml_tplt_get_dns_records" "$1"
  _pleskxml_retcode=$?
  # $1 is the Plesk internal domain ID for the domain

  _pleskxml_DBG 2 'Returned from API request, now back in get_txt_records()'

  if [ $_pleskxml_retcode -ne 0 ] || [ "$_pleskxml_errors" != '' ] || [ "$_pleskxml_result" = '' ]; then
    # Really, just testing return code should be enough, based on above code, but let's go "all-in" and test all variables returned
    _err "$_pleskxml_errors"
    return 1
  fi

  # OK, we should have a <result> section containing a list of DNS records.
  # Now keep only the TXT records

  _pleskxml_DBG 2 "Full DNS records were:${_pleskxml_newline}${_pleskxml_newline}'${_pleskxml_result}' "

  if [ -n "${2:-}" ]; then
    _pleskxml_result="$(printf '%s' "$_pleskxml_result" \
      | grep "<type>$2</type>"
    )"
    _pleskxml_DBG 2 "Filtered relevant DNS records. Records to be returned are:${_pleskxml_newline}${_pleskxml_newline}'${_pleskxml_result}' "
  else
    _pleskxml_DBG 2 'Not filtering DNS records. All records will be returned.'
  fi

  _pleskxml_DBG 2 "SUCCESSFULLY exiting _pleskxml_get_dns_records"
  return 0
}

_pleskxml_add_txt_record() {

  _pleskxml_DBG 2 "Entered Plesk _pleskxml_add_txt_record($*)"

  _pleskxml_DBG 2 'About to make API request (add TXT record)'

  _pleskxml_api_request "$_pleskxml_tplt_add_txt_record" "$1" "$2" "$3"
  _pleskxml_retcode=$?

  # $1 is the Plesk internal domain ID for the domain
  # $2 is the "host" entry within the domain, to add this to (eg '_acme_challenge')
  # $3 is the TXT record value

  _pleskxml_DBG 2 'Returned from API request, now back in add_txt_record()'

  if [ $_pleskxml_retcode -ne 0 ] || [ "$_pleskxml_errors" != '' ] || [ "$_pleskxml_result" = '' ]; then
    # Really, just testing return code should be enough, based on above code, but let's go "all-in" and test all variables returned
    _err "$_pleskxml_errors"
    return 1
  fi

  # OK, we should have added a TXT record. Let's check and return success if so.
  # All that should be left in the result, is one section, containing <result><id>PLESK_NEW_DNS_RECORD_ID</id></result>

  if printf '%s' "$_pleskxml_result" | grep -qivE '^<result><id>[0-9]+</id></result>$'; then
    # Error - doesn't contain just <id>NUMBERS</id>. Something's wrong. Abort
    _pleskxml_errors='Error when calling Plesk XML API. The API did not contain the expected <id>[PLESK_NEW_DNS_RECORD_ID]</id> section, or contained other unexpected values as well.\nThis is unexpected: something has gone wrong. Please raise this as a bug/issue in the module. The response was:\n'"$_pleskxml_prettyprint_result"'\nand the exact test string was:\n'"$_pleskxml_result"'\n'
    _err "$_pleskxml_errors"
    return 1
  fi

  # SUCCESS! Remove the surrounding <result><id> tags and return the value!
  # (although we don't actually use it!

  _pleskxml_result="$(printf '%s' "$_pleskxml_result" \
    | sed -E "s/^<result><id>([0-9]+)<\/id><\/result>$/\1/"
  )"

  _pleskxml_DBG 2 'SUCCESSFULLY exiting Plesk _pleskxml_add_txt_record'
  _pleskxml_DBG_VARDUMP 2

  return 0
}

_pleskxml_rmv_dns_record() {

  _pleskxml_DBG 2 "Entered Plesk _pleskxml_rmv_dns_record($*)"

  _pleskxml_DBG 2 'About to make API request (rmv TXT record)'

  _pleskxml_api_request "$_pleskxml_tplt_rmv_dns_record" "$1"
  _pleskxml_retcode=$?

  # $1 is the Plesk internal domain ID for the TXT record

  _pleskxml_DBG 2 'Returned from API request, now back in rmv_dns_record()'

  if [ $_pleskxml_retcode -ne 0 ] || [ "$_pleskxml_errors" != '' ] || [ "$_pleskxml_result" = '' ]; then
    # Really, just testing return code should be enough, based on above code, but let's go "all-in" and test all variables returned
    _err "$_pleskxml_errors"
    return 1
  fi

  # OK, we should have removed a TXT record. If it failed, there wouldn't have been a "status:ok" above

  _pleskxml_DBG 2 'SUCCESSFULLY exiting Plesk _pleskxml_rmv_dns_record'
  _pleskxml_DBG_VARDUMP 2

  return 0
}

# 1st arg = domain ID
# 2nd arg = host that the record exists for
# 3rd arg = value of TXT record string to be found and removed
_pleskxml_rmv_txt_record() {

  _pleskxml_DBG 2 "Entered Plesk _pleskxml_rmv_dns_TXT_record($*). Getting DNS TXT records for the domain ID"

  _pleskxml_get_dns_records "$1" 'TXT'
  _pleskxml_retcode=$?
  # $1 is the Plesk internal domain ID for the domain

  _pleskxml_DBG 2 'Returned from API request, now back in rmv_txt_record()'

  if [ $_pleskxml_retcode -ne 0 ] || [ "$_pleskxml_errors" != '' ] || [ "$_pleskxml_result" = '' ]; then
    # Really, just testing return code should be enough, based on above code, but let's go "all-in" and test all variables returned
    _err "$_pleskxml_errors"
    return 1
  fi

  # OK, we should have a <result> section containing a list of DNS TXT records.
  # Now we need to find our desired record in it (if it exists).
  # and might as well collapse any successful matches to a single line for line-count purposes at the same time

  _pleskxml_DBG 2 "Filters to apply (as literal strings):${_pleskxml_newline}'<host>${2:-<NON_MATCHING_GARBAGE>}.'${_pleskxml_newline}'<value>${3:-<NON_MATCHING_GARBAGE>}</value>' "

  _pleskxml_result="$(printf '%s' "$_pleskxml_result" \
    | grep -F "<host>${2:-<NON_MATCHING_GARBAGE>}." \
    | grep -F "<value>${3:-<NON_MATCHING_GARBAGE>}</value>" \
    | sed -E 's/(^[[:space:]]+|[[:space:]]+$)//g' \
    | tr -d '\n'
  )"
  # Run 2 separate GREP filters, because the host and value order isn't mandatory in the API return data
  # ands this avoids regex and escaping which is easier
  # NOTE: the returned "host" field is actually the FQDN, not just the host ID, hence the grep match on that field.

  _pleskxml_DBG 2 "Filtered result:${_pleskxml_newline}'$_pleskxml_result' "

  if printf '%s' "$_pleskxml_result" | grep -qiE "<result>.*<result>"; then
    # Error - contains <result>...</result>...<result>. Abort
    _pleskxml_errors='Error when querying Plesk XML API. The API contained more than one <result> section.\nThis is unexpected: something has gone wrong. Please raise this as a bug/issue in the module. The response was:\n'"$_pleskxml_prettyprint_result"'\nand the exact test string was:\n'"$_pleskxml_result"'\n'
    _err "$_pleskxml_errors"
    return 1
  fi

  if printf '%s\n' "$_pleskxml_result" | grep -qiv "<result>"; then
    # No matching TXT records, so we're done.
    _info "Couldn't find a TXT record matching the requested host/value. Not an error, but a concern..."
    _pleskxml_DBG 2 "Exiting Plesk _pleskxml_rmv_txt_record (without raising an error), as nothing more to do: the record requested for deletion doesn't exist"
    _pleskxml_result=''
    return 0
  fi

  # If we get here, there was a single TXT record match, so we delete it.

  _pleskxml_result="$(printf '%s' "$_pleskxml_result" \
    | sed -E 's/^.*<id>([0-9]+)<\/id>.*$/\1/'
  )"

  _pleskxml_DBG 2 "A unique matching DNS TXT record was found, with Plesk record ID = '$_pleskxml_result'. Calling API to delete this record."

  _pleskxml_rmv_dns_record "$_pleskxml_result"
  _pleskxml_retcode=$?

  _pleskxml_DBG 2 'Returned from API request, now back in rmv_txt_record()'

  if [ $_pleskxml_retcode -ne 0 ] || [ "$_pleskxml_errors" != '' ] || [ "$_pleskxml_result" = '' ]; then
    # Really, just testing return code should be enough, based on above code, but let's go "all-in" and test all variables returned
    _err "$_pleskxml_errors"
    return 1
  fi

  _pleskxml_DBG 2 'SUCCESSFULLY exiting Plesk _pleskxml_rmv_txt_record'
  _pleskxml_DBG_VARDUMP 2

  return 0
}

if false; then

  # ---------------------- TEST CODE ------------------------------

  # defined by user
  pleskxml_uri="https://plesk.XXXXX.net:8443/enterprise/control/agent.php"
  pleskxml_user="XXXXX"
  pleskxml_pass="XXXXX"
  pleskxml_debug_min_level=3

  # defined from args by module
  _pleskxml_FQDN="_acme_challenge.XXXXX.com"
  _pleskxml_TXT_string='~test~string~'

  printf '\n\n\n\n======================================================================== START OF RUN\n\n'

  _info 'Checking debug mode...'

  _pleskxml_DBG_EARLY_CHECK_MODE

  _pleskxml_DBG 3 'Debug mode done. Now testing _pleskxml_get_variables()'

  _pleskxml_get_variables
  _pleskxml_DBG 3 "$(printf 'RESULT:\n  _pleskxml_errors: "%s"\n  _pleskxml_retcode: "%s"\n  _pleskxml_result: "%s"\n\n' "$_pleskxml_errors" "$_pleskxml_retcode" "$_pleskxml_result")"
  _pleskxml_DBG_VARDUMP 3

  _pleskxml_DBG 3 '==============================================================='

  _pleskxml_DBG 3 'Testing _pleskxml_get_domain_ID()'
  _pleskxml_get_domain_ID "atticflat.uk"

  _pleskxml_DBG 3 "$(printf 'RESULT:\n  _pleskxml_errors: "%s"\n  _pleskxml_retcode: "%s"\n  _pleskxml_result: "%s"\n\n' "$_pleskxml_errors" "$_pleskxml_retcode" "$_pleskxml_result")"
  _pleskxml_DBG_VARDUMP 3

  _pleskxml_DBG 3 '==============================================================='

  test_string="TEST STRING ADDED @ $(date)"

  _pleskxml_DBG 3 "Testing add a TXT string: '$test_string' "
  _pleskxml_add_txt_record 874 '_test_subdomain' "$test_string"

  _pleskxml_DBG 3 "$(printf 'RESULT:\n  _pleskxml_errors: "%s"\n  _pleskxml_retcode: "%s"\n  _pleskxml_result: "%s"\n\n' "$_pleskxml_errors" "$_pleskxml_retcode" "$_pleskxml_result")"
  _pleskxml_DBG_VARDUMP 3

  _pleskxml_DBG 3 '==============================================================='

  _pleskxml_DBG 3 'Testing get DNS records (ALL)'
  _pleskxml_get_dns_records 874

  _pleskxml_DBG 3 "$(printf 'RESULT:\n  _pleskxml_errors: "%s"\n  _pleskxml_retcode: "%s"\n  _pleskxml_result: "%s"\n\n' "$_pleskxml_errors" "$_pleskxml_retcode" "$_pleskxml_result")"
  _pleskxml_DBG_VARDUMP 3

  _pleskxml_DBG 3 '==============================================================='

  _pleskxml_DBG 3 'Testing get DNS records (TXT ONLY)'
  _pleskxml_get_dns_records 874 TXT

  _pleskxml_DBG 3 "$(printf 'RESULT:\n  _pleskxml_errors: "%s"\n  _pleskxml_retcode: "%s"\n  _pleskxml_result: "%s"\n\n' "$_pleskxml_errors" "$_pleskxml_retcode" "$_pleskxml_result")"
  _pleskxml_DBG_VARDUMP 3

  _pleskxml_DBG 3 '==============================================================='

  _pleskxml_DBG 3 'Testing rmv a TXT string'
  _pleskxml_rmv_txt_record 874 '_test_subdomain' "$test_string"

  _pleskxml_DBG 3 "$(printf 'RESULT:\n  _pleskxml_errors: "%s"\n  _pleskxml_retcode: "%s"\n  _pleskxml_result: "%s"\n\n' "$_pleskxml_errors" "$_pleskxml_retcode" "$_pleskxml_result")"
  _pleskxml_DBG_VARDUMP 3

  _pleskxml_DBG 3 '==============================================================='

  _pleskxml_DBG 3 'Re-testing get DNS records (TXT ONLY) after TXT string removal'
  _pleskxml_get_dns_records 874 TXT

  _pleskxml_DBG 3 "$(printf 'RESULT:\n  _pleskxml_errors: "%s"\n  _pleskxml_retcode: "%s"\n  _pleskxml_result: "%s"\n\n' "$_pleskxml_errors" "$_pleskxml_retcode" "$_pleskxml_result")"
  _pleskxml_DBG_VARDUMP 3

  _pleskxml_DBG 3 '==============================================================='

  _pleskxml_DBG 3 'Testing rmv a TXT string, with a non-matching string'
  _pleskxml_rmv_txt_record 874 '_test_subdomain' 'JUNKegqw4bw4bb2'

  _pleskxml_DBG 3 "$(printf 'RESULT:\n  _pleskxml_errors: "%s"\n  _pleskxml_retcode: "%s"\n  _pleskxml_result: "%s"\n\n' "$_pleskxml_errors" "$_pleskxml_retcode" "$_pleskxml_result")"
  _pleskxml_DBG_VARDUMP 3

  _pleskxml_DBG 3 '=============================================================== END OF RUN'

fi

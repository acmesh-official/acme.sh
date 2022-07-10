#!/usr/bin/env sh

##  Name: dns_pleskxml.sh
##  Created by Stilez.
##  Also uses some code from PR#1832 by @romanlum (https://github.com/acmesh-official/acme.sh/pull/1832/files)

##  This DNS-01 method uses the Plesk XML API described at:
##  https://docs.plesk.com/en-US/12.5/api-rpc/about-xml-api.28709
##  and more specifically: https://docs.plesk.com/en-US/12.5/api-rpc/reference.28784

##  Note: a DNS ID with host = empty string is OK for this API, see
##  https://docs.plesk.com/en-US/obsidian/api-rpc/about-xml-api/reference/managing-dns/managing-dns-records/adding-dns-record.34798
##  For example, to add a TXT record to DNS alias domain "acme-alias.com" would be a valid Plesk action.
##  So this API module can handle such a request, if needed.

##  For ACME v2 purposes, new TXT records are appended when added, and removing one TXT record will not affect any other TXT records.

##  The user credentials (username+password) and URL/URI for the Plesk XML API must be set by the user
##  before this module is called (case sensitive):
##
##  ```
##  export pleskxml_uri="https://address-of-my-plesk-server.net:8443/enterprise/control/agent.php"
##          (or probably something similar)
##  export pleskxml_user="my plesk username"
##  export pleskxml_pass="my plesk password"
##  ```

##  Ok, let's issue a cert now:
##  ```
##  acme.sh --issue --dns dns_pleskxml -d example.com -d www.example.com
##  ```
##
##  The `pleskxml_uri`, `pleskxml_user` and `pleskxml_pass` will be saved in `~/.acme.sh/account.conf` and reused when needed.

####################  INTERNAL VARIABLES + NEWLINE + API TEMPLATES ##################################

pleskxml_init_checks_done=0

# Variable containing bare newline - not a style issue
# shellcheck disable=SC1004
NEWLINE='\
'

pleskxml_tplt_get_domains="<packet><webspace><get><filter/><dataset><gen_info/></dataset></get></webspace></packet>"
# Get a list of domains that PLESK can manage, so we can check root domain + host for acme.sh
# Also used to test credentials and URI.
# No params.

pleskxml_tplt_get_dns_records="<packet><dns><get_rec><filter><site-id>%s</site-id></filter></get_rec></dns></packet>"
# Get all DNS records for a Plesk domain ID.
# PARAM = Plesk domain id to query

pleskxml_tplt_add_txt_record="<packet><dns><add_rec><site-id>%s</site-id><type>TXT</type><host>%s</host><value>%s</value></add_rec></dns></packet>"
# Add a TXT record to a domain.
# PARAMS = (1) Plesk internal domain ID, (2) "hostname" for the new record, eg '_acme_challenge', (3) TXT record value

pleskxml_tplt_rmv_dns_record="<packet><dns><del_rec><filter><id>%s</id></filter></del_rec></dns></packet>"
# Delete a specific TXT record from a domain.
# PARAM = the Plesk internal ID for the DNS record to be deleted

####################  Public functions ##################################

#Usage: dns_pleskxml_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_pleskxml_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Entering dns_pleskxml_add() to add TXT record '$txtvalue' to domain '$fulldomain'..."

  # Get credentials if not already checked, and confirm we can log in to Plesk XML API
  if ! _credential_check; then
    return 1
  fi

  # Get root and subdomain details, and Plesk domain ID
  if ! _pleskxml_get_root_domain "$fulldomain"; then
    return 1
  fi

  _debug 'Credentials OK, and domain identified. Calling Plesk XML API to add TXT record'

  # printf using template in a variable - not a style issue
  # shellcheck disable=SC2059
  request="$(printf "$pleskxml_tplt_add_txt_record" "$root_domain_id" "$sub_domain_name" "$txtvalue")"
  if ! _call_api "$request"; then
    return 1
  fi

  # OK, we should have added a TXT record. Let's check and return success if so.
  # All that should be left in the result, is one section, containing <result><status>ok</status><id>NEW_DNS_RECORD_ID</id></result>

  results="$(_api_response_split "$pleskxml_prettyprint_result" 'result' '<status>')"

  if ! _value "$results" | grep '<status>ok</status>' | grep '<id>[0-9]\{1,\}</id>' >/dev/null; then
    # Error - doesn't contain expected string. Something's wrong.
    _err 'Error when calling Plesk XML API.'
    _err 'The result did not contain the expected <id>XXXXX</id> section, or contained other values as well.'
    _err 'This is unexpected: something has gone wrong.'
    _err 'The full response was:'
    _err "$pleskxml_prettyprint_result"
    return 1
  fi

  recid="$(_value "$results" | grep '<id>[0-9]\{1,\}</id>' | sed 's/^.*<id>\([0-9]\{1,\}\)<\/id>.*$/\1/')"

  _info "Success. TXT record appears to be correctly added (Plesk record ID=$recid). Exiting dns_pleskxml_add()."

  return 0
}

#Usage: dns_pleskxml_rm   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_pleskxml_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "Entering dns_pleskxml_rm() to remove TXT record '$txtvalue' from domain '$fulldomain'..."

  # Get credentials if not already checked, and confirm we can log in to Plesk XML API
  if ! _credential_check; then
    return 1
  fi

  # Get root and subdomain details, and Plesk domain ID
  if ! _pleskxml_get_root_domain "$fulldomain"; then
    return 1
  fi

  _debug 'Credentials OK, and domain identified. Calling Plesk XML API to get list of TXT records and their IDs'

  # printf using template in a variable - not a style issue
  # shellcheck disable=SC2059
  request="$(printf "$pleskxml_tplt_get_dns_records" "$root_domain_id")"
  if ! _call_api "$request"; then
    return 1
  fi

  # Reduce output to one line per DNS record, filtered for TXT records with a record ID only (which they should all have)
  # Also strip out spaces between tags, redundant <data> and </data> group tags and any <self-closing/> tags
  reclist="$(
    _api_response_split "$pleskxml_prettyprint_result" 'result' '<status>ok</status>' |
      sed 's# \{1,\}<\([a-zA-Z]\)#<\1#g;s#</\{0,1\}data>##g;s#<[a-z][^/<>]*/>##g' |
      grep "<site-id>${root_domain_id}</site-id>" |
      grep '<id>[0-9]\{1,\}</id>' |
      grep '<type>TXT</type>'
  )"

  if [ -z "$reclist" ]; then
    _err "No TXT records found for root domain $fulldomain (Plesk domain ID ${root_domain_id}). Exiting."
    return 1
  fi

  _debug "Got list of DNS TXT records for root Plesk domain ID ${root_domain_id} of root domain $fulldomain:"
  _debug "$reclist"

  # Extracting the id of the TXT record for the full domain (NOT case-sensitive) and corresponding value
  recid="$(
    _value "$reclist" |
      grep -i "<host>${fulldomain}.</host>" |
      grep "<value>${txtvalue}</value>" |
      sed 's/^.*<id>\([0-9]\{1,\}\)<\/id>.*$/\1/'
  )"

  _debug "Got id from line: $recid"

  if ! _value "$recid" | grep '^[0-9]\{1,\}$' >/dev/null; then
    _err "DNS records for root domain '${fulldomain}.' (Plesk ID ${root_domain_id}) + host '${sub_domain_name}' do not contain the TXT record '${txtvalue}'"
    _err "Cannot delete TXT record. Exiting."
    return 1
  fi

  _debug "Found Plesk record ID for target text string '${txtvalue}': ID=${recid}"
  _debug 'Calling Plesk XML API to remove TXT record'

  # printf using template in a variable - not a style issue
  # shellcheck disable=SC2059
  request="$(printf "$pleskxml_tplt_rmv_dns_record" "$recid")"
  if ! _call_api "$request"; then
    return 1
  fi

  # OK, we should have removed a TXT record. Let's check and return success if so.
  # All that should be left in the result, is one section, containing <result><status>ok</status><id>PLESK_DELETED_DNS_RECORD_ID</id></result>

  results="$(_api_response_split "$pleskxml_prettyprint_result" 'result' '<status>')"

  if ! _value "$results" | grep '<status>ok</status>' | grep '<id>[0-9]\{1,\}</id>' >/dev/null; then
    # Error - doesn't contain expected string. Something's wrong.
    _err 'Error when calling Plesk XML API.'
    _err 'The result did not contain the expected <id>XXXXX</id> section, or contained other values as well.'
    _err 'This is unexpected: something has gone wrong.'
    _err 'The full response was:'
    _err "$pleskxml_prettyprint_result"
    return 1
  fi

  _info "Success. TXT record appears to be correctly removed. Exiting dns_pleskxml_rm()."
  return 0
}

####################  Private functions below (utility functions) ##################################

# Outputs value of a variable without additional newlines etc
_value() {
  printf '%s' "$1"
}

# Outputs value of a variable (FQDN) and cuts it at 2 specified '.' delimiters, returning the text in between
# $1, $2 = where to cut
# $3 = FQDN
_valuecut() {
  printf '%s' "$3" | cut -d . -f "${1}-${2}"
}

# Counts '.' present in a domain name or other string
# $1 = domain name
_countdots() {
  _value "$1" | tr -dc '.' | wc -c | sed 's/ //g'
}

# Cleans up an API response, splits it "one line per item in the response" and greps for a string that in the context, identifies "useful" lines
# $1 - result string from API
# $2 - plain text tag to resplit on (usually "result" or "domain"). NOT REGEX
# $3 - basic regex to recognise useful return lines
# note: $3 matches via basic NOT extended regex (BRE), as extended regex capabilities not needed at the moment.
#       Last line could change to <sed -n '/.../p'> instead, with suitable escaping of ['"/$],
#       if future Plesk XML API changes ever require extended regex
_api_response_split() {
  printf '%s' "$1" |
    sed 's/^ +//;s/ +$//' |
    tr -d '\n\r' |
    sed "s/<\/\{0,1\}$2>/${NEWLINE}/g" |
    grep "$3"
}

####################  Private functions below (DNS functions) ##################################

# Calls Plesk XML API, and checks results for obvious issues
_call_api() {
  request="$1"
  errtext=''

  _debug 'Entered _call_api(). Calling Plesk XML API with request:'
  _debug "'$request'"

  export _H1="HTTP_AUTH_LOGIN: $pleskxml_user"
  export _H2="HTTP_AUTH_PASSWD: $pleskxml_pass"
  export _H3="content-Type: text/xml"
  export _H4="HTTP_PRETTY_PRINT: true"
  pleskxml_prettyprint_result="$(_post "${request}" "$pleskxml_uri" "" "POST")"
  pleskxml_retcode="$?"
  _debug 'The responses from the Plesk XML server were:'
  _debug "retcode=$pleskxml_retcode. Literal response:"
  _debug "'$pleskxml_prettyprint_result'"

  # Detect any <status> that isn't "ok". None of the used calls should fail if the API is working correctly.
  # Also detect if there simply aren't any status lines (null result?) and report that, as well.
  # Remove <data></data> structure from result string, since it might contain <status> values that are related to the status of the domain and not to the API request

  statuslines_count_total="$(echo "$pleskxml_prettyprint_result" | sed '/<data>/,/<\/data>/d' | grep -c '^ *<status>[^<]*</status> *$')"
  statuslines_count_okay="$(echo "$pleskxml_prettyprint_result" | sed '/<data>/,/<\/data>/d' | grep -c '^ *<status>ok</status> *$')"
  _debug "statuslines_count_total=$statuslines_count_total."
  _debug "statuslines_count_okay=$statuslines_count_okay."

  if [ -z "$statuslines_count_total" ]; then

    # We have no status lines at all. Results are empty
    errtext='The Plesk XML API unexpectedly returned an empty set of results for this call.'

  elif [ "$statuslines_count_okay" -ne "$statuslines_count_total" ]; then

    # We have some status lines that aren't "ok". Any available details are in API response fields "status" "errcode" and "errtext"
    # Workaround for basic regex:
    #   - filter output to keep only lines like this: "SPACES<TAG>text</TAG>SPACES" (shouldn't be necessary with prettyprint but guarantees subsequent code is ok)
    #   - then edit the 3 "useful" error tokens individually and remove closing tags on all lines
    #   - then filter again to remove all lines not edited (which will be the lines not starting A-Z)
    errtext="$(
      _value "$pleskxml_prettyprint_result" |
        grep '^ *<[a-z]\{1,\}>[^<]*<\/[a-z]\{1,\}> *$' |
        sed 's/^ *<status>/Status:     /;s/^ *<errcode>/Error code: /;s/^ *<errtext>/Error text: /;s/<\/.*$//' |
        grep '^[A-Z]'
    )"

  fi

  if [ "$pleskxml_retcode" -ne 0 ] || [ "$errtext" != "" ]; then
    # Call failed, for reasons either in the retcode or the response text...

    if [ "$pleskxml_retcode" -eq 0 ]; then
      _err "The POST request was successfully sent to the Plesk server."
    else
      _err "The return code for the POST request was $pleskxml_retcode (non-zero = failure in submitting request to server)."
    fi

    if [ "$errtext" != "" ]; then
      _err 'The error responses received from the Plesk server were:'
      _err "$errtext"
    else
      _err "No additional error messages were received back from the Plesk server"
    fi

    _err "The Plesk XML API call failed."
    return 1

  fi

  _debug "Leaving _call_api(). Successful call."

  return 0
}

# Startup checks (credentials, URI)
_credential_check() {
  _debug "Checking Plesk XML API login credentials and URI..."

  if [ "$pleskxml_init_checks_done" -eq 1 ]; then
    _debug "Initial checks already done, no need to repeat. Skipped."
    return 0
  fi

  pleskxml_user="${pleskxml_user:-$(_readaccountconf_mutable pleskxml_user)}"
  pleskxml_pass="${pleskxml_pass:-$(_readaccountconf_mutable pleskxml_pass)}"
  pleskxml_uri="${pleskxml_uri:-$(_readaccountconf_mutable pleskxml_uri)}"

  if [ -z "$pleskxml_user" ] || [ -z "$pleskxml_pass" ] || [ -z "$pleskxml_uri" ]; then
    pleskxml_user=""
    pleskxml_pass=""
    pleskxml_uri=""
    _err "You didn't specify one or more of the Plesk XML API username, password, or URI."
    _err "Please create these and try again."
    _err "Instructions are in the 'dns_pleskxml' plugin source code or in the acme.sh documentation."
    return 1
  fi

  # Test the API is usable, by trying to read the list of managed domains...
  _call_api "$pleskxml_tplt_get_domains"
  if [ "$pleskxml_retcode" -ne 0 ]; then
    _err 'Failed to access Plesk XML API.'
    _err "Please check your login credentials and Plesk URI, and that the URI is reachable, and try again."
    return 1
  fi

  _saveaccountconf_mutable pleskxml_uri "$pleskxml_uri"
  _saveaccountconf_mutable pleskxml_user "$pleskxml_user"
  _saveaccountconf_mutable pleskxml_pass "$pleskxml_pass"

  _debug "Test login to Plesk XML API successful. Login credentials and URI successfully saved to the acme.sh configuration file for future use."

  pleskxml_init_checks_done=1

  return 0
}

# For a FQDN, identify the root domain managed by Plesk, its domain ID in Plesk, and the host if any.

# IMPORTANT NOTE:  a result with host = empty string is OK for this API, see
# https://docs.plesk.com/en-US/obsidian/api-rpc/about-xml-api/reference/managing-dns/managing-dns-records/adding-dns-record.34798
# See notes at top of this file

_pleskxml_get_root_domain() {
  original_full_domain_name="$1"

  _debug "Identifying DNS root domain for '$original_full_domain_name' that is managed by the Plesk account."

  # test if the domain as provided is valid for splitting.

  if [ "$(_countdots "$original_full_domain_name")" -eq 0 ]; then
    _err "Invalid domain. The ACME domain must contain at least two parts (aa.bb) to identify a domain and tld for the TXT record."
    return 1
  fi

  _debug "Querying Plesk server for list of managed domains..."

  _call_api "$pleskxml_tplt_get_domains"
  if [ "$pleskxml_retcode" -ne 0 ]; then
    return 1
  fi

  # Generate a crude list of domains known to this Plesk account.
  # We convert <ascii-name> tags to <name> so it'll flag on a hit with either <name> or <ascii-name> fields,
  # for non-Western character sets.
  # Output will be one line per known domain, containing 2 <name> tages and a single <id> tag
  # We don't actually need to check for type, name, *and* id, but it guarantees only usable lines are returned.

  output="$(_api_response_split "$pleskxml_prettyprint_result" 'result' '<status>ok</status>' | sed 's/<ascii-name>/<name>/g;s/<\/ascii-name>/<\/name>/g' | grep '<name>' | grep '<id>')"

  _debug 'Domains managed by Plesk server are (ignore the hacked output):'
  _debug "$output"

  # loop and test if domain, or any parent domain, is managed by Plesk
  # Loop until we don't have any '.' in the string we're testing as a candidate Plesk-managed domain

  root_domain_name="$original_full_domain_name"

  while true; do

    _debug "Checking if '$root_domain_name' is managed by the Plesk server..."

    root_domain_id="$(_value "$output" | grep "<name>$root_domain_name</name>" | _head_n 1 | sed 's/^.*<id>\([0-9]\{1,\}\)<\/id>.*$/\1/')"

    if [ -n "$root_domain_id" ]; then
      # Found a match
      # SEE IMPORTANT NOTE ABOVE - THIS FUNCTION CAN RETURN HOST='', AND THAT'S OK FOR PLESK XML API WHICH ALLOWS IT.
      # SO WE HANDLE IT AND DON'T PREVENT IT
      sub_domain_name="$(_value "$original_full_domain_name" | sed "s/\.\{0,1\}${root_domain_name}"'$//')"
      _info "Success. Matched host '$original_full_domain_name' to: DOMAIN '${root_domain_name}' (Plesk ID '${root_domain_id}'), HOST '${sub_domain_name}'. Returning."
      return 0
    fi

    # No match, try next parent up (if any)...

    root_domain_name="$(_valuecut 2 1000 "$root_domain_name")"

    if [ "$(_countdots "$root_domain_name")" -eq 0 ]; then
      _debug "No match, and next parent would be a TLD..."
      _err "Cannot find '$original_full_domain_name' or any parent domain of it, in Plesk."
      _err "Are you sure that this domain is managed by this Plesk server?"
      return 1
    fi

    _debug "No match, trying next parent up..."

  done
}

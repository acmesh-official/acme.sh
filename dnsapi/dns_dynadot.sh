#!/usr/bin/env sh
#
# Author: Daniel Harp
#
# ## PLEASE READ THE WARNINGS AND ISSUES BELOW BEFORE USING THIS SCRIPT.  These were based on the dynadot api
#   current as of FEB-26-2023
#
# WARNING #1: During development, significant issues were experienced utilizing the dynadot apis to implement
#   the acme protocol, to the extent that the acme.sh automated test scripts could not repeatably and
#   reliably complete successfully, as explained below.  If you are attempting to create a single certificate
#   for a single domain, this will likely work well.  A single wildcard certificate is likely to work most
#   of the time.  As the number of certificates requested under a single primary domain go up, the highly
#   likelihood becomes that failures will be experienced.  Please read through these issues and the settings
#   available to mitigate these issues.
#
# WARNING #2: The dynadot api only allows "GET" requests.  Your api token will be passed as a URL parameter.
#   While this doesn't inherently expose risk, this is not following security best practices as often end
#   up in server logs.  There is currently no other option to interact with the dynadot api.
#
# API Issues:
#   Dynadot did not provide an api call to add or remove a specific subdomain, rather they provided a "set_dns2"
#   command that updates the entire domain configuration.  That command does have an "append" option, but when
#   attempting to use it in the append mode, it still required a main domain record to be added or the API
#   would reject the request.  As only TXT records for subdomains need to be appended, the append mode could
#   not be used.
#
#   To utilize the "set_dns2" command, without using the append mode, the entire domain configuration had to be
#   provided.  To add a TXT record, the current configuration was read, the new TXT record was added to that
#   configuration, then the entire configuration was sent to the set_dns2 api call, resulting in the added record.
#   Deleting a record is this same process: read config, delete specific TXT record, send the entire configuration.
#
#   The problem with sending the entire configuration rather than being able to append a single record is the
#   propogation of the transactions now must complete in order.  For instance if the domain currently only has a
#   single A record, and we need to add two text records( TXT1 & TXT2 ) the first "set_dns2" call will send a
#   configuration with the A record and the first TXT record, call_1=(A, TXT1).  The second add call sends a
#   configuration that contains all three records, call2=(A, TXT1, TXT2).  As these proprogate through the dynadot
#   system, if any part of the system applies call_2 first, it will have all three records, but then when it
#   processes call_1, it will end up dropping TXT2 as it applies it as the entire configuration.
#
#   To work reliably, after applying ANY change (add or remove) to a domain, you must wait for the change to
#   propogate through their system entirely prior to applying any new or additional change.  This was observed
#   behavior, not anything documented or provided by dynadot.
#
#   The acme.sh --dnssleep does not do this.  If multiple TXT records are required it will call add twice serially
#   without waiting, then will apply the sleep before verification.  It also does not sleep after a remove.  This
#   means moving on to additional certificates (or as observed moving on to the next set of test cases) can cause
#   problems as the remove has not fully propogated.  Two options are available:
#   export DYNADOT_ADD_DNS_SLEEP=1800
#   export DYNADOT_REMOVE_DNS_SLEEP=1800
#   These are sleep times, in seconds, that will be applied immediately after EVERY ADD or REMOVE.
#   If you are only requesting one certificate, you likely do not need the wait after the remove. If you are running
#   any more DNS updates/changes to the domain after the script runs, you do need this wait to ensure it completes
#   first.
#   Note that for a wildcard certificate, two text records are added.  DYNADOT_ADD_DNS_SLEEP is applied after each
#   so the total wait before verification will be doubled.
#   Dynadot notes that propogation times can range from 5 minutes to 48 hours!!!  30 minutes (1800 second) waits
#   appeared to consistently be sufficient.  Sleep times 15 minutes or less were found to consistently cause
#   failures in the tests.
#   The "docker" test stage runs through 8 different linux containers, with at least 2 adds and 2 removes for each.
#   That's at least 32 "set_dns2" calls.  At 30 minutes for propogation for each, that's 16 hours of just sleep time.
#   An additional option was then added:
#   export DYNADOTAPI_SKIP_REMOVE=SKIP
#   This option skips the removals, allowing one to clean up the TXT records by hand later, but in doing so cuts the
#   number of necessary operations for the tests in half.  Unfortunately, that's only down to 8 hours, and GitHub
#   aborts the process at 6 hours, so a successful test run was never completed.
#
#   An additional issue arose with periodic failures from the dynadot api:
#   {"ListDomainInfoResponse":{"ResponseCode":"-1","Status":"error","Error":"problem with connection to main server"}}
#   This error was reported to dynadot support. The response received was:
#   "sometimes we are maintaining main server so you will see such errors like connection issue. Just try again in a
#   few minutes."
#
#   To accomodate this error, two additional configuration options were added:
#   export DYNADOTAPI_API_RETRIES=5
#   export DYNADOTAPI_RETRY_SLEEP=60
#   On seeing an error from the dynadot api, up to $DYNADOTAPI_API_RETRIES attempts will be made before giving up.
#   DYNADOTAPI_RETRY_SLEEP specifies the number of seconds to wait between attempts.
#   However, when seeing this error, it consistently lasted longer than the wait time specified, so these two options
#   never accomplished their goal.  Instead a new test run would be attemped hours later (or the next day/night
#   altogether).
#
# Usage:
#  Create a dynadot api key under the web portal "Tools > API" and export that for this script:
# export DYNADOTAPI_Token="ASDF1234ASDF1234"
#
# export DYNADOT_ADD_DNS_SLEEP=1800    (optional) Default:empty. Recommended value: at least 1800.
# export DYNADOT_REMOVE_DNS_SLEEP=1800 (optional) Default:empty. Recommended:
#    If only a single domain certificate will be requested, this may be left blank.
#    If requesting multiple certificates, recommended setting is at least 1800, or use DYNADOTAPI_SKIP_REMOVE
#
# export DYNADOTAPI_SKIP_REMOVE=SKIP (optional)  Recommended if multiple certificates will be requested to reduce the
#    number of api calls required (but TXT records will need to be removed manually).
#
#  The following two options are available but are not recommended as they did not prove useful during testing.
# export DYNADOTAPI_API_RETRIES=1 (optional) Number of times to attempt Dynadot API call until success (default=1)
# export DYNADOTAPI_RETRY_SLEEP=30 (optional) Seconds to sleep between retry attempts (default: 30 seconds)
#

DYNADOT_Api=https://api.dynadot.com/api3.json

########  Public functions #####################

#Usage: dns_dynadot_add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dynadot_add() {
  fulldomain=$1
  txtvalue=$2
  _info "DYNADOT: Adding TXT Record"
  _debug "DYNADOT: fulldomain: $fulldomain"
  _debug "DYNADOT: txtvalue: $txtvalue"

  DYNADOTAPI_Token="${DYNADOTAPI_Token:-$(_readaccountconf_mutable DYNADOTAPI_Token)}"
  if [ -z "$DYNADOTAPI_Token" ]; then
    _err "You don't specify dynadot api token key."
    _err "Please create your token and try again."
    return 1
  fi
  _saveaccountconf_mutable DYNADOTAPI_Token "$DYNADOTAPI_Token"

  DYNADOTAPI_API_RETRIES="${DYNADOTAPI_API_RETRIES:-$(_readaccountconf_mutable DYNADOTAPI_API_RETRIES)}"
  if [ -z "$DYNADOTAPI_API_RETRIES" ]; then
    DYNADOTAPI_API_RETRIES=1
  fi
  _saveaccountconf_mutable DYNADOTAPI_API_RETRIES "$DYNADOTAPI_API_RETRIES"

  DYNADOTAPI_RETRY_SLEEP="${DYNADOTAPI_RETRY_SLEEP:-$(_readaccountconf_mutable DYNADOTAPI_RETRY_SLEEP)}"
  if [ -z "$DYNADOTAPI_RETRY_SLEEP" ]; then
    DYNADOTAPI_RETRY_SLEEP=30
  fi
  _saveaccountconf_mutable DYNADOTAPI_RETRY_SLEEP "$DYNADOTAPI_RETRY_SLEEP"

  DYNADOT_ADD_DNS_SLEEP="${DYNADOT_ADD_DNS_SLEEP:-$(_readaccountconf_mutable DYNADOT_ADD_DNS_SLEEP)}"
  if [ "$DYNADOT_ADD_DNS_SLEEP" ]; then
    _saveaccountconf_mutable DYNADOT_ADD_DNS_SLEEP "$DYNADOT_ADD_DNS_SLEEP"
  fi

  _debug "DYNADOT: Detecting root domain"
  if ! _get_root "$fulldomain"; then
    _err "DYNADOT: Root domain not found"
    return 1
  fi
  _debug "DYNADOT: _domain: $_domain"
  _debug "DYNADOT: _sub_domain: $_sub_domain"

  #Get the current domain settings
  if ! _dynadot_get_dns; then
    _err "cannot get domain current settings"
    return 1
  fi

  if _contains "$response" "$txtvalue"; then
    _info "DYNADOT: Already exists, Skipping ADD"
    return 0
  fi

  if ! _contains "$response" '"Type":"Dynadot DNS"'; then
    _err "Only Dynadot domains with Type 'Dynadot DNS' are supported."
    return 1
  fi

  if ! _dynadot_add_txt_entry; then
    _err "DYNADOT: Add txt record failed."
    return 1
  fi

  if [ "$DYNADOT_ADD_DNS_SLEEP" ]; then
    _debug "DYNADOT: Test Mode. Sleeping $DYNADOT_ADD_DNS_SLEEP seconds."
    sleep "$DYNADOT_ADD_DNS_SLEEP"
  fi

  _info "DYNADOT: TXT record added successfully"
  return 0
}

#Usage: dns_dynadot_rm fulldomain txtvalue
#Remove the txt record after validation.
dns_dynadot_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "DYNADOT: Removing TXT Record"
  _debug "DYNADOT: fulldomain: $fulldomain"
  _debug "DYNADOT: txtvalue: $txtvalue"

  DYNADOTAPI_SKIP_REMOVE="${DYNADOTAPI_SKIP_REMOVE:-$(_readaccountconf_mutable DYNADOTAPI_SKIP_REMOVE)}"
  if [ "$DYNADOTAPI_SKIP_REMOVE" ]; then
    _saveaccountconf_mutable DYNADOTAPI_SKIP_REMOVE "$DYNADOTAPI_SKIP_REMOVE"
  fi

  if [ "$DYNADOTAPI_SKIP_REMOVE" = "SKIP" ]; then
    _info "DYNADOT: Skipping removal.  Please remove manually."
    return 0
  fi

  DYNADOTAPI_Token="${DYNADOTAPI_Token:-$(_readaccountconf_mutable DYNADOTAPI_Token)}"
  if [ -z "$DYNADOTAPI_Token" ]; then
    _err "You don't specify dynadot api token key."
    _err "Please create your token and try again."
    return 1
  fi
  _saveaccountconf_mutable DYNADOTAPI_Token "$DYNADOTAPI_Token"

  DYNADOTAPI_API_RETRIES="${DYNADOTAPI_API_RETRIES:-$(_readaccountconf_mutable DYNADOTAPI_API_RETRIES)}"
  if [ -z "$DYNADOTAPI_API_RETRIES" ]; then
    DYNADOTAPI_API_RETRIES=1
  fi
  _saveaccountconf_mutable DYNADOTAPI_API_RETRIES "$DYNADOTAPI_API_RETRIES"

  DYNADOTAPI_RETRY_SLEEP="${DYNADOTAPI_RETRY_SLEEP:-$(_readaccountconf_mutable DYNADOTAPI_RETRY_SLEEP)}"
  if [ -z "$DYNADOTAPI_RETRY_SLEEP" ]; then
    DYNADOTAPI_RETRY_SLEEP=30
  fi
  _saveaccountconf_mutable DYNADOTAPI_RETRY_SLEEP "$DYNADOTAPI_RETRY_SLEEP"

  DYNADOT_REMOVE_DNS_SLEEP="${DYNADOT_REMOVE_DNS_SLEEP:-$(_readaccountconf_mutable DYNADOT_REMOVE_DNS_SLEEP)}"
  if [ "$DYNADOT_REMOVE_DNS_SLEEP" ]; then
    _saveaccountconf_mutable DYNADOT_REMOVE_DNS_SLEEP "$DYNADOT_REMOVE_DNS_SLEEP"
  fi

  _debug "DYNADOT: First detect the root domain"
  if ! _get_root "$fulldomain"; then
    _err "DYNADOT: Root domain not found"
    return 1
  fi
  _debug "DYNADOT: _domain: $_domain"
  _debug "DYNADOT: _sub_domain: $_sub_domain"

  #Get the current domain settings
  if ! _dynadot_get_dns; then
    _err "DYNADOT: cannot get domain current settings"
    return 1
  fi

  if ! _contains "$response" "$txtvalue"; then
    _info "DYNADOT: Record not found, skipping REMOVE"
    return 0
  fi

  if ! _dynadot_rm_txt_entry; then
    _err "DYNADOT: Remove txt record failed."
    return 1
  fi

  if [ "$DYNADOT_REMOVE_DNS_SLEEP" ]; then
    _debug "DYNADOT: Test Mode. Sleeping $DYNADOT_REMOVE_DNS_SLEEP seconds."
    sleep "$DYNADOT_REMOVE_DNS_SLEEP"
  fi

  _info "DYNADOT: TXT record removed successfully"
  return 0
}

####################  Private functions below ##################################

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1
  i=1
  p=1

  _debug "DYNADOT: Lookup root domain for: $domain"

  if ! _dynadot_list_domain; then
    _debug "DYNADOT: list_domain failed"
    return 1
  fi

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if _contains "$response" "\"Name\":\"$h\""; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain=$h
      _debug "DYNADOT: Found root domain: $_domain"
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_dynadot_list_domain() {
  _dynadot_rest "command=list_domain"
  return $?
}

_dynadot_get_dns() {
  _dynadot_rest "command=get_dns&domain=$_domain"
  return $?
}

_dynadot_add_txt_entry() {

  _debug "DYNADOT: Building add command"

  _json="$response"
  _url_params=""
  _sub_host_cnt=$(echo "$_json" | sed 's/[x ]/-/g' | sed 's/{"Subhost"/x /g' | sed 's/[^x ]//g' | wc -w)
  _main_domain_cnt=$(echo "$_json" | sed 's/[x ]/-/g' | sed 's/{"RecordType"/x /g' | sed 's/[^x ]//g' | wc -w)

  _debug "DYNADOT: Main Domain Count: $_main_domain_cnt"
  _debug "DYNADOT: Sub Domain Count: $_sub_host_cnt"

  _ttl=$(printf "%s" "$_json" | sed -n 's/.*"TTL":"\([^"]*\)".*/\1/p')
  if [ "$_ttl" ]; then
    _url_params="$_url_params&ttl=$_ttl"
  fi
  _debug "DYNADOT: TTL: $_ttl"

  # Slashes interfere with our sed commands on some systems. Changing to placeholder values and will add them back in later
  _json=$(printf "%s" "$_json" | _json_decode | sed 's#/#----SLASH----#g' | sed 's#\\#----BSLASH----#g')

  _cnt="$((_sub_host_cnt - 1))"
  for i in $(seq 0 "$_cnt"); do
    _subHostArgs=$(printf "%s" "$_json" | sed 's/.*{\("Subhost":[^}]*\)}.*/\1/')
    _json=$(printf "%s" "$_json" | sed "s/${_subHostArgs}/--------------------/")

    _subHost=$(printf "%s" "$_subHostArgs" | sed -n 's/.*"Subhost":"\([^"]*\)".*/\1/p' | _url_encode)
    _subHost_type=$(printf "%s" "$_subHostArgs" | sed -n 's/.*"RecordType":"\([^"]*\)".*/\1/p' | tr '[:upper:]' '[:lower:]' | _url_encode)
    _subHost_value=$(printf "%s" "$_subHostArgs" | sed -n 's/.*"Value":"\([^"]*\)".*/\1/p' | _url_encode)
    _subHost_valuex=$(printf "%s" "$_subHostArgs" | sed -n 's/.*"Value2":"\([^"]*\)".*/\1/p' | _url_encode)

    if [ "$_subHost" ]; then
      _url_params="$_url_params&subdomain$i=$_subHost"
    fi
    if [ "$_subHost_type" ]; then
      _url_params="$_url_params&sub_record_type$i=$_subHost_type"
    fi
    if [ "$_subHost_value" ]; then
      _url_params="$_url_params&sub_record$i=$_subHost_value"
    fi
    if [ "$_subHost_valuex" ]; then
      _url_params="$_url_params&sub_recordx$i=$_subHost_valuex"
    fi
    _debug "DYNADOT: Including Sub Domain: $_subHost : $_subHost_type : $_subHost_value : $_subHost_valuex"

  done

  _cnt="$((_main_domain_cnt - 1))"
  for i in $(seq 0 "$_cnt"); do
    _mainHostArgs=$(printf "%s" "$_json" | sed 's/.*{\("RecordType":[^}]*\)}.*/\1/')
    _json=$(printf "%s" "$_json" | sed "s/${_mainHostArgs}/--------------------/")

    _mainHost_type=$(printf "%s" "$_mainHostArgs" | sed -n 's/.*"RecordType":"\([^"]*\)".*/\1/p' | tr '[:upper:]' '[:lower:]' | _url_encode)
    _mainHost_value=$(printf "%s" "$_mainHostArgs" | sed -n 's/.*"Value":"\([^"]*\)".*/\1/p' | _url_encode)
    _mainHost_valuex=$(printf "%s" "$_mainHostArgs" | sed -n 's/.*"Value2":"\([^"]*\)".*/\1/p' | _url_encode)

    if [ "$_mainHost_type" ]; then
      _url_params="$_url_params&main_record_type$i=$_mainHost_type"
    fi
    if [ "$_mainHost_value" ]; then
      _url_params="$_url_params&main_record$i=$_mainHost_value"
    fi
    if [ "$_mainHost_valuex" ]; then
      _url_params="$_url_params&main_recordx$i=$_mainHost_valuex"
    fi
    _debug "DYNADOT: Including Main Domain: $_mainHost_type : $_mainHost_value : $_mainHost_valuex"

  done

  _url_params=$(printf "%s" "$_url_params" | sed 's#----SLASH----#%2f#g' | sed 's#----BSLASH----#%5c#g')

  _debug "DYNADOT: Including Sub Domain $_sub_host_cnt: $_sub_domain : txt : $txtvalue"
  _url_params="command=set_dns2&domain=$_domain$_url_params&subdomain$_sub_host_cnt=$_sub_domain&sub_record_type$_sub_host_cnt=txt&sub_record$_sub_host_cnt=$txtvalue"

  _dynadot_rest "$_url_params"
  return $?
}

_dynadot_rm_txt_entry() {

  _debug "DYNADOT: Building remove command"

  _json="$response"
  _url_params=""
  _sub_host_cnt=$(echo "$_json" | sed 's/[x ]/-/g' | sed 's/{"Subhost"/x /g' | sed 's/[^x ]//g' | wc -w)
  _main_domain_cnt=$(echo "$_json" | sed 's/[x ]/-/g' | sed 's/{"RecordType"/x /g' | sed 's/[^x ]//g' | wc -w)

  _debug "DYNADOT: Main Domain Count: $_main_domain_cnt"
  _debug "DYNADOT: Sub Domain Count: $_sub_host_cnt"

  _ttl=$(printf "%s" "$_json" | sed -n 's/.*"TTL":"\([^"]*\)".*/\1/p')
  if [ "$_ttl" ]; then
    _url_params="$_url_params&ttl=$_ttl"
  fi
  _debug "DYNADOT: TTL: $_ttl"

  # Slashes interfere with our sed commands on some systems. Changing to placeholder values and will add them back in later
  _json=$(printf "%s" "$_json" | _json_decode | sed 's#/#----SLASH----#g' | sed 's#\\#----BSLASH----#g')

  _cnt="$((_sub_host_cnt - 1))"
  for i in $(seq 0 "$_cnt"); do
    _subHostArgs=$(printf "%s" "$_json" | sed 's/.*{\("Subhost":[^}]*\)}.*/\1/')
    _json=$(printf "%s" "$_json" | sed "s/${_subHostArgs}/--------------------/")

    _subHost=$(printf "%s" "$_subHostArgs" | sed -n 's/.*"Subhost":"\([^"]*\)".*/\1/p' | _url_encode)
    _subHost_type=$(printf "%s" "$_subHostArgs" | sed -n 's/.*"RecordType":"\([^"]*\)".*/\1/p' | tr '[:upper:]' '[:lower:]' | _url_encode)
    _subHost_value=$(printf "%s" "$_subHostArgs" | sed -n 's/.*"Value":"\([^"]*\)".*/\1/p' | _url_encode)
    _subHost_valuex=$(printf "%s" "$_subHostArgs" | sed -n 's/.*"Value2":"\([^"]*\)".*/\1/p' | _url_encode)

    if [ "$_subHost_value" != "$txtvalue" ]; then
      if [ "$_subHost" ]; then
        _url_params="$_url_params&subdomain$i=$_subHost"
      fi
      if [ "$_subHost_type" ]; then
        _url_params="$_url_params&sub_record_type$i=$_subHost_type"
      fi
      if [ "$_subHost_value" ]; then
        _url_params="$_url_params&sub_record$i=$_subHost_value"
      fi
      if [ "$_subHost_valuex" ]; then
        _url_params="$_url_params&sub_recordx$i=$_subHost_valuex"
      fi
      _debug "DYNADOT: Including Sub Domain: $_subHost : $_subHost_type : $_subHost_value : $_subHost_valuex"
    else
      _debug "DYNADOT: Excluding Sub Domain: $_subHost : $_subHost_type : $_subHost_value : $_subHost_valuex"
    fi
  done

  _cnt="$((_main_domain_cnt - 1))"
  for i in $(seq 0 "$_cnt"); do
    _mainHostArgs=$(printf "%s" "$_json" | sed 's/.*{\("RecordType":[^}]*\)}.*/\1/')
    _json=$(printf "%s" "$_json" | sed "s/${_mainHostArgs}/--------------------/")

    _mainHost_type=$(printf "%s" "$_mainHostArgs" | sed -n 's/.*"RecordType":"\([^"]*\)".*/\1/p' | tr '[:upper:]' '[:lower:]' | _url_encode)
    _mainHost_value=$(printf "%s" "$_mainHostArgs" | sed -n 's/.*"Value":"\([^"]*\)".*/\1/p' | _url_encode)
    _mainHost_valuex=$(printf "%s" "$_mainHostArgs" | sed -n 's/.*"Value2":"\([^"]*\)".*/\1/p' | _url_encode)

    if [ "$_mainHost_type" ]; then
      _url_params="$_url_params&main_record_type$i=$_mainHost_type"
    fi
    if [ "$_mainHost_value" ]; then
      _url_params="$_url_params&main_record$i=$_mainHost_value"
    fi
    if [ "$_mainHost_valuex" ]; then
      _url_params="$_url_params&main_recordx$i=$_mainHost_valuex"
    fi
    _debug "DYNADOT: Including Main Domain: $_mainHost_type : $_mainHost_value : $_mainHost_valuex"

  done

  _url_params=$(printf "%s" "$_url_params" | sed 's#----SLASH----#%2f#g' | sed 's#----BSLASH----#%5c#g')

  _url_params="command=set_dns2&domain=$_domain$_url_params"

  _dynadot_rest "$_url_params"
  return $?
}

_dynadot_rest() {
  url_params=$1

  _retry_attempts="$DYNADOTAPI_API_RETRIES"
  _retry_sleep="$DYNADOTAPI_RETRY_SLEEP"

  while true; do
    if _dynadot_rest_call "$url_params"; then
      return 0
    fi

    _retry_attempts=$(_math "$_retry_attempts" - 1)

    if [ "${_retry_attempts}" -lt "1" ]; then
      _err "DYNADOT: api call failed all retry attempts."
      return 1
    fi

    _info "DYNADOT: api call failed. Retrying up to $_retry_attempts times. Sleeping $_retry_sleep seconds before retry."
    sleep "$_retry_sleep"
  done

  # We should not get to the bottom of this function
  return 1
}

_dynadot_rest_call() {
  url_params=$1
  token_trimmed=$(echo "$DYNADOTAPI_Token" | tr -d '"')

  _debug "DYNADOT: Calling dynadot API: $url_params"

  url="$DYNADOT_Api?key=$token_trimmed&$url_params"

  response="$(_get "$url")"

  if [ "$?" != "0" ]; then
    _err "DYNADOT: error with: $url_params"
    return 1
  fi
  if ! _contains "$response" '"Status":"success"'; then
    _err "DYNADOT: error with: $url_params"
    _err "$response"
    return 1
  fi
  _debug2 "DYNADOT: api response: $response"

  return 0
}

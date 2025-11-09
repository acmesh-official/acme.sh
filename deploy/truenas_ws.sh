#!/usr/bin/env sh

# TrueNAS deploy script for SCALE/CORE using websocket
# It is recommend to use a wildcard certificate
#
# Websocket Documentation: https://www.truenas.com/docs/api/scale_websocket_api.html
#
# Tested with TrueNAS Scale - Electric Eel 24.10
# Changes certificate in the following services:
#  - Web UI
#  - FTP
#  - iX Apps
#
# The following environment variables must be set:
# ------------------------------------------------
#
# # API KEY
# # Use the folowing URL to create a new API token: <TRUENAS_HOSTNAME OR IP>/ui/apikeys
# export DEPLOY_TRUENAS_APIKEY="<API_KEY_GENERATED_IN_THE_WEB_UI"
#

### Private functions

# Call websocket method
# Usage:
#   _ws_response=$(_ws_call "math.dummycalc" "'{"x": 4, "y": 5}'")
#   _info "$_ws_response"
#
# Output:
#   {"z": 9}
#
# Arguments:
#   $@ - midclt arguments for call
#
# Returns:
#   JSON/JOBID
_ws_call() {
  _debug "_ws_call arg1" "$1"
  _debug "_ws_call arg2" "$2"
  _debug "_ws_call arg3" "$3"
  if [ $# -eq 3 ]; then
    _ws_response=$(midclt --uri "$_ws_uri" -K "$DEPLOY_TRUENAS_APIKEY" call "$1" "$2" "$3")
  fi
  if [ $# -eq 2 ]; then
    _ws_response=$(midclt --uri "$_ws_uri" -K "$DEPLOY_TRUENAS_APIKEY" call "$1" "$2")
  fi
  if [ $# -eq 1 ]; then
    _ws_response=$(midclt --uri "$_ws_uri" -K "$DEPLOY_TRUENAS_APIKEY" call "$1")
  fi
  _debug "_ws_response" "$_ws_response"
  printf "%s" "$_ws_response"
  return 0
}

# Upload certificate with webclient api
_ws_upload_cert() {

  /usr/bin/env python - <<EOF

import sys

from truenas_api_client import Client
with Client(uri="$_ws_uri") as c:

  ### Login with API key
  print("I:Trying to upload new certificate...")
  ret = c.call("auth.login_with_api_key", "${DEPLOY_TRUENAS_APIKEY}")
  if ret:
    ### upload certificate
    with open('$1', 'r') as file:
      fullchain = file.read()
    with open('$2', 'r') as file:
      privatekey = file.read()
    ret = c.call("certificate.create", {"name": "$3", "create_type": "CERTIFICATE_CREATE_IMPORTED", "certificate": fullchain, "privatekey": privatekey}, job=True)
    print("R:" + str(ret["id"]))
    sys.exit(0)
  else:
    print("R:0")
    print("E:_ws_upload_cert error!")
    sys.exit(7)

EOF

  return $?

}

# Check argument is a number
# Usage:
#
# Output:
#   n/a
#
# Arguments:
#   $1 - Anything
#
# Returns:
#   0: true
#   1: false
_ws_check_jobid() {
  case "$1" in
  [0-9]*)
    return 0
    ;;
  esac
  return 1
}

# Wait for job to finish and return result as JSON
# Usage:
#   _ws_result=$(_ws_get_job_result "$_ws_jobid")
#   _new_certid=$(printf "%s" "$_ws_result" | jq -r '."id"')
#
# Output:
#   JSON result of the job
#
# Arguments:
#   $1 - JobID
#
# Returns:
#   n/a
_ws_get_job_result() {
  while true; do
    _sleep 2
    _ws_response=$(_ws_call "core.get_jobs" "[[\"id\", \"=\", $1]]")
    if [ "$(printf "%s" "$_ws_response" | jq -r '.[]."state"')" != "RUNNING" ]; then
      _ws_result="$(printf "%s" "$_ws_response" | jq '.[]."result"')"
      _debug "_ws_result" "$_ws_result"
      printf "%s" "$_ws_result"
      _ws_error="$(printf "%s" "$_ws_response" | jq '.[]."error"')"
      if [ "$_ws_error" != "null" ]; then
        _err "Job $1 failed:"
        _err "$_ws_error"
        return 7
      fi
      break
    fi
  done
  return 0
}

########################
### Public functions ###
########################

# truenas_ws_deploy
#
# Deploy new certificate to TrueNAS services
#
# Arguments
#  1: Domain
#  2: Key-File
#  3: Certificate-File
#  4: CA-File
#  5: FullChain-File
# Returns:
#  0: Success
#  1: Missing API Key
#  2: TrueNAS not ready
#  3: Not a JobID
#  4: FTP cert error
#  5: WebUI cert error
#  6: Job error
#  7: WS call error
#
truenas_ws_deploy() {
  _domain="$1"
  _file_key="$2"
  _file_cert="$3"
  _file_ca="$4"
  _file_fullchain="$5"
  _debug _domain "$_domain"
  _debug _file_key "$_file_key"
  _debug _file_cert "$_file_cert"
  _debug _file_ca "$_file_ca"
  _debug _file_fullchain "$_file_fullchain"

  ########## Environment check

  _info "Checking environment variables..."
  _getdeployconf DEPLOY_TRUENAS_APIKEY
  _getdeployconf DEPLOY_TRUENAS_HOSTNAME
  _getdeployconf DEPLOY_TRUENAS_PROTOCOL
  # Check API Key
  if [ -z "$DEPLOY_TRUENAS_APIKEY" ]; then
    _err "TrueNAS API key not found, please set the DEPLOY_TRUENAS_APIKEY environment variable."
    return 1
  fi
  # Check Hostname, default to localhost if not set
  if [ -z "$DEPLOY_TRUENAS_HOSTNAME" ]; then
    _info "TrueNAS hostname not set. Using 'localhost'."
    DEPLOY_TRUENAS_HOSTNAME="localhost"
  fi
  # Check protocol, default to ws if not set
  if [ -z "$DEPLOY_TRUENAS_PROTOCOL" ]; then
    _info "TrueNAS protocol not set. Using 'ws'."
    DEPLOY_TRUENAS_PROTOCOL="ws"
  fi
  _ws_uri="$DEPLOY_TRUENAS_PROTOCOL://$DEPLOY_TRUENAS_HOSTNAME/websocket"
  _debug2 DEPLOY_TRUENAS_HOSTNAME "$DEPLOY_TRUENAS_HOSTNAME"
  _debug2 DEPLOY_TRUENAS_PROTOCOL "$DEPLOY_TRUENAS_PROTOCOL"
  _debug _ws_uri "$_ws_uri"
  _secure_debug2 DEPLOY_TRUENAS_APIKEY "$DEPLOY_TRUENAS_APIKEY"
  _info "Environment variables: OK"

  ########## Health check

  _info "Checking TrueNAS health..."
  _ws_response=$(_ws_call "system.ready" | tr '[:lower:]' '[:upper:]')
  _ws_ret=$?
  if [ $_ws_ret -gt 0 ]; then
    _err "Error calling system.ready:"
    _err "$_ws_response"
    return $_ws_ret
  fi

  if [ "$_ws_response" != "TRUE" ]; then
    _err "TrueNAS is not ready."
    _err "Please check environment variables DEPLOY_TRUENAS_APIKEY, DEPLOY_TRUENAS_HOSTNAME and DEPLOY_TRUENAS_PROTOCOL."
    _err "Verify API key."
    return 2
  fi
  _savedeployconf DEPLOY_TRUENAS_APIKEY "$DEPLOY_TRUENAS_APIKEY"
  _savedeployconf DEPLOY_TRUENAS_HOSTNAME "$DEPLOY_TRUENAS_HOSTNAME"
  _savedeployconf DEPLOY_TRUENAS_PROTOCOL "$DEPLOY_TRUENAS_PROTOCOL"
  _info "TrueNAS health: OK"

  ########## System info

  _info "Gather system info..."
  _ws_response=$(_ws_call "system.info")
  _truenas_version=$(printf "%s" "$_ws_response" | jq -r '."version"')
  _info "TrueNAS version: $_truenas_version"

  ########## Gather current certificate

  _info "Gather current WebUI certificate..."
  _ws_response="$(_ws_call "system.general.config")"
  _ui_certificate_id=$(printf "%s" "$_ws_response" | jq -r '."ui_certificate"."id"')
  _ui_certificate_name=$(printf "%s" "$_ws_response" | jq -r '."ui_certificate"."name"')
  _info "Current WebUI certificate ID: $_ui_certificate_id"
  _info "Current WebUI certificate name: $_ui_certificate_name"

  ########## Upload new certificate

  _info "Upload new certificate..."
  _certname="acme_$(_utc_date | tr -d '\-\:' | tr ' ' '_')"
  _info "New WebUI certificate name: $_certname"
  _debug _certname "$_certname"
  _ws_out=$(_ws_upload_cert "$_file_fullchain" "$_file_key" "$_certname")

  echo "$_ws_out" | while IFS= read -r LINE; do
    case "$LINE" in
    I:*)
      _info "${LINE#I:}"
      ;;
    D:*)
      _debug "${LINE#D:}"
      ;;
    E*)
      _err "${LINE#E:}"
      ;;
    *) ;;

    esac
  done

  _new_certid=$(echo "$_ws_out" | grep 'R:' | cut -d ':' -f 2)

  _info "New certificate ID: $_new_certid"

  ########## FTP

  _info "Replace FTP certificate..."
  _ws_response=$(_ws_call "ftp.update" "{\"ssltls_certificate\": $_new_certid}")
  _ftp_certid=$(printf "%s" "$_ws_response" | jq -r '."ssltls_certificate"')
  if [ "$_ftp_certid" != "$_new_certid" ]; then
    _err "Cannot set FTP certificate."
    _debug "_ws_response" "$_ws_response"
    return 4
  fi

  ########## ix Apps (SCALE only)

  _info "Replace app certificates..."
  _ws_response=$(_ws_call "app.query")
  for _app_name in $(printf "%s" "$_ws_response" | jq -r '.[]."name"'); do
    _info "Checking app $_app_name..."
    _ws_response=$(_ws_call "app.config" "$_app_name")
    if [ "$(printf "%s" "$_ws_response" | jq -r '."network" | has("certificate_id")')" = "true" ]; then
      _info "App has certificate option, setup new certificate..."
      _info "App will be redeployed after updating the certificate."
      _ws_jobid=$(_ws_call "app.update" "$_app_name" "{\"values\": {\"network\": {\"certificate_id\": $_new_certid}}}")
      _debug "_ws_jobid" "$_ws_jobid"
      if ! _ws_check_jobid "$_ws_jobid"; then
        _err "No JobID returned from websocket method."
        return 3
      fi
      _ws_result=$(_ws_get_job_result "$_ws_jobid")
      _ws_ret=$?
      if [ $_ws_ret -gt 0 ]; then
        return $_ws_ret
      fi
      _debug "_ws_result" "$_ws_result"
      _info "App certificate replaced."
    else
      _info "App has no certificate option, skipping..."
    fi
  done

  ########## WebUI

  _info "Replace WebUI certificate..."
  _ws_response=$(_ws_call "system.general.update" "{\"ui_certificate\": $_new_certid}")
  _changed_certid=$(printf "%s" "$_ws_response" | jq -r '."ui_certificate"."id"')
  if [ "$_changed_certid" != "$_new_certid" ]; then
    _err "WebUI certificate change error.."
    return 5
  else
    _info "WebUI certificate replaced."
  fi
  _info "Restarting WebUI..."
  _ws_response=$(_ws_call "system.general.ui_restart")
  _info "Waiting for UI restart..."
  _sleep 15

  ########## Certificates

  _info "Deleting old certificate..."
  _ws_jobid=$(_ws_call "certificate.delete" "$_ui_certificate_id")
  if ! _ws_check_jobid "$_ws_jobid"; then
    _err "No JobID returned from websocket method."
    return 3
  fi
  _ws_result=$(_ws_get_job_result "$_ws_jobid")
  _ws_ret=$?
  if [ $_ws_ret -gt 0 ]; then
    return $_ws_ret
  fi

  _info "Have a nice day...bye!"

}

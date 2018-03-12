#!/usr/bin/env sh

# Deploy certificates to rancher environmentsx

# here are the defaults, overridable via env vars
#
#export RANCHER_CONFIG=${HOME}/.rancher/cli.json
#export RANCHER_ENV=

# usage:
# - download rancher-cli from your rancher server and use it to create cli.json
#   the format of the file is quite simple, so you can just create your own
# ! also run chmod 600 ~/.rancher/cli.json, since rancher-cli doesn't
# - for multiple servers override RANCHER_CONFIG
# - for multiple environments on a server set RANCHER_ENV appropriately
#   otherwise the one selected within cli.json is used

# example
# acme.sh --deploy -d my.website.com --deploy-hook rancher --debug
# RANCHER_ENV=1a6 acme.sh --deploy -d my.website.com --deploy-hook rancher --debug

########  Public functions #####################

#domain keyfile certfile cafile fullchain
rancher_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  if ! _exists jq; then
      _err "The command jq is not found."
      return 1
  fi

  
  _defaultRancherConfig=${HOME}/.rancher/cli.json
  _rancherConfig=${RANCHER_CONFIG:-${_defaultRancherConfig}}
  _info "Using rancher configuration $_rancherConfig"
  if [ ! -r "${_rancherConfig}" ] ; then
      _err "cannot read rancher configuration"
      return 1
  fi
  eval $(jq --monochrome-output < "${_rancherConfig}" \
     '@sh "_rancherUrl=\(.url)","_accessKey=\(.accessKey)","_secretKey=\(.secretKey)","_envId=\(.environment)"' | xargs)
  _debug _rancherUrl "$_rancherUrl"
  _debug _accessKey "$_accessKey"
  _secure_debug _secretKey "$_secretKey"
  _debug _envId "$_envId"

  if [ -n "${RANCHER_ENV}" ] ; then
      _envId="${RANCHER_ENV}"
  fi

  # when set by rancher-cli rancerUrl has an unwanted trailing "/schemas"
  _rancherUrl=${_rancherUrl%/schemas}

  _info "Deploying certificate $_cdomain into rancher environment $_envId at $_rancherUrl"
  _do_rancher_deploy_cert
  _success=$?
  if (( ! $_success )) ; then
      _info "Certificate successfully deployed"
      return 0
  else
      _err "Deployment failed: $_curlResult"
      return 1
  fi

}

function _do_rancher_deploy_cert () {
    _cert=$(<"$_ccert")
    _chain=$(<"$_cca")
    _privkey=$(<"$_ckey")

    _curlUrl="$_rancherUrl/projects/$_envId/certificates"
    _curlMethod="POST"
    _curlAuth="$_accessKey:$_secretKey"
    _certJson=$(jq --null-input --compact-output \
                   --arg cert "$_cert" \
                   --arg chain "$_chain" \
                   --arg privkey "$_privkey" \
                   --arg name "$_cdomain" \
                   '{type:"certificate",cert:$cert,certChain:$chain,key:$privkey,name:$name}')

    _debug _curlUrl "$_curlUrl"
    _debug _curlMethod "$_curlMethod"
    _secure_debug _curlAuth "$_curlAuth"    
    _secure_debug _certJson "$_certJson"

    _curlResult=$(curl -s \
                       -u "${_curlAuth}" \
                       -X "${_curlMethod}" \
                       -H 'Content-Type: application/json' \
                       -H 'Accept: application/json' \
                       -d "${_certJson}" \
                       "${_curlUrl}" |
                         jq -r 'if (.type == "error") then "error: status="+(.status|tostring)+", code="+(.code|tostring)+", detail="+(.detail|tostring) else "success" end')
    _debug _curlResult "$_curlResult"

    [ "$_curlResult" == "success" ] && return 0 || return 1
}

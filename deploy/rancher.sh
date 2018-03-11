#!/bin/bash

# Deploy and maintain certificates within Rancher environments

# here are the defaults, overridable via env vars

#export RANCHER_CONFIG=${HOME}/.rancher/cli.json
#export RANCHER_ENV=

# usage:

# - download rancher-cli from your rancher server and use it to create cli.json
#   the format of the file is quite simple, so you can just create your own
# ! also run chmod 600 ~/.rancher/cli.json, since rancher-cli doesn't
# - for multiple servers override RANCHER_CONFIG
# - for multiple environments on a server set RANCHER_ENV appropriately;
#   otherwise the one within cli.json is used
# - each run with --deploy saves the rancher configuration into the domain conf file in acme.sh
#   the list will be used when running acme.sh --renew[-all] to push the certificate onto rancher environments
#   you have to keep the rancher config files for renewal to work
# - to remove a rancher server from a certificate you have to edit its conf file

# deploy example:
#    acme.sh --deploy -d my.website.com --deploy-hook rancher
#    RANCHER_ENV=1a6 acme.sh --deploy -d my.website.com --deploy-hook rancher

# renew example:
#    acme.sh --renew -d my.website.com


########  Private functions #####################

# save rancher environment configuration in the domain config file
function _rancher_savedomainconf () {
    local _rancherEnvId="$1"
    local _rancherConfigFile="$2"

    # use this hash to store the config pair
    local _configId=$(echo "${_rancherEnvId}@${_rancherConfigFile}" | md5sum | head -c 8)

    _info "Saving rancher information in domain file under id $_configId: environment $_rancherEnvId, config file $_rancherConfigFile"
    _savedomainconf "Rancher_ConfigFile_$_configId" "$_rancherConfig"
    _savedomainconf "Rancher_EnvId_$_configId" "$_rancherEnvId"

    local _rancherEnvs=$(_readdomainconf Rancher_Configs)
    if [[ ! "$_rancherConfigs" = *"$_configId"* ]] ; then
        _savedomainconf "Rancher_Configs" "$_rancherConfigs $_configId"
    fi
}

# read rancher's cli.json file
function _rancher_read_configfile () {
    local _rancherConfigFile="$1"
    _info "Reading rancher configuration $_rancherConfig"

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

    # when set by rancher-cli rancerUrl has an unwanted trailing "/schemas"
    _rancherUrl=${_rancherUrl%/schemas}

    return 0
}

# deploy a new certificate into a rancher environment
function _rancher_deploy_cert () {
    local _cert=$(<"$_ccert")
    local _chain=$(<"$_cca")
    local _privkey=$(<"$_ckey")

    local _curlUrl="$_rancherUrl/projects/$_envId/certificates"
    local _curlMethod="POST"
    local _curlAuth="$_accessKey:$_secretKey"
    local _certJson=$(jq --null-input --compact-output \
                         --arg cert "$_cert" \
                         --arg chain "$_chain" \
                         --arg privkey "$_privkey" \
                         --arg name "$_cdomain" \
                         '{type:"certificate",cert:$cert,certChain:$chain,key:$privkey,name:$name}')

    _debug _curlUrl "$_curlUrl"
    _debug _curlMethod "$_curlMethod"
    _secure_debug _curlAuth "$_curlAuth"
    _secure_debug _certJson "$_certJson"

    local _curlResult=$(curl -s \
                             -u "${_curlAuth}" \
                             -X "${_curlMethod}" \
                             -H 'Content-Type: application/json' \
                             -H 'Accept: application/json' \
                             -d "${_certJson}" \
                             "${_curlUrl}" |
                               jq -r 'if (.type == "error") then "error: status="+(.status|tostring)+", code="+(.code|tostring)+", detail="+(.detail|tostring) else "success" end')
    _debug _curlResult "$_curlResult"
    if [ "$_curlResult" == "success" ] ; then
        _info "Certificate successfully deployed"
        return 0
    else
        _err "Deployment failed: $_curlResult"
        return 1
    fi
}

# get the id of an existing certificate by domain from a rancher environment
function _get_rancher_certId () {
    local _curlUrl="$_rancherUrl/projects/$_envId/certificates"
    local _curlMethod="GET"
    local _curlAuth="$_accessKey:$_secretKey"
    local _filter=".data[] | select(.CN==\"$_cdomain\") | .id"

    _debug _curlUrl "$_curlUrl"
    _debug _curlMethod "$_curlMethod"
    _secure_debug _curlAuth "$_curlAuth"
    _debug _filter "$_filter"

    local _curlResult=$(curl -s \
                             -u "${_curlAuth}" \
                             -X "${_curlMethod}" \
                             -H 'Content-Type: application/json' \
                             -H 'Accept: application/json' \
                             "${_curlUrl}" |
                               jq -r "$_filter")
    echo $_curlResult
}

# update an existing certificate on a rancher environment
function _rancher_update_cert () {
    local _certId=$(_get_rancher_certId)

    if [ "$_certId" == "" ] ; then
        _err "Cannot find certificate for domain $_cdomain on rancher environment $_envId at url $_rancherUrl"
        return 1
    fi

    _info "Found that certificate $_cdomain has id $_certId on rancher environment $_envId at url $_rancherUrl"

    local _cert=$(<"$_ccert")
    local _chain=$(<"$_cca")
    local _privkey=$(<"$_ckey")

    local _curlUrl="$_rancherUrl/projects/$_envId/certificates/$_certId"
    local _curlMethod="PUT"
    local _curlAuth="$_accessKey:$_secretKey"
    local _certJson=$(jq --null-input --compact-output \
                         --arg cert "$_cert" \
                         --arg chain "$_chain" \
                         --arg privkey "$_privkey" \
                         --arg name "$_cdomain" \
                         '{type:"certificate",cert:$cert,certChain:$chain,key:$privkey,name:$name}')

    _debug _curlUrl "$_curlUrl"
    _debug _curlMethod "$_curlMethod"
    _secure_debug _curlAuth "$_curlAuth"
    _secure_debug _certJson "$_certJson"

    local _curlResult=$(curl -s \
                             -u "${_curlAuth}" \
                             -X "${_curlMethod}" \
                             -H 'Content-Type: application/json' \
                             -H 'Accept: application/json' \
                             -d "${_certJson}" \
                             "${_curlUrl}" |
                               jq -r 'if (.type == "error") then "error: status="+(.status|tostring)+", code="+(.code|tostring)+", detail="+(.detail|tostring) else "success" end')
    _debug _curlResult "$_curlResult"

    if [ "$_curlResult" == "success" ] ; then
        _info "Certificate successfully updated"
        return 0
    else
        _err "Certificate update failed: $_curlResult"
        return 1
    fi
}

# deploy a new certificate into a rancher environment
function _rancher_deploy () {
    local _defaultRancherConfig=${HOME}/.rancher/cli.json
    local _rancherConfig=${RANCHER_CONFIG:-${_defaultRancherConfig}}

    _rancher_read_configfile "${_rancherConfig}"
    local _success=$?
    if [ "$_success" != "0" ] ; then
        return 1
    fi

    if [ -n "${RANCHER_ENV}" ] ; then
        _envId="${RANCHER_ENV}"
    fi

    if [ -z "$_envId" ] ; then
        _err "Empty rancher env ID"
        return 1
    fi

    _info "Deploying certificate $_cdomain into rancher environment $_envId at $_rancherUrl"
    _rancher_deploy_cert
    local _success=$?
    if [ "$_success" == "0" ] ; then
        _rancher_savedomainconf "$_envId" "$_rancherConfig"
        return 0
    else
        return 1
    fi
}

# renew an existing certificate in a rancher environment
function _rancher_renew () {
    local _rancherConfigs=$(_readdomainconf Rancher_Configs)
    _info "Found rancher env configs: $_rancherConfigs"
    for _configId in $_rancherConfigs ; do
        _info "Processing rancher config $_configId"
        local _rancherConfig=$(_readdomainconf "Rancher_ConfigFile_$_configId")
        _rancher_read_configfile "${_rancherConfig}"
        _envId=$(_readdomainconf "Rancher_EnvId_$_configId")
        local _success=$?
        if [ "$_success" != "0" ] ; then
            return 1
        fi

        _info "Updating certificate $_cdomain from rancher environment $_envId at $_rancherUrl"
        _rancher_update_cert
        local _success=$?
        if [ "$_success" != "0" ] ; then
            return 1
        fi
    done

    return 0
}



########  Public functions #####################


# domain keyfile certfile cafile fullchain
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

    _debug IS_RENEW "$IS_RENEW"
    if [ "$IS_RENEW" == "1" ] ; then
        _rancher_renew
    else
        _rancher_deploy
    fi
    return $?
}

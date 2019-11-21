#!/usr/bin/env sh
# Here is the script to deploy the cert to your rancher-server using the rancher API.
# Uses curl to add cert to your rancher environment.
# Returns 0 when success.
#
# Written by Mihkail Zyablickiy <mikeaggy91@gmail.com>
# 2018-2019
#
####### Variables ##############################
#export RANCHER_ACCESS_KEY=7E6F529DAAFE771A5
#export RANCHER_SECRET_KEY=zahciekuro1eayae7jam3to5Ohf9adaeCooghiep
#export RANCHER_ENVIRONMENT=1a5
#export RANCHER_SERVER=http://rancher-server.example.com

REQ_SOFT="curl awk grep"
REQ_ENV_VARS="RANCHER_ACCESS_KEY RANCHER_SECRET_KEY RANCHER_ENVIRONMENT RANCHER_SERVER"

######## Private functions #####################

_getconfigvar() {
    _var="$1"
    case "${_var}" in
        "RANCHER_ACCESS_KEY" ) get_result="Le_rancher_access_key" ;;
        "RANCHER_SECRET_KEY" ) get_result="Le_rancher_secret_key" ;;
        "RANCHER_ENVIRONMENT" ) get_result="Le_rancher_environment" ;;
        "RANCHER_SERVER" ) get_result="Le_rancher_server" ;;
    esac
}

########  Public functions #####################

#domain keyfile certfile cafile fullchain

rancher_deploy() {
    _cdomain="$1"
    # Further $(sed 's/$/\\n/' "$1" | tr -d '\n')
    # Made for iclude cert in var in one line with \n
    _ckey=$(sed 's/$/\\n/' "$2" | tr -d '\n')
    _ccert=$(sed 's/$/\\n/' "$3" | tr -d '\n')
    _cca=$(sed 's/$/\\n/' "$4" | tr -d '\n')
    _cfullchain=$(sed 's/$/\\n/' "$5" | tr -d '\n')
    
    _debug _cdomain "$_cdomain"
    _debug _ckey "$_ckey"
    _debug _ccert "$_ccert"
    _debug _cca "$_cca"
    _debug _cfullchain "$_cfullchain"
    
    # Check software needed
    for PROGRAMM in $REQ_SOFT
    do
        if ! _exists $PROGRAMM; then
            _err "The command $PROGRAMM is not found."
            return 1
        fi
    done
    
    # Check environment variables and config variables
    for ENV_VAR in $REQ_ENV_VARS
    do
        _getconfigvar $ENV_VAR
        eval _var='$'$ENV_VAR
        eval _result='$'$get_result
        if [ -z "$_var" ]; then
            if [ -z "$_result" ]; then
                _err "$ENV_VAR variable not defined."
                return 1
            fi
        else
            $get_result="$_var"
            _savedomainconf $get_result "_result"
        fi
    done
    
    # Check api connection
    response=$(
        curl "$Le_rancher_server/v2-beta/" \
        --write-out "%{http_code}" \
        --silent \
        --output /dev/null
    )
    if [ "$response" -ge 200 ] && [ "$response" -le 299 ]; then
        _err "Curl failed to connect to $Le_rancher_server v2-beta API"
        return 1
    else
        _info "API connected!"
    fi
    
    # Check if certificate already exist in rancher
    
    id_raw_json=$(curl -s -u "$Le_rancher_access_key:$Le_rancher_secret_key" \
        -X GET \
        -H 'Accept: application/json' \
        -H 'Content-Type: application/json' \
    "$Le_rancher_server/v2-beta/projects/$Le_rancher_environment/certificates?name=$_cdomain")
    cert_state=$(echo "$id_raw_json" | awk -F='\:' -v RS='\,' "\$id_raw_json~/\"state\"/ {print}" | tr -d "\n\t" | sed -e 's/^"//' -e 's/"$//' | grep -o "active")
    _info "Cert state is $cert_state"
    if [ -z "$cert_state" ]; then
        # Add new certificate
        _info "Adding new cert to rancher"
        response=$(
            curl -u "$Le_rancher_access_key:$Le_rancher_secret_key" \
            -X POST \
            --write-out "%{http_code}" \
            --silent \
            --output /dev/null \
            -H 'Accept: application/json' \
            -H 'Content-Type: application/json' \
            -d "{\"type\":\"certificate\",\"name\":\"$_cdomain\",\"description\":\"acme.sh cert for $_cdomain\",\"key\":\"$_ckey\",\"cert\":\"$_ccert\",\"certChain\":\"$_cca\"}" \
            "$Le_rancher_server/v2-beta/projects/$Le_rancher_environment/certificates/"
        )
        _info "Update status code: $response"
        if [ "$response" -lt 199 ] || [ "$response" -gt 300 ]; then
            _err "Curl failed to create new cert"
            return 1
        fi
    else
        # Get certificate ID
        id_raw_json=$(curl -s -u "$Le_rancher_access_key:$Le_rancher_secret_key" \
            -X GET \
            -H 'Accept: application/json' \
            -H 'Content-Type: application/json' \
        "$Le_rancher_server/v2-beta/projects/$Le_rancher_environment/certificates?name=$_cdomain")
        cert_id=$(echo "$id_raw_json" | awk -F='\:' -v RS='\,' "\$id_raw_json~/\"data\"/ {print}" | tr -d "\n\t" | sed -e 's/^"//' -e 's/"$//' | sed -e 's/data.*"//')
        _info "Cert already exist ID is: $cert_id"
        # Update existing certificate
        _info "Updating..."
        response=$(
            curl -u "$Le_rancher_access_key:$Le_rancher_secret_key" \
            -X PUT \
            --write-out "%{http_code}" \
            --silent \
            --output /dev/null \
            -H 'Accept: application/json' \
            -H 'Content-Type: application/json' \
            -d "{\"id\":\"$cert_id\",\"type\":\"certificate\",\"baseType\":\"certificate\",\"name\":\"$_cdomain\",\"state\":\"active\",\"accountId\":\"$Le_rancher_environment\",\"algorithm\":\"SHA256WITHRSA\",\"cert\":\"$_ccert\",\"certChain\":\"$_cfullchain\",\"key\":\"$_ckey\"}" \
            "$Le_rancher_server/v2-beta/projects/$Le_rancher_environment/certificates/$cert_id"
        )
        _info "Update status code: $response"
        if [ "$response" -lt 199 ] || [ "$response" -gt 300 ]; then
            _err "Curl failed to update cert with id=$cert_id"
            return 1
        fi
    fi
    _info "Certificate successfully deployed"
    return 0
}

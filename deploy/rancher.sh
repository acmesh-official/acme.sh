#!/usr/bin/env sh
# Here is the script to deploy the cert to your rancher-server using the rancher API.
# Uses curl to add cert to your rancher environment.
# Returns 0 when success.
#
# Written by Mihkail Zyablickiy <mikeaggy91@gmail.com>
# 2018
#
####### Variables ##############################
#export RANCHER_ACCESS_KEY=7E6F529DAAFE771A5
#export RANCHER_SECRET_KEY=zahciekuro1eayae7jam3to5Ohf9adaeCooghiep
#export RANCHER_ENVIRONMENT=1a5
#export RANCHER_SERVER=http://rancher-server.example.com

########  Public functions #####################

#domain keyfile certfile cafile fullchain

rancher_deploy() {
    _cdomain="$1"
    # Further $(echo "$1" | sed 's/$/\\n/' | tr -d '\n')
    # Made for iclude cert in var in one line with \n
    _ckey=$(echo "$2" | sed 's/$/\\n/' | tr -d '\n')
    _ccert=$(echo "$3" | sed 's/$/\\n/' | tr -d '\n')
    _cca=$(echo "$4" | sed 's/$/\\n/' | tr -d '\n')
    _cfullchain=$(echo "$5" | sed 's/$/\\n/' | tr -d '\n')
    
    _debug _cdomain "$_cdomain"
    _debug _ckey "$_ckey"
    _debug _ccert "$_ccert"
    _debug _cca "$_cca"
    _debug _cfullchain "$_cfullchain"
    
    # Check software needed
    if ! _exists curl; then
        _err "The command curl is not found."
        return 1
    fi
    
    if ! _exists awk; then
        _err "The command awk is not found."
        return 1
    fi
    
    if ! _exists grep; then
        _err "The command grep is not found."
        return 1
    fi
    
    # Check environment variables and config
    
    if [ -z "$RANCHER_ACCESS_KEY" ]; then
        if [ -z "$Le_rancher_access_key" ]; then
            _err "RANCHER_ACCESS_KEY not defined."
            return 1
        fi
    else
        Le_rancher_access_key="$RANCHER_ACCESS_KEY"
        _savedomainconf Le_rancher_access_key "$Le_rancher_access_key"
    fi
    
    if [ -z "$RANCHER_SECRET_KEY" ]; then
        if [ -z "$Le_rancher_secret_key" ]; then
            _err "RANCHER_SECRET_KEY not defined."
            return 1
        fi
    else
        Le_rancher_secret_key="$RANCHER_SECRET_KEY"
        _savedomainconf Le_rancher_secret_key "$Le_rancher_secret_key"
    fi
    
    if [ -z "$RANCHER_ENVIRONMENT" ]; then
        if [ -z "$Le_rancher_environment" ]; then
            _err "RANCHER_ENVIRONMENT not defined."
            return 1
        fi
    else
        Le_rancher_environment="$RANCHER_ENVIRONMENT"
        _savedomainconf Le_rancher_environment "$Le_rancher_environment"
    fi
    
    if [ -z "$RANCHER_SERVER" ]; then
        if [ -z "$Le_rancher_server" ]; then
            _err "RANCHER_SERVER not defined."
            return 1
        fi
    else
        Le_rancher_server="$RANCHER_SERVER"
        _savedomainconf Le_rancher_server "$Le_rancher_server"
    fi
    
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
    cert_state=$(echo "$id_raw_json" | awk -F='\:' -v RS='\,' "\$id_raw_json~/\"state\"/ {print}" | tr -d "\n\t" | sed -e 's/^"//'  -e 's/"$//' | grep -o "active")
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
        cert_id=$(echo "$id_raw_json" | awk -F='\:' -v RS='\,' "\$id_raw_json~/\"data\"/ {print}" | tr -d "\n\t" | sed -e 's/^"//'  -e 's/"$//' | sed -e 's/data.*"//')
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

#!/usr/bin/env bash

## DNS-01 challenge plugin for ACME & ukraine.com.ua DNS hosting.

## How to usage:
## 1. Create the API token: https://adm.tools/user/api/
## 2. export DNS_UKRAINE_API_KEY="..."
## 3. acme.sh --issue -d your.domain.com.ua --dns dns_ukraine --server letsencrypt --dnssleep 180

## Author: QipDev <dev@qip.cx>
## Report Bugs: https://github.com/sorbing/acme.sh
## Development DNS API plugin for acme.sh: https://github.com/acmesh-official/acme.sh/wiki/DNS-API-Dev-Guide

## Debug API:
## curl -X POST -H "Authorization: Bearer $DNS_UKRAINE_API_KEY" https://adm.tools/action/dns/list/
## curl -X POST -H "Authorization: Bearer $DNS_UKRAINE_API_KEY" -H "Content-Type: application/json" --data "{\"domain_id\":000000}" https://adm.tools/action/dns/records_list/


########  Public functions #####################

## Add the TXT record `_acme-challenge.your.domain` for validation.
## Ukraine DNS API Documentation:
## - https://adm.tools/user/api/#/tab-sandbox/dns/list
## - https://adm.tools/user/api/#/tab-sandbox/dns/record_add
dns_ukraine_add() {
    fulldomain=$1
    txtvalue=$2

    _info "Using dns_ukraine.sh"
    _debug fulldomain "$fulldomain" ## fulldomain='_acme-challenge.your.domain.com.ua'
    _debug txtvalue "$txtvalue"     ## txtvalue='XxXxXxXxX'

    ## Save the credentials to the account conf file
    DNS_UKRAINE_API_KEY="${DNS_UKRAINE_API_KEY:-$(_readaccountconf_mutable DNS_UKRAINE_API_KEY)}"
    if [ -z "$DNS_UKRAINE_API_KEY" ]; then
        DNS_UKRAINE_API_KEY=""
        _err "You don't specify env variable DNS_UKRAINE_API_KEY."
        _err 'Please create your api key and export DNS_UKRAINE_API_KEY="...".'
        return 1
    fi
    _saveaccountconf_mutable DNS_UKRAINE_API_KEY "$DNS_UKRAINE_API_KEY"

    ## Get domain_id
    __dns_ukraine_get_domain_id "$fulldomain"
    _debug ukraine_domain_id "$DOMAIN_ID"

    if test -z "$DOMAIN_ID"; then
        _err "Failed to add the TXT record $fulldomain"
        return 1
    fi

    data="{\"domain_id\":\"$DOMAIN_ID\",\"type\":\"TXT\",\"record\":\"$ACME_CHALLENGE_RECORD\",\"data\":\"$txtvalue\"}"
    response="$(_post "$data" "https://adm.tools/action/dns/record_add/" "" "POST")"
    _debug response "$response"
}

## Remove the TXT record after validation.
## Ukraine DNS API Documentation:
## - https://adm.tools/user/api/#/tab-sandbox/dns/records_list
## - https://adm.tools/user/api/#/tab-sandbox/dns/record_delete
dns_ukraine_rm() {
    fulldomain=$1
    txtvalue=$2
    _info "Using dns_ukraine.sh"
    _debug fulldomain "$fulldomain"
    _debug txtvalue "$txtvalue"

    ## Get domain_id
    __dns_ukraine_get_domain_id "$fulldomain"
    _debug ukraine_domain_id "$DOMAIN_ID"

    response="$(_post "{\"domain_id\":\"$DOMAIN_ID\"}" "https://adm.tools/action/dns/records_list/" "" "POST")"
    subdomain_id=$(echo "$response" | grep -Po '(?<="id":")\d+(?=","domain_id":"[0-9]+","record":"'$ACME_CHALLENGE_RECORD'")')

    if test -z "$subdomain_id"; then
        _err "Failed getting subdomain_id from API ukraine.com.ua to delete the dns record: $ACME_CHALLENGE_RECORD"
        return 1
    fi

    response="$(_post "{\"subdomain_id\":\"$subdomain_id\"}" "https://adm.tools/action/dns/record_delete/" "" "POST")"
    _debug response "$response"
}


####################  Private functions below ##################################

__dns_ukraine_get_domain_id() {
    fulldomain=$1

    export _H1="Authorization: Bearer $DNS_UKRAINE_API_KEY"
    export _H2="Accept: application/json"
    export _H3="Content-Type: application/json"

    local response="$(_post "" "https://adm.tools/action/dns/list/" "" "POST" "application/json")"

    local subdomain=$(echo "$fulldomain" | sed -E 's/^_acme-challenge\.//')
    local topdomain=$subdomain

    DOMAIN_ID=$(echo "$response" | grep -Po '(?<="'$topdomain'":{"domain_id":)\d+')
    if test -z "$DOMAIN_ID"; then
        topdomain=$(echo "$topdomain" | sed -E 's/^[^\.]+\.//')
        DOMAIN_ID=$(echo "$response" | grep -Po '(?<="'$topdomain'":{"domain_id":)\d+')

        if test -z "$DOMAIN_ID"; then
            topdomain=$(echo "$topdomain" | sed -E 's/^[^\.]+\.//')
            DOMAIN_ID=$(echo "$response" | grep -Po '(?<="'$topdomain'":{"domain_id":)\d+')
        fi
    fi

    if test -z "$DOMAIN_ID"; then
        _err "Failed getting domain_id from API ukraine.com.ua"
        return 1
    fi

    ACME_CHALLENGE_RECORD=$(echo "$fulldomain" | sed -E "s/\.$topdomain$//")  ## _acme-challenge.subdomain
}

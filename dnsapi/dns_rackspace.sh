#!/bin/bash

# vim: tabstop=4 shiftwidth=4 softtabstop=4 expandtab:


# See:
# https://developer.rackspace.com/docs/cloud-dns/v1/api-reference/

# Rackspace API authentication:
# Create file .rackspace.auth with your Rackspace API user credentials.
# The API user needs permission: DNS, Creator (View, Create, Edit) for adding to work.
# For deletion to work: DNS, Admin (View, Create, Edit, Delete) is needed.
# Example of a .rackspace.auth file:
# { "user": "my rackspace user", "key": "my rackspace API key" }

# Example usage:
# ./acme.sh --keylength 4096 --issue -d "example.com" --dns dns_rackspace --dnssleep 10


########  Public functions #####################

RACKSPACE_DOMAIN=0
RACKSPACE_DOMAIN_ID=0
RACKSPACE_RETRY=0

#Usage: dns_add _acme-challenge.www.domain.com "XKrxp6q0HG9i01zxXp5CPBs"
dns_rackspace_add() {
    local fulldomain=$1
    local txtvalue=$2
    _info "Using Rackspace Cloud DNS API to add challenge into $fulldomain"
    _debug fulldomain "$fulldomain"
    _debug txtvalue "$txtvalue"

    _rackspace_sanity
    _rackspace_authenticate

    # At this point, there is an authenticated session token that we can use.
    local token_file=/tmp/.acme.rackspace.$EUID.token
    local token=$(jq -r ".access.token.id" "$token_file")
    local api_url=$(jq -r ".access.serviceCatalog[0].endpoints[0].publicURL" "$token_file")
    local json_data

    # Try to find a domain from Rackspace that will have the new TXT-record.
    # Start by stripping the hard-coded word "_acme-challenge." from the FQDN.
    # Remainin record is a potential domain name in Rackspace.
    if [[ ! "$fulldomain" =~ ^_acme-challenge\.(.+)$ ]]; then
        _err "Failed to extract domain name from $fulldomain. Fatal error, cannot continue."
        exit 1
    fi

    _rackspace_get_domain "${BASH_REMATCH[1]}" "$api_url"
    if [ $? -gt 0 ]; then
        # If the internal operation fails, an error will be emitted in the _rackspace_get_domain().
        # Ultimately, there is no way this operation can continue.
        exit 1
    fi

    local text_rr=${fulldomain%.$RACKSPACE_DOMAIN}
    if [ "$fulldomain" == "$text_rr" ]; then
        _err "Found domain $RACKSPACE_DOMAIN for $fulldomain, but failed to create a RR for it. Fatal error, cannot continue."
        exit 1
    fi
    _info "Using domain $RACKSPACE_DOMAIN on Rackspace Cloud DNS. Adding $text_rr."

    # Add a record
    read -r -d '' json_data <<END_OF_JSON
{
  "records" : [{
    "name" : "$fulldomain",
    "type" : "TXT",
    "data" : "$txtvalue"
  }]
}
END_OF_JSON

    _debug "Rackspace API URL to use for adding: $api_url/domains/$RACKSPACE_DOMAIN_ID/records"

    json_data=$(curl --silent -X POST --data "$json_data" -H "X-Auth-Token: $token" -H "Content-Type: application/json" -H "Accept: application/json" "$api_url/domains/$RACKSPACE_DOMAIN_ID/records")
    if [ $? -gt 0 ]; then
        _err "Failed to add record to Rackspace Cloud DNS. Fatal error, cannot continue."
        exit 1
    fi

    local status=$(echo "$json_data" | jq -r '.status')
    if [ -z "$status" ] || [ "$status" == "null" ]; then
        local code=$(echo "$json_data" | jq -r '."error-message"')
        if [ -n "$code" ] && [ "$code" != "null" ]; then
            _err "Failed to add record to Rackspace Cloud DNS. No permission to add! Fatal error: $code"
        else
            code=$(echo "$json_data" | jq -r .code)
            _err "Failed to add record to Rackspace Cloud DNS. Status: HTTP/$code"
        fi
        exit 1
    fi
    if [ "$status" == "RUNNING" ]; then
        local callback_url=$(echo "$json_data" | jq -r '.callbackUrl')
        if [ -z "$callback_url" ]; then
            _err "Attempt to add record to Rackspace Cloud DNS most likely failed. There is no callback URL to query the operation status from."
            return 1
        fi
        while [ "$status" == "RUNNING" ]; do
            sleep 2
            json_data=$(curl --silent -H "X-Auth-Token: $token" "$callback_url")
            if [ $? -gt 0 ]; then
                _err "Failed to query DNS add status from $callback_url"
                return 1
            fi
            status=$(echo "$json_data" | jq -r '.status')
        done

        if [ "$status" == "ERROR" ]; then
            _err "Failed to add record to Rackspace Cloud DNS, add status is: $status."
            # See, if the add failed because the record already exists.
            json_data=$(curl --silent -H "X-Auth-Token: $token" -H "Accept: application/json" "$api_url/domains/$RACKSPACE_DOMAIN_ID/records?type=TXT&name=$fulldomain")
            if [ $? == 0 ] && [ -n "$json_data" ] && [ $RACKSPACE_RETRY == 0 ] ; then
                # We have something ...
                local record_id=$(echo "$json_data" | jq -r '.records[0].id')
                if [ -n "$record_id" ] || [ "$record_id" != "null" ]; then
                    # Attempt to delete the record
                    _info "Found existing record! Deleting record $record_id on domain $RACKSPACE_DOMAIN."
                    json_data=$(curl --silent -X DELETE -H "X-Auth-Token: $token" -H "Accept: application/json" "$api_url/domains/$RACKSPACE_DOMAIN_ID/records/$record_id")
                    local status=$(echo "$json_data" | jq -r '.status')
                    if [ "$status" == "RUNNING" ]; then
                        _info "Succesfully deleted the record. Retrying ..."
                        RACKSPACE_RETRY=1
                        sleep 3

                        # Call myself with same arguments.
                        dns_rackspace_add "$1" "$2"
                        return $?
                    else
                        _err "Failed to delete the record. Nothing else to try."
                    fi
                fi
            fi

            # end if $status = ERROR
        fi
    fi
    if [ "$status" != "COMPLETED" ]; then
        _err "Failed to add record to Rackspace Cloud DNS, add status is: $status."
        return 1
    fi

    return 0
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_rackspace_rm() {
    local fulldomain=$1
    local txtvalue=$2
    _info "Using Rackspace Cloud DNS API to remove challenge $fulldomain"
    _debug fulldomain "$fulldomain"
    _debug txtvalue "$txtvalue"

    _rackspace_sanity
    _rackspace_authenticate

    # At this point, there is an authenticated session token that we can use.
    local token_file=/tmp/.acme.rackspace.$EUID.token
    local token=$(jq -r ".access.token.id" "$token_file")
    local api_url=$(jq -r ".access.serviceCatalog[0].endpoints[0].publicURL" "$token_file")
    local json_data

    # Try to find a domain from Rackspace that will have an existing TXT-record.
    if [[ ! "$fulldomain" =~ ^_acme-challenge\.(.+)$ ]]; then
        _err "Failed to extract domain name from $fulldomain."
        return 1
    fi

    _rackspace_get_domain "${BASH_REMATCH[1]}" "$api_url"
    if [ $? -gt 0 ]; then
        # If the internal operation fails, an error will be emitted in the _rackspace_get_domain().
        return 1
    fi

    local text_rr=${fulldomain%.$RACKSPACE_DOMAIN}
    _info "Using domain $RACKSPACE_DOMAIN on Rackspace Cloud DNS. Trying to find and remove $text_rr."

    _debug "Rackspace API URL to use for searching: $api_url/domains/$RACKSPACE_DOMAIN_ID/records"

    # Go search for TXT-records
    json_data=$(curl --silent -H "X-Auth-Token: $token" -H "Accept: application/json" "$api_url/domains/$RACKSPACE_DOMAIN_ID/records?type=TXT&name=$fulldomain")
    if [ $? -gt 0 ]; then
        _err "Failed to search for TXT-record $fulldomain on Rackspace Cloud DNS."
        return 1
    fi

    local record_id=$(echo "$json_data" | jq -r '.records[0].id')
    if [ -z "$record_id" ] || [ "$record_id" == "null" ]; then
        _err "TXT-record $fulldomain was not found. Nothing to delete."
        return 1
    fi

    _info "Deleting record $record_id on domain $RACKSPACE_DOMAIN."
    json_data=$(curl --silent -X DELETE -H "X-Auth-Token: $token" -H "Accept: application/json" "$api_url/domains/$RACKSPACE_DOMAIN_ID/records/$record_id")
    if [ $? -gt 0 ]; then
        _err "Failed to delete record to Rackspace Cloud DNS. API-call failed."
        return 1
    fi

    local status=$(echo "$json_data" | jq -r '.status')
    if [ -z "$status" ] || [ "$status" == "null" ]; then
        status=$(echo "$json_data" | jq -r '."error-message"')
        if [ -n "$status" ] && [ "$status" != "null" ]; then
            _err "Failed to delete record to Rackspace Cloud DNS. No permission to delete! Error: $status"
        else
            _err "Failed to delete record to Rackspace Cloud DNS. Unknown reason."
        fi
        return 1
    fi
    if [ "$status" != "RUNNING" ]; then
        _err "Failed to delete record to Rackspace Cloud DNS."
        return 1
    fi

    return 0
}

####################  Private functions below ##################################


_rackspace_sanity() {
    local needed=('curl' 'jq')
    local cmd

    for cmd in "${needed[@]}"; do
        which "$cmd" >& /dev/null
        if [ $? -gt 0 ]; then
            _err "Rackspace Cloud DNS API needs command: $cmd"
            exit 1
        fi
    done
}

_rackspace_get_domain() {
    local domain_to_use="$1"
    local api_url="$2"
    local domain_to_check

    # Get list of all domains this API user can manage.
    local json_data=$(curl --silent -H "X-Auth-Token: $token" -H "Accept: application/json" "$api_url/domains")
    if [ $? -gt 0 ] || [ -z "$json_data" ]; then
        _err "Failed to retrieve domain list from Rackspace Cloud DNS API. Fatal error, cannot continue."
        return 1
    fi
    local status=$(echo "$json_data" | jq -r '."error-message"')
    if [ -n "$status" ] && [ "$status" != "null" ]; then
        _err "Configured user has no permission to retrieve domain list from Rackspace Cloud DNS API. Fatal error, cannot continue."
        return 1
    fi 

    # Iterate the domain list reverse-sorted. That will do a longest match comparison if there are
    # subdomain used for the request, but will also match a shorter domain.
    local matching_domain_idx hostmaster_email
    while [ -z "$matching_domain_idx" ] && [[ $domain_to_use =~ \..+$ ]]; do
        local domain_idx=0
        while [ "$domain_to_check" != "null" ]; do
            domain_to_check=$(echo "$json_data" | jq -r '.domains|sort_by(.name)|reverse|.['$domain_idx'].name')
            if [ "$domain_to_use" == "$domain_to_check" ]; then
                matching_domain_idx=$domain_idx
                hostmaster_email=$(echo "$json_data" | jq -r '.domains|sort_by(.name)|reverse|.['$domain_idx'].emailAddress')
                RACKSPACE_DOMAIN="$domain_to_use"
                RACKSPACE_DOMAIN_ID=$(echo "$json_data" | jq -r '.domains|sort_by(.name)|reverse|.['$domain_idx'].id')
                break
            fi
            domain_idx=$(( domain_idx+1 ))
        done
        if [ -z "$matching_domain_idx" ]; then
            # Eat out one level from the domain, if nothing found
            domain_to_use=${domain_to_use#*.}
            domain_to_check=''
        fi
    done
    if [ -z "$matching_domain_idx" ]; then
        _err "Failed to find the domain for $fulldomain to add a record. Fatal error, cannot continue."
        return 1
    fi
    if [ -z "$RACKSPACE_DOMAIN_ID" ] || [ "$RACKSPACE_DOMAIN_ID" == "null" ]; then
        _err "Failed to get domain ID for domain $domain_to_use. Fatal error, cannot add record."
        return 1
    fi

    return 0
}

_rackspace_authenticate() {
    local token_file=/tmp/.acme.rackspace.$EUID.token

    if [ ! -e "$token_file" ]; then
        _rackspace_get_token
    fi

    local token=$(jq -r --exit-status .access.token.id "$token_file")
    if [ $? -gt 0 ]; then
        _rackspace_get_token
        token=$(jq -r --exit-status .access.token.id "$token_file")
        if [ $? -gt 0 ]; then
            _err "Failed to read access token from $token_file"
            exit 1
        fi
    fi

    curl --silent -H "X-Auth-Token: $token" "https://identity.api.rackspacecloud.com/v2.0/tokens/$token" | jq --exit-status .access.token.tenant > /dev/null
    if [ $? -gt 0 ]; then
        _err "Failed to verify access token from $token_file"
        exit 1
    fi
}

_rackspace_get_token() {
    local token_file=/tmp/.acme.rackspace.$EUID.token
    local creds_file user key
    local auth_json stat umask code

    creds_file="$_SCRIPT_HOME/.rackspace.auth"
    if [ ! -e "$creds_file" ]; then
        creds_file="$LE_WORKING_DIR/.rackspace.auth"
        if [ ! -e "$creds_file" ]; then
            _err "Rackspace Cloud DNS API needs credentials in .rackspace.auth file in $_SCRIPT_HOME/ or $LE_WORKING_DIR/"
            exit 1
        fi
    fi

    user=$(jq -r .user "$creds_file")
    key=$(jq -r .key "$creds_file")
    if [ -z "$user" ] || [ -z "$key" ]; then
        _err "Failed to read Rackspace Cloud DNS API credentials from $creds_file"
        exit 1
    fi

    umask=$(umask)
    umask 0077
    auth_json="{\"auth\":{\"RAX-KSKEY:apiKeyCredentials\":{\"username\":\"$user\",\"apiKey\":\"$key\"}}}"
    curl --silent https://identity.api.rackspacecloud.com/v2.0/tokens -X POST -d "$auth_json" -H "Content-type: application/json" > $token_file
    stat=$?
    umask $umask
    if [ $stat -gt 0 ]; then
        _err "Failed to make an authentication request into Rackspace Cloud DNS API"
        exit 1
    fi
    jq . $token_file > /dev/null
    if [ $? -gt 0 ]; then
        _err "Failed to retrieve authentication JSON from Rackspace Cloud DNS API"
        exit 1
    fi

    code=$(jq -r --exit-status .access.token.tenant "$token_file")
    stat=$?
    if [ $stat -gt 0 ]; then
        code=$(jq -r .unauthorized.code "$token_file")
        _err "Failed to authenticate into Rackspace Cloud DNS API ($stat). Status: HTTP/$code"
        rm -f "$token_file"
        exit 1
    fi
}


#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_timeweb_info='Timeweb.Cloud
Site: Timeweb.Cloud
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_timeweb
Options:
 TW_Token API JWT token. Get it from the control panel at https://timeweb.cloud/my/api-keys
Issues: github.com/acmesh-official/acme.sh/issues/5140
Author: Nikolay Pronchev <@nikolaypronchev>
'

TW_Api="https://api.timeweb.cloud/api/v1"

################  Public functions ################

# Adds an ACME DNS-01 challenge DNS TXT record via the Timeweb Cloud API.
#
# Param1: The ACME DNS-01 challenge FQDN.
# Param2: The value of the ACME DNS-01 challenge TXT record.
#
# Example: dns_timeweb_add "_acme-challenge.sub.domain.com" "D-52Wm...4uYM"
dns_timeweb_add() {
  _debug "$(__green "Timeweb DNS API"): \"dns_timeweb_add\" started."

  _timeweb_set_acme_fqdn "$1" || return 1
  _timeweb_set_acme_txt "$2" || return 1
  _timeweb_check_token || return 1
  _timeweb_split_acme_fqdn || return 1
  _timeweb_dns_txt_add || return 1

  _debug "$(__green "Timeweb DNS API"): \"dns_timeweb_add\" finished."
}

# Removes a DNS TXT record via the Timeweb Cloud API.
#
# Param1: The ACME DNS-01 challenge FQDN.
# Param2: The value of the ACME DNS-01 challenge TXT record.
#
# Example: dns_timeweb_rm "_acme-challenge.sub.domain.com" "D-52Wm...4uYM"
dns_timeweb_rm() {
  _debug "$(__green "Timeweb DNS API"): \"dns_timeweb_rm\" started."

  _timeweb_set_acme_fqdn "$1" || return 1
  _timeweb_set_acme_txt "$2" || return 1
  _timeweb_check_token || return 1
  _timeweb_split_acme_fqdn || return 1
  _timeweb_get_dns_txt || return 1
  _timeweb_dns_txt_remove || return 1

  _debug "$(__green "Timeweb DNS API"): \"dns_timeweb_rm\" finished."
}

################  Private functions ################

# Checks and sets the ACME DNS-01 challenge FQDN.
#
# Param1: The ACME DNS-01 challenge FQDN.
#
# Example: _timeweb_set_acme_fqdn "_acme-challenge.sub.domain.com"
#
# Sets the "Acme_Fqdn" variable (_acme-challenge.sub.domain.com)
_timeweb_set_acme_fqdn() {
  Acme_Fqdn=$1
  _debug "Setting ACME DNS-01 challenge FQDN \"$Acme_Fqdn\"."
  [ -z "$Acme_Fqdn" ] && {
    _err "ACME DNS-01 challenge FQDN is empty."
    return 1
  }
  return 0
}

# Checks and sets the value of the ACME DNS-01 challenge TXT record.
#
# Param1: Value of the ACME DNS-01 challenge TXT record.
#
# Example: _timeweb_set_acme_txt "D-52Wm...4uYM"
#
# Sets the "Acme_Txt" variable to the provided value (D-52Wm...4uYM)
_timeweb_set_acme_txt() {
  Acme_Txt=$1
  _debug "Setting the value of the ACME DNS-01 challenge TXT record to \"$Acme_Txt\"."
  [ -z "$Acme_Txt" ] && {
    _err "ACME DNS-01 challenge TXT record value is empty."
    return 1
  }
  return 0
}

# Checks if the Timeweb Cloud API JWT token is present (refer to the script description).
# Adds or updates the token in the acme.sh account configuration.
_timeweb_check_token() {
  _debug "Checking for the presence of the Timeweb Cloud API JWT token."

  TW_Token="${TW_Token:-$(_readaccountconf_mutable TW_Token)}"

  [ -z "$TW_Token" ] && {
    _err "Timeweb Cloud API JWT token was not found."
    return 1
  }

  _saveaccountconf_mutable TW_Token "$TW_Token"
}

# Divides the ACME DNS-01 challenge FQDN into its main domain and subdomain components.
_timeweb_split_acme_fqdn() {
  _debug "Trying to divide \"$Acme_Fqdn\" into its main domain and subdomain components."

  TW_Page_Limit=100
  TW_Page_Offset=0
  TW_Domains_Returned=""

  while [ -z "$TW_Domains_Returned" ] || [ "$TW_Domains_Returned" -ge "$TW_Page_Limit" ]; do

    _timeweb_list_domains "$TW_Page_Limit" "$TW_Page_Offset" || return 1

    # Remove the 'subdomains' subarray to prevent confusion with FQDNs.

    TW_Domains=$(
      echo "$TW_Domains" |
        sed 's/"subdomains":\[[^]]*]//g'
    )

    [ -z "$TW_Domains" ] && {
      _err "Failed to parse the list of domains."
      return 1
    }

    while
      TW_Domain=$(
        echo "$TW_Domains" |
          sed -n 's/.*{[^{]*"fqdn":"\([^"]*\)"[^}]*}.*/\1/p'
      )

      [ -n "$TW_Domain" ] && {
        _timeweb_is_main_domain "$TW_Domain" && return 0

        TW_Domains=$(
          echo "$TW_Domains" |
            sed 's/{\([^{]*"fqdn":"'"$TW_Domain"'"[^}]*\)}//'
        )
        continue
      }
    do :; done

    TW_Page_Offset=$(_math "$TW_Page_Offset" + "$TW_Page_Limit")
  done

  _err "Failed to divide \"$Acme_Fqdn\" into its main domain and subdomain components."
  return 1
}

# Searches for a previously added DNS TXT record.
#
# Sets the "TW_Dns_Txt_Id" variable.
_timeweb_get_dns_txt() {
  _debug "Trying to locate a DNS TXT record with the value \"$Acme_Txt\"."

  TW_Page_Limit=100
  TW_Page_Offset=0
  TW_Dns_Records_Returned=""

  while [ -z "$TW_Dns_Records_Returned" ] || [ "$TW_Dns_Records_Returned" -ge "$TW_Page_Limit" ]; do

    _timeweb_list_dns_records "$TW_Page_Limit" "$TW_Page_Offset" || return 1

    while
      Dns_Record=$(
        echo "$TW_Dns_Records" |
          sed -n 's/.*{\([^{]*{[^{]*'"$Acme_Txt"'[^}]*}[^}]*\)}.*/\1/p'
      )

      [ -n "$Dns_Record" ] && {
        _timeweb_is_added_txt "$Dns_Record" && return 0

        TW_Dns_Records=$(
          echo "$TW_Dns_Records" |
            sed 's/{\([^{]*{[^{]*'"$Acme_Txt"'[^}]*}[^}]*\)}//'
        )
        continue
      }
    do :; done

    TW_Page_Offset=$(_math "$TW_Page_Offset" + "$TW_Page_Limit")
  done

  _err "DNS TXT record was not found."
  return 1
}

# Lists domains via the Timeweb Cloud API.
#
# Param 1: Limit for listed domains.
# Param 2: Offset for domains list.
#
# Sets the "TW_Domains" variable.
# Sets the "TW_Domains_Returned" variable.
_timeweb_list_domains() {
  _debug "Listing domains via Timeweb Cloud API. Limit: $1, offset: $2."

  export _H1="Authorization: Bearer $TW_Token"

  if ! TW_Domains=$(_get "$TW_Api/domains?limit=$1&offset=$2"); then
    _err "The request to the Timeweb Cloud API failed."
    return 1
  fi

  [ -z "$TW_Domains" ] && {
    _err "Empty response from the Timeweb Cloud API."
    return 1
  }

  TW_Domains_Returned=$(
    echo "$TW_Domains" |
      sed 's/.*"meta":{"total":\([0-9]*\)[^0-9].*/\1/'
  )

  [ -z "$TW_Domains_Returned" ] && {
    _err "Failed to extract the total count of domains."
    return 1
  }

  [ "$TW_Domains_Returned" -eq "0" ] && {
    _err "Domains are missing."
    return 1
  }

  _debug "Domains returned by Timeweb Cloud API: $TW_Domains_Returned."
}

# Lists domain DNS records via the Timeweb Cloud API.
#
# Param 1: Limit for listed DNS records.
# Param 2: Offset for DNS records list.
#
# Sets the "TW_Dns_Records" variable.
# Sets the "TW_Dns_Records_Returned" variable.
_timeweb_list_dns_records() {
  _debug "Listing domain DNS records via the Timeweb Cloud API. Limit: $1, offset: $2."

  export _H1="Authorization: Bearer $TW_Token"

  if ! TW_Dns_Records=$(_get "$TW_Api/domains/$TW_Main_Domain/dns-records?limit=$1&offset=$2"); then
    _err "The request to the Timeweb Cloud API failed."
    return 1
  fi

  [ -z "$TW_Dns_Records" ] && {
    _err "Empty response from the Timeweb Cloud API."
    return 1
  }

  TW_Dns_Records_Returned=$(
    echo "$TW_Dns_Records" |
      sed 's/.*"meta":{"total":\([0-9]*\)[^0-9].*/\1/'
  )

  [ -z "$TW_Dns_Records_Returned" ] && {
    _err "Failed to extract the total count of DNS records."
    return 1
  }

  [ "$TW_Dns_Records_Returned" -eq "0" ] && {
    _err "DNS records are missing."
    return 1
  }

  _debug "DNS records returned by Timeweb Cloud API: $TW_Dns_Records_Returned."
}

# Verifies whether the domain is the primary domain for the ACME DNS-01 challenge FQDN.
# The requirement is that the provided domain is the top-level domain
# for the ACME DNS-01 challenge FQDN.
#
# Param 1: Domain object returned by Timeweb Cloud API.
#
# Sets the "TW_Main_Domain" variable (e.g. "_acme-challenge.s1.domain.co.uk" → "domain.co.uk").
# Sets the "TW_Subdomains" variable (e.g. "_acme-challenge.s1.domain.co.uk" → "_acme-challenge.s1").
_timeweb_is_main_domain() {
  _debug "Checking if \"$1\" is the main domain of the ACME DNS-01 challenge FQDN."

  [ -z "$1" ] && {
    _debug "Failed to extract FQDN. Skipping domain."
    return 1
  }

  ! echo ".$Acme_Fqdn" | grep -qi "\.$1$" && {
    _debug "Domain does not match the ACME DNS-01 challenge FQDN. Skipping domain."
    return 1
  }

  TW_Main_Domain=$1
  TW_Subdomains=$(
    echo "$Acme_Fqdn" |
      sed "s/\.*.\{${#1}\}$//"
  )

  _debug "Matched domain. ACME DNS-01 challenge FQDN  split as [$TW_Subdomains].[$TW_Main_Domain]."
  return 0
}

# Verifies whether a DNS record was previously added based on the following criteria:
# - The value matches the ACME DNS-01 challenge TXT record value;
# - The record type is TXT;
# - The subdomain matches the ACME DNS-01 challenge FQDN.
#
# Param 1: DNS record object returned by Timeweb Cloud API.
#
# Sets the "TW_Dns_Txt_Id" variable.
_timeweb_is_added_txt() {
  _debug "Checking if \"$1\" is a previously added DNS TXT record."

  echo "$1" | grep -qv '"type":"TXT"' && {
    _debug "Not a TXT record. Skipping the record."
    return 1
  }

  if [ -n "$TW_Subdomains" ]; then
    echo "$1" | grep -qvi "\"subdomain\":\"$TW_Subdomains\"" && {
      _debug "Subdomains do not match. Skipping the record."
      return 1
    }
  else
    echo "$1" | grep -q '"subdomain\":"..*"' && {
      _debug "Subdomains do not match. Skipping the record."
      return 1
    }
  fi

  TW_Dns_Txt_Id=$(
    echo "$1" |
      sed 's/.*"id":\([0-9]*\)[^0-9].*/\1/'
  )

  [ -z "$TW_Dns_Txt_Id" ] && {
    _debug "Failed to extract the DNS record ID. Skipping the record."
    return 1
  }

  _debug "Matching DNS TXT record ID is \"$TW_Dns_Txt_Id\"."
  return 0
}

# Adds a DNS TXT record via the Timeweb Cloud API.
_timeweb_dns_txt_add() {
  _debug "Adding a new DNS TXT record via the Timeweb Cloud API."

  export _H1="Authorization: Bearer $TW_Token"
  export _H2="Content-Type: application/json"

  if ! TW_Response=$(
    _post "{
      \"subdomain\":\"$TW_Subdomains\",
      \"type\":\"TXT\",
      \"value\":\"$Acme_Txt\"
    }" \
      "$TW_Api/domains/$TW_Main_Domain/dns-records"
  ); then
    _err "The request to the Timeweb Cloud API failed."
    return 1
  fi

  [ -z "$TW_Response" ] && {
    _err "An unexpected empty response was received from the Timeweb Cloud API."
    return 1
  }

  TW_Dns_Txt_Id=$(
    echo "$TW_Response" |
      sed 's/.*"id":\([0-9]*\)[^0-9].*/\1/'
  )

  [ -z "$TW_Dns_Txt_Id" ] && {
    _err "Failed to extract the DNS TXT Record ID."
    return 1
  }

  _debug "DNS TXT record has been added. ID: \"$TW_Dns_Txt_Id\"."
}

# Removes a DNS record via the Timeweb Cloud API.
_timeweb_dns_txt_remove() {
  _debug "Removing DNS record via the Timeweb Cloud API."

  export _H1="Authorization: Bearer $TW_Token"

  if ! TW_Response=$(
    _post \
      "" \
      "$TW_Api/domains/$TW_Main_Domain/dns-records/$TW_Dns_Txt_Id" \
      "" \
      "DELETE"
  ); then
    _err "The request to the Timeweb Cloud API failed."
    return 1
  fi

  [ -n "$TW_Response" ] && {
    _err "Received an unexpected response body from the Timeweb Cloud API."
    return 1
  }

  _debug "DNS TXT record with ID \"$TW_Dns_Txt_Id\" has been removed."
}

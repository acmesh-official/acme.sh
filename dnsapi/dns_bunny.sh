#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_bunny_info='Bunny.net
Site: Bunny.net/dns/
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_bunny
Options:
 BUNNY_API_KEY API Key
Issues: github.com/acmesh-official/acme.sh/issues/4296
Author: <nosilver4u@ewww.io>
'

#####################  Public functions  #####################

## Create the text record for validation.
## Usage: fulldomain txtvalue
## EG: "_acme-challenge.www.other.domain.com" "XKrxpRBosdq0HG9i01zxXp5CPBs"
dns_bunny_add() {
  fulldomain="$(echo "$1" | _lower_case)"
  txtvalue=$2

  BUNNY_API_KEY="${BUNNY_API_KEY:-$(_readaccountconf_mutable BUNNY_API_KEY)}"
  # Check if API Key is set
  if [ -z "$BUNNY_API_KEY" ]; then
    BUNNY_API_KEY=""
    _err "You did not specify Bunny.net API key."
    _err "Please export BUNNY_API_KEY and try again."
    return 1
  fi

  _info "Using Bunny.net dns validation - add record"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  ## save the env vars (key and domain split location) for later automated use
  _saveaccountconf_mutable BUNNY_API_KEY "$BUNNY_API_KEY"

  ## split the domain for Bunny API
  if ! _get_base_domain "$fulldomain"; then
    _err "domain not found in your account for addition"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _debug _domain_id "$_domain_id"

  ## Set the header with our post type and auth key
  export _H1="Accept: application/json"
  export _H2="AccessKey: $BUNNY_API_KEY"
  export _H3="Content-Type: application/json"
  PURL="https://api.bunny.net/dnszone/$_domain_id/records"
  PBODY='{"Id":'$_domain_id',"Type":3,"Name":"'$_sub_domain'","Value":"'$txtvalue'","ttl":120}'

  _debug PURL "$PURL"
  _debug PBODY "$PBODY"

  ## the create request - POST
  ## args: BODY, URL, [need64, httpmethod]
  response="$(_post "$PBODY" "$PURL" "" "PUT")"

  ## check response
  if [ "$?" != "0" ]; then
    _err "error in response: $response"
    return 1
  fi
  _debug2 response "$response"

  ## finished correctly
  return 0
}

## Remove the txt record after validation.
## Usage: fulldomain txtvalue
## EG: "_acme-challenge.www.other.domain.com" "XKrxpRBosdq0HG9i01zxXp5CPBs"
dns_bunny_rm() {
  fulldomain="$(echo "$1" | _lower_case)"
  txtvalue=$2

  BUNNY_API_KEY="${BUNNY_API_KEY:-$(_readaccountconf_mutable BUNNY_API_KEY)}"
  # Check if API Key Exists
  if [ -z "$BUNNY_API_KEY" ]; then
    BUNNY_API_KEY=""
    _err "You did not specify Bunny.net API key."
    _err "Please export BUNNY_API_KEY and try again."
    return 1
  fi

  _info "Using Bunny.net dns validation - remove record"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  ## split the domain for Bunny API
  if ! _get_base_domain "$fulldomain"; then
    _err "Domain not found in your account for TXT record removal"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _debug _domain_id "$_domain_id"

  ## Set the header with our post type and key auth key
  export _H1="Accept: application/json"
  export _H2="AccessKey: $BUNNY_API_KEY"
  ## get URL for the list of DNS records
  GURL="https://api.bunny.net/dnszone/$_domain_id"

  ## 1) Get the domain/zone records
  ## the fetch request - GET
  ## args: URL, [onlyheader, timeout]
  domain_list="$(_get "$GURL")"

  ## check response
  if [ "$?" != "0" ]; then
    _err "error in domain_list response: $domain_list"
    return 1
  fi
  _debug2 domain_list "$domain_list"

  ## 2) search through records
  ## check for what we are looking for: "Type":3,"Value":"$txtvalue","Name":"$_sub_domain"
  record="$(echo "$domain_list" | _egrep_o "\"Id\"\s*\:\s*\"*[0-9]+\"*,\s*\"Type\"[^}]*\"Value\"\s*\:\s*\"$txtvalue\"[^}]*\"Name\"\s*\:\s*\"$_sub_domain\"")"

  if [ -n "$record" ]; then

    ## We found records
    rec_ids="$(echo "$record" | _egrep_o "Id\"\s*\:\s*\"*[0-9]+" | _egrep_o "[0-9]+")"
    _debug rec_ids "$rec_ids"
    if [ -n "$rec_ids" ]; then
      echo "$rec_ids" | while IFS= read -r rec_id; do
        ## delete the record
        ## delete URL for removing the one we dont want
        DURL="https://api.bunny.net/dnszone/$_domain_id/records/$rec_id"

        ## the removal request - DELETE
        ## args: BODY, URL, [need64, httpmethod]
        response="$(_post "" "$DURL" "" "DELETE")"

        ## check response (sort of)
        if [ "$?" != "0" ]; then
          _err "error in remove response: $response"
          return 1
        fi
        _debug2 response "$response"

      done
    fi
  fi

  ## finished correctly
  return 0
}

#####################  Private functions below  #####################

## Split the domain provided into the "base domain" and the "start prefix".
## This function searches for the longest subdomain in your account
## for the full domain given and splits it into the base domain (zone)
## and the prefix/record to be added/removed
## USAGE: fulldomain
## EG: "_acme-challenge.two.three.four.domain.com"
## returns
## _sub_domain="_acme-challenge.two"
## _domain="three.four.domain.com" *IF* zone "three.four.domain.com" exists
## _domain_id=234
## if only "domain.com" exists it will return
## _sub_domain="_acme-challenge.two.three.four"
## _domain="domain.com"
## _domain_id=234
_get_base_domain() {
  # args
  fulldomain="$(echo "$1" | _lower_case)"
  _debug fulldomain "$fulldomain"

  # domain max legal length = 253
  MAX_DOM=255
  page=1

  ## get a list of domains for the account to check thru
  ## Set the headers
  export _H1="Accept: application/json"
  export _H2="AccessKey: $BUNNY_API_KEY"
  _debug BUNNY_API_KEY "$BUNNY_API_KEY"
  ## get URL for the list of domains
  ## may get: "links":{"pages":{"last":".../v2/domains/DOM/records?page=2","next":".../v2/domains/DOM/records?page=2"}}
  DOMURL="https://api.bunny.net/dnszone"

  ## while we dont have a matching domain we keep going
  while [ -z "$found" ]; do
    ## get the domain list (current page)
    domain_list="$(_get "$DOMURL")"

    ## check response
    if [ "$?" != "0" ]; then
      _err "error in domain_list response: $domain_list"
      return 1
    fi
    _debug2 domain_list "$domain_list"

    i=1
    while [ "$i" -gt 0 ]; do
      ## get next longest domain
      _domain=$(printf "%s" "$fulldomain" | cut -d . -f "$i"-"$MAX_DOM")
      ## check we got something back from our cut (or are we at the end)
      if [ -z "$_domain" ]; then
        break
      fi
      ## we got part of a domain back - grep it out
      found="$(echo "$domain_list" | _egrep_o "\"Id\"\s*:\s*\"*[0-9]+\"*,\s*\"Domain\"\s*\:\s*\"$_domain\"")"
      ## check if it exists
      if [ -n "$found" ]; then
        ## exists - exit loop returning the parts
        sub_point=$(_math "$i" - 1)
        _sub_domain=$(printf "%s" "$fulldomain" | cut -d . -f 1-"$sub_point")
        _domain_id="$(echo "$found" | _egrep_o "Id\"\s*\:\s*\"*[0-9]+" | _egrep_o "[0-9]+")"
        _debug _domain_id "$_domain_id"
        _debug _domain "$_domain"
        _debug _sub_domain "$_sub_domain"
        found=""
        return 0
      fi
      ## increment cut point $i
      i=$(_math "$i" + 1)
    done

    if [ -z "$found" ]; then
      page=$(_math "$page" + 1)
      nextpage="https://api.bunny.net/dnszone?page=$page"
      ## Find the next page if we don't have a match.
      hasnextpage="$(echo "$domain_list" | _egrep_o "\"HasMoreItems\"\s*:\s*true")"
      if [ -z "$hasnextpage" ]; then
        _err "No record and no nextpage in Bunny.net domain search."
        found=""
        return 1
      fi
      _debug2 nextpage "$nextpage"
      DOMURL="$nextpage"
    fi

  done

  ## We went through the entire domain zone list and didn't find one that matched.
  ## If we ever get here, something is broken in the code...
  _err "Domain not found in Bunny.net account, but we should never get here!"
  found=""
  return 1
}

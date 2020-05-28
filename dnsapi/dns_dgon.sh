#!/usr/bin/env sh

## Will be called by acme.sh to add the txt record to your api system.
## returns 0 means success, otherwise error.

## Author: thewer <github at thewer.com>
## GitHub: https://github.com/gitwer/acme.sh

##
## Environment Variables Required:
##
## DO_API_KEY="75310dc4ca779ac39a19f6355db573b49ce92ae126553ebd61ac3a3ae34834cc"
##

#####################  Public functions  #####################

## Create the text record for validation.
## Usage: fulldomain txtvalue
## EG: "_acme-challenge.www.other.domain.com" "XKrxpRBosdq0HG9i01zxXp5CPBs"
dns_dgon_add() {
  fulldomain="$(echo "$1" | _lower_case)"
  txtvalue=$2

  DO_API_KEY="${DO_API_KEY:-$(_readaccountconf_mutable DO_API_KEY)}"
  # Check if API Key Exist
  if [ -z "$DO_API_KEY" ]; then
    DO_API_KEY=""
    _err "You did not specify DigitalOcean API key."
    _err "Please export DO_API_KEY and try again."
    return 1
  fi

  _info "Using digitalocean dns validation - add record"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  ## save the env vars (key and domain split location) for later automated use
  _saveaccountconf_mutable DO_API_KEY "$DO_API_KEY"

  ## split the domain for DO API
  if ! _get_base_domain "$fulldomain"; then
    _err "domain not found in your account for addition"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  ## Set the header with our post type and key auth key
  export _H1="Content-Type: application/json"
  export _H2="Authorization: Bearer $DO_API_KEY"
  PURL='https://api.digitalocean.com/v2/domains/'$_domain'/records'
  PBODY='{"type":"TXT","name":"'$_sub_domain'","data":"'$txtvalue'","ttl":120}'

  _debug PURL "$PURL"
  _debug PBODY "$PBODY"

  ## the create request - post
  ## args: BODY, URL, [need64, httpmethod]
  response="$(_post "$PBODY" "$PURL")"

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
dns_dgon_rm() {
  fulldomain="$(echo "$1" | _lower_case)"
  txtvalue=$2

  DO_API_KEY="${DO_API_KEY:-$(_readaccountconf_mutable DO_API_KEY)}"
  # Check if API Key Exist
  if [ -z "$DO_API_KEY" ]; then
    DO_API_KEY=""
    _err "You did not specify DigitalOcean API key."
    _err "Please export DO_API_KEY and try again."
    return 1
  fi

  _info "Using digitalocean dns validation - remove record"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  ## split the domain for DO API
  if ! _get_base_domain "$fulldomain"; then
    _err "domain not found in your account for removal"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  ## Set the header with our post type and key auth key
  export _H1="Content-Type: application/json"
  export _H2="Authorization: Bearer $DO_API_KEY"
  ## get URL for the list of domains
  ## may get: "links":{"pages":{"last":".../v2/domains/DOM/records?page=2","next":".../v2/domains/DOM/records?page=2"}}
  GURL="https://api.digitalocean.com/v2/domains/$_domain/records"

  ## Get all the matching records
  while true; do
    ## 1) get the URL
    ## the create request - get
    ## args: URL, [onlyheader, timeout]
    domain_list="$(_get "$GURL")"

    ## check response
    if [ "$?" != "0" ]; then
      _err "error in domain_list response: $domain_list"
      return 1
    fi
    _debug2 domain_list "$domain_list"

    ## 2) find records
    ## check for what we are looking for: "type":"A","name":"$_sub_domain"
    record="$(echo "$domain_list" | _egrep_o "\"id\"\s*\:\s*\"*[0-9]+\"*[^}]*\"name\"\s*\:\s*\"$_sub_domain\"[^}]*\"data\"\s*\:\s*\"$txtvalue\"")"

    if [ ! -z "$record" ]; then

      ## we found records
      rec_ids="$(echo "$record" | _egrep_o "id\"\s*\:\s*\"*[0-9]+" | _egrep_o "[0-9]+")"
      _debug rec_ids "$rec_ids"
      if [ ! -z "$rec_ids" ]; then
        echo "$rec_ids" | while IFS= read -r rec_id; do
          ## delete the record
          ## delete URL for removing the one we dont want
          DURL="https://api.digitalocean.com/v2/domains/$_domain/records/$rec_id"

          ## the create request - delete
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

    ## 3) find the next page
    nextpage="$(echo "$domain_list" | _egrep_o "\"links\".*" | _egrep_o "\"next\".*" | _egrep_o "http.*page\=[0-9]+")"
    if [ -z "$nextpage" ]; then
      break
    fi
    _debug2 nextpage "$nextpage"
    GURL="$nextpage"

  done

  ## finished correctly
  return 0
}

#####################  Private functions below  #####################

## Split the domain provided into the "bade domain" and the "start prefix".
## This function searches for the longest subdomain in your account
## for the full domain given and splits it into the base domain (zone)
## and the prefix/record to be added/removed
## USAGE: fulldomain
## EG: "_acme-challenge.two.three.four.domain.com"
## returns
## _sub_domain="_acme-challenge.two"
## _domain="three.four.domain.com" *IF* zone "three.four.domain.com" exists
## if only "domain.com" exists it will return
## _sub_domain="_acme-challenge.two.three.four"
## _domain="domain.com"
_get_base_domain() {
  # args
  fulldomain="$(echo "$1" | _lower_case)"
  _debug fulldomain "$fulldomain"

  # domain max legal length = 253
  MAX_DOM=255

  ## get a list of domains for the account to check thru
  ## Set the headers
  export _H1="Content-Type: application/json"
  export _H2="Authorization: Bearer $DO_API_KEY"
  _debug DO_API_KEY "$DO_API_KEY"
  ## get URL for the list of domains
  ## may get: "links":{"pages":{"last":".../v2/domains/DOM/records?page=2","next":".../v2/domains/DOM/records?page=2"}}
  DOMURL="https://api.digitalocean.com/v2/domains"

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

    ## for each shortening of our $fulldomain, check if it exists in the $domain_list
    ## can never start on 1 (aka whole $fulldomain) as $fulldomain starts with "_acme-challenge"
    i=2
    while [ $i -gt 0 ]; do
      ## get next longest domain
      _domain=$(printf "%s" "$fulldomain" | cut -d . -f "$i"-"$MAX_DOM")
      ## check we got something back from our cut (or are we at the end)
      if [ -z "$_domain" ]; then
        break
      fi
      ## we got part of a domain back - grep it out
      found="$(echo "$domain_list" | _egrep_o "\"name\"\s*\:\s*\"$_domain\"")"
      ## check if it exists
      if [ ! -z "$found" ]; then
        ## exists - exit loop returning the parts
        sub_point=$(_math $i - 1)
        _sub_domain=$(printf "%s" "$fulldomain" | cut -d . -f 1-"$sub_point")
        _debug _domain "$_domain"
        _debug _sub_domain "$_sub_domain"
        return 0
      fi
      ## increment cut point $i
      i=$(_math $i + 1)
    done

    if [ -z "$found" ]; then
      ## find the next page if we dont have a match
      nextpage="$(echo "$domain_list" | _egrep_o "\"links\".*" | _egrep_o "\"next\".*" | _egrep_o "http.*page\=[0-9]+")"
      if [ -z "$nextpage" ]; then
        _err "no record and no nextpage in digital ocean DNS removal"
        return 1
      fi
      _debug2 nextpage "$nextpage"
      DOMURL="$nextpage"
    fi

  done

  ## we went through the entire domain zone list and dint find one that matched
  ## doesnt look like we can add in the record
  _err "domain not found in DigitalOcean account, but we should never get here"
  return 1
}

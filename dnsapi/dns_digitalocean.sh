#!/usr/bin/env sh


## Will be called by acme.sh to add the txt record to your api system.
## returns 0 means success, otherwise error.

## Author: thewer <github at thewer.com>

##
## Environment Variables Required:
##
## DO_API_KEY="75310dc4ca779ac39a19f6355db573b49ce92ae126553ebd61ac3a3ae34834cc"
##
## DO_DOMAIN_START="3"
## start of the digital ocean dns base domain from the LEFT
## (EG: one.two.three.four.five.com -> one.two & three.four.five.com)
##


#####################  Public functions  #####################


## Create the text record for validation.
## Usage: fulldomain txtvalue
## EG: "_acme-challenge.www.other.domain.com" "XKrxpRBosdq0HG9i01zxXp5CPBs"
dns_digitalocean_add() {
	fulldomain=$1
	txtvalue=$2
	_info "Using digitalocean dns validation - add record"
	_debug fulldomain "$fulldomain"
	_debug txtvalue "$txtvalue"
	_debug DO_DOMAIN_START "$DO_DOMAIN_START"

	## split the domain for DO API
	if ! _get_base_domain "$fulldomain" "$DO_DOMAIN_START"; then
		_err "invalid domain or split"
		return 1
	fi
	_debug _sub_domain "$_sub_domain"
	_debug _domain "$_domain"
	
	## Set the header with our post type and key auth key
	_H1="Content-Type: application/json"
	_H2="Authorization: Bearer $DO_API_KEY"
	PURL='https://api.digitalocean.com/v2/domains/'$_domain'/records'
	PBODY='{"type":"TXT","name":"'$_sub_domain'","data":"'$txtvalue'"}'

	_debug PURL "$PURL"
	_debug PBODY "$PBODY"

	## the create request - post
	## args: BODY, URL, [need64, httpmethod]
	response="$(_post "$PBODY" "$PURL")"
	
	## check response (sort of)
	if [ "$?" != "0" ]; then
		_err "error in response: $response"
		return 1
	fi
	_debug response "$response"
	
	## check for result and get the ID so we can delete it later
	#response="$(echo "$response" | tr -d "\n" | sed 's/{/\n&/g')"
	#do_id="$(echo "$response" | _egrep_o "id\"\s*\:\s*\d+" | _egrep_o "\d+" )"
	#if [ -z "$do_id" ]; then
	#	_err "error getting ID from response: $response"
	#	return 1;
	#fi
	#_debug do_id "$do_id"
	
	## finished correctly
	return 0
}


## Remove the txt record after validation.
## Usage: fulldomain txtvalue
## EG: "_acme-challenge.www.other.domain.com" "XKrxpRBosdq0HG9i01zxXp5CPBs"
dns_digitalocean_rm() {
	fulldomain=$1
	txtvalue=$2
	_info "Using digitalocean dns validation - remove record"
	_debug fulldomain "$fulldomain"
	_debug txtvalue "$txtvalue"
	_debug DO_DOMAIN_START "$DO_DOMAIN_START"

	## split the domain for DO API
	if ! _get_base_domain "$fulldomain" "$DO_DOMAIN_START"; then
		_err "invalid domain or split in remove"
		return 1
	fi
	_debug _sub_domain "$_sub_domain"
	_debug _domain "$_domain"
	
	## Set the header with our post type and key auth key
	_H1="Content-Type: application/json"
	_H2="Authorization: Bearer $DO_API_KEY"
	## get URL for the list of domains
	## may get: "links":{"pages":{"last":".../v2/domains/DOM/records?page=2","next":".../v2/domains/DOM/records?page=2"}}
	GURL="https://api.digitalocean.com/v2/domains/$_domain/records"

	## while we dont have a record ID we keep going
	while [ -z "$record" ]; do
		## 1) get the URL
		## the create request - get
		## args: URL, [onlyheader, timeout]
		domain_list="$(_get "$GURL")"
		## 2) find record
		## check for what we are looing for: "type":"A","name":"$_sub_domain"
		record="$(echo "$domain_list" | _egrep_o "\"id\"\s*\:\s*\"*\d+\"*[^}]*\"name\"\s*\:\s*\"$_sub_domain\"[^}]*\"data\"\s*\:\s*\"$txtvalue\"" )"
		## 3) check record and get next page
		if [ -z "$record" ]; then
			## find the next page if we dont have a match
			nextpage="$(echo "$domain_list" | _egrep_o "\"links\".*" | _egrep_o "\"next\".*" | _egrep_o "http.*page\=\d+" )"
			if [ -z "$nextpage" ]; then
				_err "no record and no nextpage in digital ocean DNS removal"
				return 1
			fi
			_debug nextpage "$nextpage"
			GURL="$nextpage"
		fi
		## we break out of the loop when we have a record
	done

	## we found the record
	rec_id="$(echo "$record" | _egrep_o "id\"\s*\:\s*\"*\d+" | _egrep_o "\d+" )"
	_debug rec_id "$rec_id"
	
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
	_debug response "$response"
	
	## finished correctly
	return 0
}


#####################  Private functions below  #####################


## Split the domain provided at "base_domain_start_position" from the FRONT
## USAGE: fulldomain base_domain_start_position
## EG: "_acme-challenge.two.three.four.domain.com" "3"
## returns
## _sub_domain="_acme-challenge.two"
## _domain="three.four.domain.com"
_get_base_domain() {
	# args
	domain=$1
	dom_point=$2
	sub_point=$(_math $dom_point - 1)
	_debug "split domain" "$domain"
	_debug "split dom_point" "$dom_point"
	_debug "split sub_point" "$sub_point"
	
	# domain max length - 253
	MAX_DOM=255

	## cut in half and check
	_domain=$(printf "%s" "$domain" | cut -d . -f $dom_point-$MAX_DOM)
	_sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$sub_point)
	if [ -z "$_domain" ]; then
		## not valid
		_err "invalid split location"
		return 1
	fi
	if [ -z "$_sub_domain" ]; then
		## not valid
		_err "invalid split location"
		return 1
	fi
	
	_debug "split _domain" "$_domain"
	_debug "split _sub_domain" "$_sub_domain"
	
	## all ok
	return 0
}


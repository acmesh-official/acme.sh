#!/bin/bash

#Author: Neilpang
#			original file dns_myapi.sh
#			Modified by Chris Polley to support Digital Ocean
#Report Bugs here: https://github.com/Neilpang/acme.sh
#
#depends: doctl (https://github.com/digitalocean/doctl/) v1.5
#         (configured using `doctl auth init` and the acocunt's access token
#
########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_doctl_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using dns_doctl"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

# digitalocean needs the domain to act upon, so split $fulldomain into record-name and domain
# "_acme-challenge" and "www.domain.com" in the above example


	# get list of domains authorized
	domains_avail=$( doctl compute domain list --no-header --format Domain | tr "$IFS" " " )
	_debug domains_avail "$domains_avail"

	if [ -z "$domains_avail" ]
	then
		_err "No domains in DigitalOcean DNS"
		return 1
	fi

	for d in $domains_avail
	do
		_debug trying_domain "$d"
		try_domain=${fulldomain##$d}
		try_challenge=${fulldomain%%.$d}
		_debug try_domain "$try_domain"
		_debug try_challenge "$challenge"

		if [ "$fulldomain" == "$try_challenge.$d" ]
		then
			_debug matches "$d"
			domain="$d"
			challenge="$try_challenge"
		else
			_debug no_match "$d"
		fi
	done

	if [ -z "$domain" ]
	then
		_err "Unable to locate domain of $fulldomain in DigitalOcean DNS"
		return 1
	fi

	record_name="$challenge"
	_debug domain "$domain"
	_debug record_name "$record_name"
    _debug txtvalue "$txtvalue"
	id_created=$( doctl compute domain records create $domain --record-data $txtvalue  --record-name $record_name --record-type TXT --no-header --format ID )
	_debug id_created "$id_created"
	_info "Created record $id_created in domain $domain with name $record_name and TXT $txtvalue"
	if [ "" != "$id_created" ]
	then
		return 0
	else
		_err "Error creating DNS record $fulldomain"
		return 1
	fi
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_doctl_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using dns_doctl"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

	# get list of domains authorized
	domains_avail=$( doctl compute domain list --no-header --format Domain | tr "$IFS" " " )
	_debug domains_avail "$domains_avail"
	if [ -z "$domains_avail" ]
	then
		_err "No domains in DigitalOcean DNS"
		return 1
	fi

	for d in $domains_avail
	do
		_debug trying_domain "$d"
		try_domain=${fulldomain##$d}
		try_challenge=${fulldomain%%.$d}
		_debug try_domain "$try_domain"
		_debug try_challenge "$try_challenge"

		if [ "$fulldomain" == "$try_challenge.$d" ]
		then
			_debug matches "$d"
			domain="$d"
			challenge="$try_challenge"
		else
			_debug no_match "$d"
		fi
	done

	if [ -z "$domain" ]
	then
		_err "Unable to locate domain of $fulldomain in DigitalOcean DNS"
		return 1
	fi

	record_name="$challenge"
	_debug domain "$domain"
	_debug record_name "$record_name"
    _debug txtvalue "$txtvalue"

  	record_ids=$( doctl compute domain records list $domain --no-header --format=ID,Name,Data | grep $record_name | grep $txtvalue | awk '{print $1}' | tr "$IFS" " " )
	_debug record_ids "$record_ids"
	# could be more than one; delete all matching records
	if [ -z "$record_ids" ]
	then
		_err "Error: Unable to locate any DNS record matching $record_name with TXT $txtvalue -- you will need to delete record\(s\) manually"
		#
	else
	  	for r in $record_ids
  		do
			_info "Deleting record $r from domain $domain"
			doctl compute domain records delete $domain $r
  		done
	fi

}

####################  Private functions below ##################################

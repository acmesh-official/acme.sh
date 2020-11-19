#!/usr/bin/env sh

# This script has been created at June 2020, based on knowledge base of wedos.com provider.
# It is intended to allow DNS-01 challenges for acme.sh using wedos's WAPI using XML.

# Author Michal Tuma <mxtuma@gmail.com>
# For issues send me an email

WEDOS_WAPI_ENDPOINT="https://api.wedos.com/wapi/xml"
TESTING_STAGE=

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_wedos_add() {
	fulldomain=$1
	txtvalue=$2

	WEDOS_Username="${WEDOS_Username:-$(_readaccountconf_mutable WEDOS_Username)}"
	WEDOS_Wapipass="${WEDOS_Wapipass:-$(_readaccountconf_mutable WEDOS_Wapipass)}"
	WEDOS_Authtoken="${WEDOS_Authtoken:-$(_readaccountconf_mutable WEDOS_Authtoken)}"

	if [ "${WEDOS_Authtoken}" ]; then
		_debug "WEDOS Authtoken was already saved, using saved one"
		_saveaccountconf_mutable WEDOS_Authtoken "${WEDOS_Authtoken}"
	else
		if [ -z "${WEDOS_Username}" ] || [ -z "${WEDOS_Wapipass}" ]; then
			WEDOS_Username=""
			WEDOS_Wapipass=""
			_err "You didn't specify a WEDOS's username and wapi key yet."
			_err "Please type: export WEDOS_Username=<your user name to login to wedos web account>"
			_err "And: export WEDOS_Wapipass=<your WAPI passwords you setup using wedos web pages>"
			_err "After you export those variables, run the script again, the values will be saved for future"
			return 1
		fi

		#build WEDOS_Authtoken
		_debug "WEDOS Authtoken were not saved yet, building"
		WEDOS_Authtoken=$(printf '%s' "${WEDOS_Wapipass}" | _digest "sha1" "true" | head -c 40)
		_debug "WEDOS_Authtoken step 1, WAPI PASS sha1 sum: '${WEDOS_Authtoken}'"
		WEDOS_Authtoken="${WEDOS_Username}${WEDOS_Authtoken}"
		_debug "WEDOS_Authtoken step 2, username concat with token without hours: '${WEDOS_Authtoken}'"

		#save details

		_saveaccountconf_mutable WEDOS_Username "${WEDOS_Username}"
		_saveaccountconf_mutable WEDOS_Wapipass "${WEDOS_Wapipass}"
		_saveaccountconf_mutable WEDOS_Authtoken "${WEDOS_Authtoken}"
	fi

	if ! _get_root "${fulldomain}"; then
		_err "WEDOS Account do not contain primary domain to fullfill add of ${fulldomain}!"
		return 1
	fi

	_debug _sub_domain "${_sub_domain}"
	_debug _domain "${_domain}"

	if _wapi_row_add "${_domain}" "${_sub_domain}" "${txtvalue}" "300"; then
		_info "WEDOS WAPI: dns record added and dns changes were commited"
		return 0
	else
		_err "FAILED TO ADD DNS RECORD OR COMMIT DNS CHANGES"
		return 1
	fi
}

#fulldomain txtvalue
dns_wedos_rm() {
	fulldomain=$1
	txtvalue=$2

	WEDOS_Username="${WEDOS_Username:-$(_readaccountconf_mutable WEDOS_Username)}"
	WEDOS_Wapipass="${WEDOS_Wapipass:-$(_readaccountconf_mutable WEDOS_Wapipass)}"
	WEDOS_Authtoken="${WEDOS_Authtoken:-$(_readaccountconf_mutable WEDOS_Authtoken)}"

	if [ "${WEDOS_Authtoken}" ]; then
		_debug "WEDOS Authtoken was already saved, using saved one"
		_saveaccountconf_mutable WEDOS_Authtoken "${WEDOS_Authtoken}"
	else
		if [ -z "${WEDOS_Username}" ] || [ -z "${WEDOS_Wapipass}" ]; then
			WEDOS_Username=""
			WEDOS_Wapipass=""
			_err "You didn't specify a WEDOS's username and wapi key yet."
			_err "Please type: export WEDOS_Username=<your user name to login to wedos web account>"
			_err "And: export WEDOS_Wapipass=<your WAPI passwords you setup using wedos web pages>"
			_err "After you export those variables, run the script again, the values will be saved for future"
			return 1
		fi

		#build WEDOS_Authtoken
		_debug "WEDOS Authtoken were not saved yet, building"
		WEDOS_Authtoken=$(printf '%s' "${WEDOS_Wapipass}" | sha1sum | head -c 40)
		_debug "WEDOS_Authtoken step 1, WAPI PASS sha1 sum: '${WEDOS_Authtoken}'"
		WEDOS_Authtoken="${WEDOS_Username}${WEDOS_Authtoken}"
		_debug "WEDOS_Authtoken step 2, username concat with token without hours: '${WEDOS_Authtoken}'"

		#save details

		_saveaccountconf_mutable WEDOS_Username "${WEDOS_Username}"
		_saveaccountconf_mutable WEDOS_Wapipass "${WEDOS_Wapipass}"
		_saveaccountconf_mutable WEDOS_Authtoken "${WEDOS_Authtoken}"
	fi

	if ! _get_root "${fulldomain}"; then
		_err "WEDOS Account do not contain primary domain to fullfill add of ${fulldomain}!"
		return 1
	fi

	_debug _sub_domain "${_sub_domain}"
	_debug _domain "${_domain}"

	if _wapi_find_row "${_domain}" "${_sub_domain}" "${txtvalue}"; then
		_info "WEDOS WAPI: dns record found with id '${_row_id}'"

		if _wapi_delete_row "${_domain}" "${_row_id}"; then
			_info "WEDOS WAPI: dns row were deleted and changes commited!"
			return 0
		fi
	fi

	_err "Requested dns row were not found or was imposible to delete it, do it manually"
	_err "Delete: ${fulldomain}"
	_err "Value: ${txtvalue}"
	return 1
}

####################  Private functions below ##################################

# Function _wapi_post(), only takes data, prepares auth token and provide result
# $1 - WAPI command string, like 'dns-domains-list'
# $2 - WAPI data for given command, is not required
# returns WAPI response if request were successfully delivered to WAPI endpoint
_wapi_post() {
	command=$1
	data=$2

	_debug "Command : ${command}"
	_debug "Data : ${data}"

	if [ -z "${command}" ]; then
		_err "No command were provided, implamantation error!"
		return 1
	fi

	# Prepare authentification token
	hour=$(TZ='Europe/Prague' date +%H)
	token=$(printf '%s' "${WEDOS_Authtoken}${hour}" | _digest "sha1" "true" | head -c 40)
	_debug "Authentification token is '${token}'"

	# Build xml request

	request="request=<?xml version=\"1.0\" encoding=\"UTF-8\"?>\
<request>\
  <user>${WEDOS_Username}</user>\
  <auth>${token}</auth>\
  <command>${command}</command>"

	if [ -z "${data}" ]; then
		echo "" 1>/dev/null
	else
		request="${request}${data}"
	fi

	if [ -z "$TESTING_STAGE" ]; then
		echo "" 1>/dev/null
	else
		request="${request}\
  <test>1</test>"
	fi

	request="${request}\
</request>"

	_debug "Request to WAPI is: ${request}"

	if ! response="$(_post "${request}" "$WEDOS_WAPI_ENDPOINT")"; then
		_err "Error contacting WEDOS WAPI with command ${command}"
		return 1
	fi

	_debug "Response : ${response}"
	_contains "${response}" "<code>1000</code>"

	return "$?"
}

# _get_root() function, for provided full domain, like _acme_challenge.www.example.com verify if WEDOS contains a primary active domain and found what is subdomain
# $1 - full domain to verify, ie _acme_challenge.www.example.com
# build ${_domain} found at WEDOS, like example.com and ${_sub_domain} from provided full domain, like _acme_challenge.www
_get_root() {
	domain=$1

	if [ -z "${domain}" ]; then
		_err "Function _get_root was called without argument, implementation error!"
		return 1
	fi

	_debug "Get root for domain: ${domain}"

	_debug "Getting list of domains using WAPI ..."

	if ! _wapi_post "dns-domains-list"; then
		_err "Error on WAPI request for list of domains, response : ${response}"
		return 1
	else
		_debug "DNS list were successfully retrieved, response : ${response}"
	fi

	# In for each cycle, try parse the response to find primary active domains
	# For cycle description:
	# 1st	tr -d '\011\012\015' = remove all newlines and tab characters - whole XML became single line
	# 2nd sed "s/^.*<data>[ ]*//g" = remove all the xml data from the beggining of the XML - XML now start with the content of <data> element
	# 3rd sed "s/<\/data>.*$//g" = remove all the data after the data xml element - XML now contains only the content of data xml element
	# 4th sed "s/>[ ]*<\([^\/]\)/><\1/g" = remove all spaces between XML tag and XML start tag - XML now contains content of data xml element and is without spaces between end and start xml tags
	# 5th sed "s/<domain>//g" = remove all domain xml start tags - XML now contains only <name>...</name><type>...</type><status>...</status>  </domain>(next xml domain)
	# 6th sed "s/[ ]*<\/domain>/\n/g"= replace all "spaces</domain>" by new line - now we create multiple lines each should contain only <name>...</name><type>...</type><status>...</status>
	# 7th sed  -n "/<name>\([a-zA-Z0-9_\-\.]\+\)<\/name><type>primary<\/type><status>active<\/status>/p" = remove all non primary or non active domains lines
	# 8th sed "s/<name>\([a-zA-Z0-9_\-\.]\+\)<\/name><type>primary<\/type><status>active<\/status>/\1/g" = substitute for domain names only

	for xml_domain in $(echo "${response}" | tr -d '\011\012\015' | sed "s/^.*<data>[ ]*//g" | sed "s/<\/data>.*$//g" | sed "s/>[ ]*<\([^\/]\)/><\1/g" | sed "s/<domain>//g" | sed "s/[ ]*<\/domain>/\n/g" | sed -n "/<name>\([a-zA-Z0-9_\-\.]\+\)<\/name><type>primary<\/type><status>active<\/status>/p" | sed "s/<name>\([a-zA-Z0-9_\-\.]\+\)<\/name><type>primary<\/type><status>active<\/status>/\1/g"); do
		_debug "Found primary active domain: ${xml_domain}"
		if _endswith "${domain}" "${xml_domain}"; then
			length_difference=$(_math "${#domain} - ${#xml_domain}")
			possible_subdomain=$(echo "${domain}" | cut -c -"${length_difference}")
			if _endswith "${possible_subdomain}" "."; then
				length_difference=$(_math "${length_difference} - 1")
				_domain=${xml_domain}
				_sub_domain=$(echo "${possible_subdomain}" | cut -c -"${length_difference}")

				_info "Domain '${_domain}' was found at WEDOS account as primary, and subdomain is '${_sub_domain}'!"
				return 0
			fi
		fi
		_debug " ... found domain does not match required!"
	done

	return 1

}

# for provided domain, it commites all performed changes
_wapi_dns_commit() {
	domain=$1

	if [ -z "${domain}" ]; then
		_err "Invalid request to commit dns changes, domain is empty, implementation error!"
		return 1
	fi

	data="  <data>\
    <name>${domain}</name>\
  </data>"

	if ! _wapi_post "dns-domain-commit" "${data}"; then
		_err "Error on WAPI request to commit DNS changes, response : ${response}"
		_err "PLEASE USE WEB ACCESS TO CHECK IF CHANGES ARE REQUIRED TO COMMIT OR ROLLBACKED IMMEDIATELLY!"
		return 1
	else
		_debug "DNS CHANGES COMMITED, response : ${response}"
		_info "WEDOS DNS WAPI: Changes were commited to domain '${domain}'"
	fi

	return 0

}

# add one TXT dns row to a specified fomain
_wapi_row_add() {
	domain=$1
	sub_domain=$2
	value=$3
	ttl=$4

	if [ -z "${domain}" ] || [ -z "${sub_domain}" ] || [ -z "${value}" ] || [ -z "${ttl}" ]; then
		_err "Invalid request to add record, domain: '${domain}', sub_domain: '${sub_domain}', value: '${value}' and ttl: '${ttl}', on of required input were not provided, implementation error!"
		return 1
	fi

	# Prepare data for request to WAPI
	data="  <data>\
    <domain>${domain}</domain>\
    <name>${sub_domain}</name>\
    <ttl>${ttl}</ttl>\
    <type>TXT</type>\
    <rdata>${value}</rdata>\
    <auth_comment>Created using WAPI from acme.sh</auth_comment>\
  </data>"

	_debug "Adding row using WAPI ..."

	if ! _wapi_post "dns-row-add" "${data}"; then
		_err "Error on WAPI request to add new TXT row, response : ${response}"
		return 1
	else
		_debug "ROW ADDED, response : ${response}"
		_info "WEDOS DNS WAPI: Row to domain '${domain}' with name '${sub_domain}' were successfully added with value '${value}' and ttl set to ${ttl}"
	fi

	# Now we have to commit
	_wapi_dns_commit "${domain}"

	return "$?"

}

_wapi_find_row() {
	domain=$1
	sub_domain=$2
	value=$3

	if [ -z "${domain}" ] || [ -z "${sub_domain}" ] || [ -z "${value}" ]; then
		_err "Invalud request to finad a row, domain: '${domain}', sub_domain: '${sub_domain}' and value: '${value}', one of required input were not provided, implementation error!"
		return 1
	fi

	data="  <data>\
    <domain>${domain}</domain>\
  </data>"

	_debug "Searching rows using WAPI ..."

	if ! _wapi_post "dns-rows-list" "${data}"; then
		_err "Error on WAPI request to list domain rows, response : ${response}"
		return 1
	fi

	_debug "Domain rows found, response : ${response}"

	# Prepare sub domain regex which will be later used for search domain row
	# from _acme_challenge.sub it should be _acme_challenge\.sub

	sub_domain_regex=$(echo "${sub_domain}" | sed "s/\./\\\\./g")

	_debug "Subdomain regex '${sub_domain_regex}'"

	# In for each cycle loops over the domains rows, description:
	# 1st tr -d '\011\012\015' = delete all newlines and tab characters - XML became a single line
	# 2nd sed "s/^.*<data>[ ]*//g" = remove all from the beggining to the start of the content of the data xml element - XML is without unusefull beginning
	# 3rd sed "s/[ ]*<\/data>.*$//g" = remove the end of the xml starting with xml end tag data - XML contains only the content of data xml element and is trimmed
	# 4th sed "s/>[ ]*<\([^\/]\)/><\1/g" = remove all spaces between XML tag and XML start tag - XML now contains content of data xml element and is without spaces between end and start xml tags
	# 5th sed "s/<row>//g" = remove all row xml start tags - XML now contains rows xml element content and its end tag
	# 6th sed "s/[ ]*<\/row>/\n/g" = replace all "spaces</row>" by new line - now we create multiple lines each should contain only single row xml content
	# 7th sed  -n "/<name>${sub_domain_regex}<\/name>.*<rdtype>TXT<\/rdtype>/p" = remove all non TXT and non name matching row lines - now we have only xml lines with TXT rows matching requested values
	# 8th sed "s/^<ID>\([0-9]\+\)<\/ID>.*<rdata>\(.*\)<\/rdata>.*$/\1-\2/" = replace the whole lines to ID-value pairs
	# -- now there are only lines with ID-value but value might contain spaces (BAD FOR FOREACH LOOP) or special characters (BAD FOR REGEX MATCHING)
	# 9th grep "${value}" = match only a line containg searched value
	# 10th sed "s/^\([0-9]\+\).*$/\1/" = get only ID from the row

	for xml_row in $(echo "${response}" | tr -d '\011\012\015' | sed "s/^.*<data>[ ]*//g" | sed "s/[ ]*<\/data>.*$//g" | sed "s/>[ ]*<\([^\/]\)/><\1/g" | sed "s/<row>//g" | sed "s/[ ]*<\/row>/\n/g" | sed -n "/<name>${sub_domain_regex}<\/name>.*<rdtype>TXT<\/rdtype>/p" | sed "s/^<ID>\([0-9]\+\)<\/ID>.*<rdata>\(.*\)<\/rdata>.*$/\1-\2/" | grep "${value}" | sed "s/^\([0-9]\+\).*$/\1/"); do
		_row_id="${xml_row}"
		_info "WEDOS API: Found DNS row id ${_row_id} for domain ${domain}"
		return 0
	done

	_info "WEDOS API: No TXT row found for domain '${domain}' with name '${sub_domain}' and value '${value}'"

	return 1
}

_wapi_delete_row() {
	domain=$1
	row_id=$2

	if [ -z "${domain}" ] || [ -z "${row_id}" ]; then
		_err "Invalid request to delete domain dns row, domain: '${domain}' and row_id: '${row_id}', one of required input were not provided, implementation error!"
		return 1
	fi

	data="  <data>\
    <domain>${domain}</domain>
    <row_id>${row_id}</row_id>
</data>"

	_debug "Deleting dns row using WAPI ..."

	if ! _wapi_post "dns-row-delete" "${data}"; then
		_err "Error on WAPI request to delete dns row, response: ${response}"
		return 1
	fi

	_debug "DNS row were deleted, response: ${response}"

	_info "WEDOS API: Required dns domain row with row_id '${row_id}'  were correctly deleted at domain '${domain}'"

	# Now we have to commit changes
	_wapi_dns_commit "${domain}"

	return "$?"

}

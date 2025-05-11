#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_wexbo_info='wexbo.com
Site: wexbo.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_wexbo
Options:
 WEXBO_TOKEN API Token
Issues: github.com/acmesh-official/acme.sh/issues/6349
Author: WEXBO s.r.o. <support@wexbo.com>
'

WEXBO_URL="https://api.wexbo.com/v1/acme/";

########  Public functions #####################

#Usage: add _acme-challenge.www.domain.com "some_long_string_of_characters_go_here_from_lets_encrypt"
dns_wexbo_add(){

	fulldomain=$1;
	txtvalue=$2;

	_wexbo_init

	_info "Adding TXT record to ${fulldomain}";
	export _H1="Authorization: ${WEXBO_TOKEN}";
	response="$(_post "content=${txtvalue}" "${WEXBO_URL}${fulldomain}" "" "POST")";
	if _contains "${response}" '"result":true'; then return 0; fi
	_err "Error: ${response}"; return 1;

}

dns_wexbo_rm(){

	fulldomain=$1;

	_wexbo_init

	_info "Deleting resource record ${fulldomain}"
	export _H1="Authorization: ${WEXBO_TOKEN}";
	response="$(_post "" "${WEXBO_URL}${fulldomain}" "" "DELETE")";
	if _contains "${response}" '"result":true'; then return 0; fi
	_err "Error: ${response}"; return 1;

}

_wexbo_init(){

	WEXBO_TOKEN="${WEXBO_TOKEN:-$(_readaccountconf_mutable WEXBO_TOKEN)}";
	if [ -z "$WEXBO_TOKEN" ]; then WEXBO_TOKEN=""; _err "Please set WEXBO_TOKEN and try again."; return 1; fi
	_saveaccountconf_mutable WEXBO_TOKEN "$WEXBO_TOKEN";

}
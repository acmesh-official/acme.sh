#!/usr/bin/env sh
#
#Author: Wolfgang Ebner
#Author: Sven Neubuaer
#Report Bugs here: https://github.com/dampfklon/acme.sh
#
# Usage:
# export ACMEDNS_BASE_URL="https://auth.acme-dns.io"
#
# You can optionally define an already existing account:
#
# replace . in domain with _
# export ACMEDNS_USERNAME_$domain="<username>"
# export ACMEDNS_PASSWORD_$domain="<password>"
# export ACMEDNS_SUBDOMAIN_$domain="<subdomain>"
#
########  Public functions #####################

_root_domain() {
  d=$1
  cache='/tmp/dns_suffix.cache'
  expiry='yesterday'
  suffix_url='https://publicsuffix.org/list/public_suffix_list.dat'
  [[ -s "${cache}" ]] || echo -n '' > "${cache}" # (re-)create empty cache
  [[ $(stat -c '%Y' "${cache}") -lt $(date +%s -d "${expiry}") ]] && echo -n '' > "${cache}" # purge old cache
  {
    [[ -s "${cache}" ]] && cat "${cache}" # load from cache
    [[ -s "${cache}" ]] || {              # save to cache
        curl -so- "${suffix_url}" | # fetch from $suffix_url
        sed 's/[#\/].*$//'        | # strip comments
        sed 's/[*][.]//'          | # strip wildcard suffixes, like '*.nom.br'
        sed '/^[\t ]*$/d'         | # delete blank lines
        tr 'A-Z' 'a-z'            | # everything lowercase
        awk '{print length, $0}'  | # prepend length of each line to each line
        sort -n -r                | # sort longest-line-first
        sed 's/^[0-9\t ]*//'      | # strip line length
        tee "${cache}"              # load into cache, and send to stdout
    }
  } |
  grep -E "${d/*./}$" | # optimisation - only include matching TLDs
  while read suffix
  do
    echo "${d}" | grep -qE '[.]'"${suffix}"'$' || continue # if $domain does not end in .$suffix, get next suffix
    c=$(echo $d | awk -F'.' '{ print NF }')
    s=$(echo $suffix | awk -F'.' '{ print NF }')
    i=$((c-s))
    echo $(echo $d | cut -d . -f $i-100)
    break                                                       # stop processing
  done
}

#Usage: dns_acmedns_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_acmedns_add() {
  fulldomain=$1
  d=$(_root_domain $fulldomain)
  h="${d//./_}"
  txtvalue=$2
  _info "Using acme-dns"
  _debug "fulldomain $fulldomain"
  _debug "domain $d"
  _debug "$h"
  _debug "txtvalue $txtvalue"

  #for compatiblity from account conf
  ACMEDNS_USERNAME="ACMEDNS_USERNAME_$h"
  export ACMEDNS_USERNAME_$h="${!ACMEDNS_USERNAME:-$(_readaccountconf_mutable ACMEDNS_USERNAME)}"
  _clearaccountconf_mutable $ACMEDNS_USERNAME
  ACMEDNS_PASSWORD="ACMEDNS_PASSWORD_$h"
  export ACMEDNS_PASSWORD_$h="${!ACMEDNS_PASSWORD:-$(_readaccountconf_mutable ACMEDNS_PASSWORD)}"
  _clearaccountconf_mutable $ACMEDNS_PASSWORD
  ACMEDNS_SUBDOMAIN="ACMEDNS_SUBDOMAIN_$h"
  export ACMEDNS_SUBDOMAIN_$h="${!ACMEDNS_SUBDOMAIN:-$(_readaccountconf_mutable ACMEDNS_SUBDOMAIN)}"
  _clearaccountconf_mutable $ACMEDNS_SUBDOMAIN

  ACMEDNS_BASE_URL="${ACMEDNS_BASE_URL:-$(_readdomainconf ACMEDNS_BASE_URL)}"
  export ACMEDNS_USERNAME_$h="${!ACMEDNS_USERNAME:-$(_readdomainconf ACMEDNS_USERNAME)}"
  export ACMEDNS_PASSWORD_$h="${!ACMEDNS_PASSWORD:-$(_readdomainconf ACMEDNS_PASSWORD)}"
  export ACMEDNS_SUBDOMAIN_$h="${!ACMEDNS_SUBDOMAIN:-$(_readdomainconf ACMEDNS_SUBDOMAIN)}"

  if [ "$ACMEDNS_BASE_URL" = "" ]; then
    ACMEDNS_BASE_URL="https://auth.acme-dns.io"
  fi

  ACMEDNS_UPDATE_URL="$ACMEDNS_BASE_URL/update"
  ACMEDNS_REGISTER_URL="$ACMEDNS_BASE_URL/register"

  if [ -z "${!ACMEDNS_USERNAME}" ] || [ -z "${!ACMEDNS_PASSWORD}" ]; then
    response="$(_post "" "$ACMEDNS_REGISTER_URL" "" "POST")"
    _debug response "$response"
    export ACMEDNS_USERNAME_$h=$(echo "$response" | sed -n 's/^{.*\"username\":[ ]*\"\([^\"]*\)\".*}/\1/p')
    _debug "received username: ${!ACMEDNS_USERNAME}"
    export ACMEDNS_PASSWORD_$h=$(echo "$response" | sed -n 's/^{.*\"password\":[ ]*\"\([^\"]*\)\".*}/\1/p')
    _debug "received password: ${!ACMEDNS_PASSWORD}"
    export ACMEDNS_SUBDOMAIN_$h=$(echo "$response" | sed -n 's/^{.*\"subdomain\":[ ]*\"\([^\"]*\)\".*}/\1/p')
    _debug "received subdomain: ${!ACMEDNS_SUBDOMAIN}"
    ACMEDNS_FULLDOMAIN="ACMEDNS_FULLDOMAIN_$h"
    export ACMEDNS_FULLDOMAIN_$h=$(echo "$response" | sed -n 's/^{.*\"fulldomain\":[ ]*\"\([^\"]*\)\".*}/\1/p')
    _info "##########################################################"
    _info "# Create $fulldomain CNAME ${!ACMEDNS_FULLDOMAIN} DNS entry #"
    _info "##########################################################"
    _info "Press enter to continue... "
    read -r _
  fi

  _savedomainconf ACMEDNS_BASE_URL "$ACMEDNS_BASE_URL"
  _savedomainconf $ACMEDNS_USERNAME "${!ACMEDNS_USERNAME}"
  _savedomainconf $ACMEDNS_PASSWORD "${!ACMEDNS_PASSWORD}"
  _savedomainconf $ACMEDNS_SUBDOMAIN "${!ACMEDNS_SUBDOMAIN}"

  export _H1="X-Api-User: ${!ACMEDNS_USERNAME}"
  export _H2="X-Api-Key: ${!ACMEDNS_PASSWORD}"
  data="{\"subdomain\":\"${!ACMEDNS_SUBDOMAIN}\", \"txt\": \"$txtvalue\"}"

  _debug data "$data"
  response="$(_post "$data" "$ACMEDNS_UPDATE_URL" "" "POST")"
  _debug response "$response"

  if ! echo "$response" | grep "\"$txtvalue\"" >/dev/null; then
    _err "invalid response of acme-dns"
    return 1
  fi

}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_acmedns_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using acme-dns"
  _debug "fulldomain $fulldomain"
  _debug "txtvalue $txtvalue"
}

####################  Private functions below ##################################

#!/usr/bin/env sh

#This file name is "dns_freedns.sh"
#So, here must be a method dns_freedns_add()
#Which will be called by acme.sh to add the txt record to your api system.
#returns 0 means success, otherwise error.
#
#Author: David Kerr
#Report Bugs here: https://github.com/dkerr64/acme.sh
#or here... https://github.com/acmesh-official/acme.sh/issues/2305
#
########  Public functions #####################

# Export FreeDNS userid and password in following variables...
#  FREEDNS_User=username
#  FREEDNS_Password=password
# login cookie is saved in acme account config file so userid / pw
# need to be set only when changed.

#Usage: dns_freedns_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_freedns_add() {
  fulldomain="$1"
  txtvalue="$2"

  _info "Add TXT record using FreeDNS"
  _debug "fulldomain: $fulldomain"
  _debug "txtvalue: $txtvalue"

  if [ -z "$FREEDNS_User" ] || [ -z "$FREEDNS_Password" ]; then
    FREEDNS_User=""
    FREEDNS_Password=""
    if [ -z "$FREEDNS_COOKIE" ]; then
      _err "You did not specify the FreeDNS username and password yet."
      _err "Please export as FREEDNS_User / FREEDNS_Password and try again."
      return 1
    fi
    using_cached_cookies="true"
  else
    FREEDNS_COOKIE="$(_freedns_login "$FREEDNS_User" "$FREEDNS_Password")"
    if [ -z "$FREEDNS_COOKIE" ]; then
      return 1
    fi
    using_cached_cookies="false"
  fi

  _debug "FreeDNS login cookies: $FREEDNS_COOKIE (cached = $using_cached_cookies)"

  _saveaccountconf FREEDNS_COOKIE "$FREEDNS_COOKIE"

  # We may have to cycle through the domain name to find the
  # TLD that we own...
  i=1
  wmax="$(echo "$fulldomain" | tr '.' ' ' | wc -w)"
  while [ "$i" -lt "$wmax" ]; do
    # split our full domain name into two parts...
    sub_domain="$(echo "$fulldomain" | cut -d. -f -"$i")"
    i="$(_math "$i" + 1)"
    top_domain="$(echo "$fulldomain" | cut -d. -f "$i"-100)"
    _debug "sub_domain: $sub_domain"
    _debug "top_domain: $top_domain"

    DNSdomainid="$(_freedns_domain_id "$top_domain")"
    if [ "$?" = "0" ]; then
      _info "Domain $top_domain found at FreeDNS, domain_id $DNSdomainid"
      break
    else
      _info "Domain $top_domain not found at FreeDNS, try with next level of TLD"
    fi
  done

  if [ -z "$DNSdomainid" ]; then
    # If domain ID is empty then something went wrong (top level
    # domain not found at FreeDNS).
    _err "Domain $top_domain not found at FreeDNS"
    return 1
  fi

  # Add in new TXT record with the value provided
  _debug "Adding TXT record for $fulldomain, $txtvalue"
  _freedns_add_txt_record "$FREEDNS_COOKIE" "$DNSdomainid" "$sub_domain" "$txtvalue"
  return $?
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_freedns_rm() {
  fulldomain="$1"
  txtvalue="$2"

  _info "Delete TXT record using FreeDNS"
  _debug "fulldomain: $fulldomain"
  _debug "txtvalue: $txtvalue"

  # Need to read cookie from conf file again in case new value set
  # during login to FreeDNS when TXT record was created.
  FREEDNS_COOKIE="$(_readaccountconf "FREEDNS_COOKIE")"
  _debug "FreeDNS login cookies: $FREEDNS_COOKIE"

  TXTdataid="$(_freedns_data_id "$fulldomain" "TXT")"
  if [ "$?" != "0" ]; then
    _info "Cannot delete TXT record for $fulldomain, record does not exist at FreeDNS"
    return 1
  fi
  _debug "Data ID's found, $TXTdataid"

  # now we have one (or more) TXT record data ID's. Load the page
  # for that record and search for the record txt value.  If match
  # then we can delete it.
  lines="$(echo "$TXTdataid" | wc -l)"
  _debug "Found $lines TXT data records for $fulldomain"
  i=0
  while [ "$i" -lt "$lines" ]; do
    i="$(_math "$i" + 1)"
    dataid="$(echo "$TXTdataid" | sed -n "${i}p")"
    _debug "$dataid"

    htmlpage="$(_freedns_retrieve_data_page "$FREEDNS_COOKIE" "$dataid")"
    if [ "$?" != "0" ]; then
      if [ "$using_cached_cookies" = "true" ]; then
        _err "Has your FreeDNS username and password changed?  If so..."
        _err "Please export as FREEDNS_User / FREEDNS_Password and try again."
      fi
      return 1
    fi

    echo "$htmlpage" | grep "value=\"&quot;$txtvalue&quot;\"" >/dev/null
    if [ "$?" = "0" ]; then
      # Found a match... delete the record and return
      _info "Deleting TXT record for $fulldomain, $txtvalue"
      _freedns_delete_txt_record "$FREEDNS_COOKIE" "$dataid"
      return $?
    fi
  done

  # If we get this far we did not find a match
  # Not necessarily an error, but log anyway.
  _info "Cannot delete TXT record for $fulldomain, $txtvalue. Does not exist at FreeDNS"
  return 0
}

####################  Private functions below ##################################

# usage: _freedns_login username password
# print string "cookie=value" etc.
# returns 0 success
_freedns_login() {
  export _H1="Accept-Language:en-US"
  username="$1"
  password="$2"
  url="https://freedns.afraid.org/zc.php?step=2"

  _debug "Login to FreeDNS as user $username"

  htmlpage="$(_post "username=$(printf '%s' "$username" | _url_encode)&password=$(printf '%s' "$password" | _url_encode)&submit=Login&action=auth" "$url")"

  if [ "$?" != "0" ]; then
    _err "FreeDNS login failed for user $username bad RC from _post"
    return 1
  fi

  cookies="$(grep -i '^Set-Cookie.*dns_cookie.*$' "$HTTP_HEADER" | _head_n 1 | tr -d "\r\n" | cut -d " " -f 2)"

  # if cookies is not empty then logon successful
  if [ -z "$cookies" ]; then
    _debug3 "htmlpage: $htmlpage"
    _err "FreeDNS login failed for user $username. Check $HTTP_HEADER file"
    return 1
  fi

  printf "%s" "$cookies"
  return 0
}

# usage _freedns_retrieve_subdomain_page login_cookies
# echo page retrieved (html)
# returns 0 success
_freedns_retrieve_subdomain_page() {
  export _H1="Cookie:$1"
  export _H2="Accept-Language:en-US"
  url="https://freedns.afraid.org/subdomain/"

  _debug "Retrieve subdomain page from FreeDNS"

  htmlpage="$(_get "$url")"

  if [ "$?" != "0" ]; then
    _err "FreeDNS retrieve subdomains failed bad RC from _get"
    return 1
  elif [ -z "$htmlpage" ]; then
    _err "FreeDNS returned empty subdomain page"
    return 1
  fi

  _debug3 "htmlpage: $htmlpage"

  printf "%s" "$htmlpage"
  return 0
}

# usage _freedns_retrieve_data_page login_cookies data_id
# echo page retrieved (html)
# returns 0 success
_freedns_retrieve_data_page() {
  export _H1="Cookie:$1"
  export _H2="Accept-Language:en-US"
  data_id="$2"
  url="https://freedns.afraid.org/subdomain/edit.php?data_id=$2"

  _debug "Retrieve data page for ID $data_id from FreeDNS"

  htmlpage="$(_get "$url")"

  if [ "$?" != "0" ]; then
    _err "FreeDNS retrieve data page failed bad RC from _get"
    return 1
  elif [ -z "$htmlpage" ]; then
    _err "FreeDNS returned empty data page"
    return 1
  fi

  _debug3 "htmlpage: $htmlpage"

  printf "%s" "$htmlpage"
  return 0
}

# usage _freedns_add_txt_record login_cookies domain_id subdomain value
# returns 0 success
_freedns_add_txt_record() {
  export _H1="Cookie:$1"
  export _H2="Accept-Language:en-US"
  domain_id="$2"
  subdomain="$3"
  value="$(printf '%s' "$4" | _url_encode)"
  url="https://freedns.afraid.org/subdomain/save.php?step=2"

  htmlpage="$(_post "type=TXT&domain_id=$domain_id&subdomain=$subdomain&address=%22$value%22&send=Save%21" "$url")"

  if [ "$?" != "0" ]; then
    _err "FreeDNS failed to add TXT record for $subdomain bad RC from _post"
    return 1
  elif ! grep "200 OK" "$HTTP_HEADER" >/dev/null; then
    _debug3 "htmlpage: $htmlpage"
    _err "FreeDNS failed to add TXT record for $subdomain. Check $HTTP_HEADER file"
    return 1
  elif _contains "$htmlpage" "security code was incorrect"; then
    _debug3 "htmlpage: $htmlpage"
    _err "FreeDNS failed to add TXT record for $subdomain as FreeDNS requested security code"
    _err "Note that you cannot use automatic DNS validation for FreeDNS public domains"
    return 1
  fi

  _debug3 "htmlpage: $htmlpage"
  _info "Added acme challenge TXT record for $fulldomain at FreeDNS"
  return 0
}

# usage _freedns_delete_txt_record login_cookies data_id
# returns 0 success
_freedns_delete_txt_record() {
  export _H1="Cookie:$1"
  export _H2="Accept-Language:en-US"
  data_id="$2"
  url="https://freedns.afraid.org/subdomain/delete2.php"

  htmlheader="$(_get "$url?data_id%5B%5D=$data_id&submit=delete+selected" "onlyheader")"

  if [ "$?" != "0" ]; then
    _err "FreeDNS failed to delete TXT record for $data_id bad RC from _get"
    return 1
  elif ! _contains "$htmlheader" "200 OK"; then
    _debug2 "htmlheader: $htmlheader"
    _err "FreeDNS failed to delete TXT record $data_id"
    return 1
  fi

  _info "Deleted acme challenge TXT record for $fulldomain at FreeDNS"
  return 0
}

# usage _freedns_domain_id domain_name
# echo the domain_id if found
# return 0 success
_freedns_domain_id() {
  # Start by escaping the dots in the domain name
  search_domain="$(echo "$1" | sed 's/\./\\./g')"

  # Sometimes FreeDNS does not return the subdomain page but rather
  # returns a page regarding becoming a premium member.  This usually
  # happens after a period of inactivity.  Immediately trying again
  # returns the correct subdomain page.  So, we will try twice to
  # load the page and obtain our domain ID
  attempts=2
  while [ "$attempts" -gt "0" ]; do
    attempts="$(_math "$attempts" - 1)"

    htmlpage="$(_freedns_retrieve_subdomain_page "$FREEDNS_COOKIE")"
    if [ "$?" != "0" ]; then
      if [ "$using_cached_cookies" = "true" ]; then
        _err "Has your FreeDNS username and password changed?  If so..."
        _err "Please export as FREEDNS_User / FREEDNS_Password and try again."
      fi
      return 1
    fi

    domain_id="$(echo "$htmlpage" | tr -d " \t\r\n\v\f" | sed 's/<tr>/@<tr>/g' | tr '@' '\n' \
      | grep "<td>$search_domain</td>\|<td>$search_domain(.*)</td>" \
      | sed -n 's/.*\(edit\.php?edit_domain_id=[0-9a-zA-Z]*\).*/\1/p' \
      | cut -d = -f 2)"
    # The above beauty extracts domain ID from the html page...
    # strip out all blank space and new lines. Then insert newlines
    # before each table row <tr>
    # search for the domain within each row (which may or may not have
    # a text string in brackets (.*) after it.
    # And finally extract the domain ID.
    if [ -n "$domain_id" ]; then
      printf "%s" "$domain_id"
      return 0
    fi
    _debug "Domain $search_domain not found. Retry loading subdomain page ($attempts attempts remaining)"
  done
  _debug "Domain $search_domain not found after retry"
  return 1
}

# usage _freedns_data_id domain_name record_type
# echo the data_id(s) if found
# return 0 success
_freedns_data_id() {
  # Start by escaping the dots in the domain name
  search_domain="$(echo "$1" | sed 's/\./\\./g')"
  record_type="$2"

  # Sometimes FreeDNS does not return the subdomain page but rather
  # returns a page regarding becoming a premium member.  This usually
  # happens after a period of inactivity.  Immediately trying again
  # returns the correct subdomain page.  So, we will try twice to
  # load the page and obtain our domain ID
  attempts=2
  while [ "$attempts" -gt "0" ]; do
    attempts="$(_math "$attempts" - 1)"

    htmlpage="$(_freedns_retrieve_subdomain_page "$FREEDNS_COOKIE")"
    if [ "$?" != "0" ]; then
      if [ "$using_cached_cookies" = "true" ]; then
        _err "Has your FreeDNS username and password changed?  If so..."
        _err "Please export as FREEDNS_User / FREEDNS_Password and try again."
      fi
      return 1
    fi

    data_id="$(echo "$htmlpage" | tr -d " \t\r\n\v\f" | sed 's/<tr>/@<tr>/g' | tr '@' '\n' \
      | grep "<td[a-zA-Z=#]*>$record_type</td>" \
      | grep "<ahref.*>$search_domain</a>" \
      | sed -n 's/.*\(edit\.php?data_id=[0-9a-zA-Z]*\).*/\1/p' \
      | cut -d = -f 2)"
    # The above beauty extracts data ID from the html page...
    # strip out all blank space and new lines. Then insert newlines
    # before each table row <tr>
    # search for the record type withing each row (e.g. TXT)
    # search for the domain within each row (which is within a <a..>
    # </a> anchor. And finally extract the domain ID.
    if [ -n "$data_id" ]; then
      printf "%s" "$data_id"
      return 0
    fi
    _debug "Domain $search_domain not found. Retry loading subdomain page ($attempts attempts remaining)"
  done
  _debug "Domain $search_domain not found after retry"
  return 1
}

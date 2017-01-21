
#!/usr/bin/env sh

#This file name is "dns_freedns.sh"
#So, here must be a method dns_freedns_add()
#Which will be called by acme.sh to add the txt record to your api system.
#returns 0 means success, otherwise error.
#
#Author: David Kerr
#Report Bugs here: https://github.com/Neilpang/acme.sh
#
########  Public functions #####################

# Requires FreeDNS userid and password in folowing variables...
# FREEDNS_USER=username
# FREEDNS_PASSWORD=password

#Usage: dns_freedns_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_freedns_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Add TXT record using FreeDNS"
  _debug "fulldomain: $fulldomain"
  _debug "txtvalue: $txtvalue"
  
  if [ -z "$FREEDNS_USER" ] || [ -z "$FREEDNS_PASSWORD" ]; then
    AD_API_KEY=""
    _err "You didn't specify the FreeDNS username and password yet."
    _err "Please export as FREEDNS_USER / FREEDNS_PASSWORD and try again."
    return 1
  fi
  
  login_cookies="$(_freedns_login $FREEDNS_USER $FREEDNS_PASSWORD)"
  if [ -z "$login_cookies" ]; then
    return 1
  fi
  
  _saveaccountconf FREEDNS_USER "$FREEDNS_USER"
  _saveaccountconf FREEDNS_PASSWORD "$FREEDNS_PASSWORD"

  htmlpage="$(_freedns_retrieve_subdomain_page $login_cookies)"
  if [ $? != 0 ]; then
    return $?
  fi

  # split our full domain name into two parts...
  top_domain="$(echo $fulldomain | rev | cut -d. -f -2 | rev)"
  sub_domain="$(echo $fulldomain | rev | cut -d. -f 3- | rev)"

  # Now convert the tables in the HTML to CSV.  This litte gem from
  # http://stackoverflow.com/questions/1403087/how-can-i-convert-an-html-table-to-csv
  subdomain_csv="$(echo $htmlpage |
    grep -i -e '</\?TABLE\|</\?TD\|</\?TR\|</\?TH' |
    sed 's/^[\ \t]*//g' |
    tr -d '\n' |
    sed 's/<\/TR[^>]*>/\n/Ig' |
    sed 's/<\/\?\(TABLE\|TR\)[^>]*>//Ig' |
    sed 's/^<T[DH][^>]*>\|<\/\?T[DH][^>]*>$//Ig' |
    sed 's/<\/T[DH][^>]*><T[DH][^>]*>/,/Ig' |
    grep 'edit.php?' |
    grep $top_domain)"
  # The above beauty ends with striping out rows that do not have an
  # href to edit.php and do not have the top domain we are looking for.
  # So all we should be left with is CSV of table of subdomains we are
  # interested in.
  
  # Now we have to read through this table and extract the data we need
  IFS=$'\n'
  found=0
  for line in $subdomain_csv
  do
    tmp="$(echo $line | cut -d ',' -f 1)"
    if [ $found = 0 ] && _startswith "$tmp" "<td>$top_domain"; then
      # this line will contain DNSdomainid for the top_domain
      tmp="$(echo $line | cut -d ',' -f 2)"
      url=${tmp#*=}
      url=${url%%>*}
      DNSdomainid=${url#*domain_id=}
      found=1
    else
      # lines contain DNS records for all subdomains
      dns_href="$(echo $line | cut -d ',' -f 2)"
      tmp=${dns_href#*>}
      DNSname=${tmp%%<*}
      DNStype="$(echo $line | cut -d ',' -f 3)"
      if [ "$DNSname" = "$fulldomain" -a "$DNStype" = "TXT" ]; then
        tmp=${dns_href#*=}
        url=${tmp%%>*}
        DNSdataid=${url#*data_id=}    
        # Now get current value for the TXT record.  This method may
        # produce inaccurate results as the value field is truncated
        # on this webpage. To get full value we would need to load
        # another page.  However we don't really need this so long as
        # there is only one TXT record for the acme chalenge subdomain.
        tmp="$(echo $line | cut -d ',' -f 4)"
        # strip the html double-quotes off the value
        tmp=${tmp#&quot;}
        DNSvalue=${tmp%&quot;}
        if [ $found != 0 ]; then
          break
          # we are breaking out of the loop at the first match of DNS name
          # and DNS type (if we are past finding the domainid). This assumes
          # that there is only ever one TXT record for the LetsEncrypt/acme
          # challenge subdomain.  This seems to be a reasonable assumption
          # as the acme client deletes the TXT record on successful validation.
        fi
      else
        DNSname=""
        DNStype=""
      fi
    fi
  done
  unset IFS

  _debug "DNSname: $DNSname DNStype: $DNStype DNSdomainid: $DNSdomainid DNSdataid: $DNSdataid"
  _debug "DNSvalue: $DNSvalue"

  if [ -z "$DNSdomainid" ]; then
    # If domain ID is empty then something went wrong (top level
    # domain not found at FreeDNS). Cannot proceed.
    _debug2 "$htmlpage"
    _debug2 "$subdomain_csv"
    _err "Domain $top_domain not found at FreeDNS"
    return 1
  fi

  if [ -z "$DNSdataid" ]; then
    # If data ID is empty then specific subdomain does not exist yet, need
    # to create it this should always be the case as the acme client
    # deletes the entry after domain is validated.
    _freedns_add_txt_record $login_cookies $DNSdomainid $sub_domain "$txtvalue"
    return $?
  else
    if [ "$txtvalue" = "$DNSvalue" ]; then
      # if value in TXT record matches value requested then DNS record
      # does not need to be updated. But...
      # Testing value match fails.  Website is truncating the value field.
      # So for now we will always go down the else path.  Though in theory
      # should never come here anyway as the acme client deletes
      # the TXT record on successful validation, so we should not even
      # have found a TXT record !!
      _info "No update necessary for $fulldomain at FreeDNS"
      return 0
    else
      # Delete the old TXT record (with the wrong value)
      _freedns_delete_txt_record $login_cookies $DNSdataid
      if [ $? = 0 ]; then
        # And add in new TXT record with the value provided
        _freedns_add_txt_record $login_cookies $DNSdomainid $sub_domain "$txtvalue"
      fi
      return $?
    fi
  fi
  return 0
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_freedns_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "Delete TXT record using FreeDNS"
  _debug "fulldomain: $fulldomain"
  _debug "txtvalue: $txtvalue"
  
  login_cookies="$(_freedns_login $FREEDNS_USER $FREEDNS_PASSWORD)"
  if [ -z "$login_cookies" ]; then
    return 1
  fi

  htmlpage="$(_freedns_retrieve_subdomain_page $login_cookies)"
  if [ $? != 0 ]; then
    return $?
  fi

  # Now convert the tables in the HTML to CSV.  This litte gem from
  # http://stackoverflow.com/questions/1403087/how-can-i-convert-an-html-table-to-csv
  subdomain_csv="$(echo $htmlpage |
    grep -i -e '</\?TABLE\|</\?TD\|</\?TR\|</\?TH' |
    sed 's/^[\ \t]*//g' |
    tr -d '\n' |
    sed 's/<\/TR[^>]*>/\n/Ig' |
    sed 's/<\/\?\(TABLE\|TR\)[^>]*>//Ig' |
    sed 's/^<T[DH][^>]*>\|<\/\?T[DH][^>]*>$//Ig' |
    sed 's/<\/T[DH][^>]*><T[DH][^>]*>/,/Ig' |
    grep 'edit.php?' |
    grep $fulldomain)"
  # The above beauty ends with striping out rows that do not have an
  # href to edit.php and do not have the domain name we are looking for.
  # So all we should be left with is CSV of table of subdomains we are
  # interested in.
  
  # Now we have to read through this table and extract the data we need
  IFS=$'\n'
  for line in $subdomain_csv
  do
    dns_href="$(echo $line | cut -d ',' -f 2)"
    tmp=${dns_href#*>}
    DNSname=${tmp%%<*}
    DNStype="$(echo $line | cut -d ',' -f 3)"
    if [ "$DNSname" = "$fulldomain" -a "$DNStype" = "TXT" ]; then
      tmp=${dns_href#*=}
      url=${tmp%%>*}
      DNSdataid=${url#*data_id=}
      tmp="$(echo $line | cut -d ',' -f 4)"
      # strip the html double-quotes off the value
      tmp=${tmp#&quot;}
      DNSvalue=${tmp%&quot;}
      _debug "DNSvalue: $DNSvalue"
#     if [ "$DNSvalue" = "$txtvalue" ]; then
        # Testing value match fails.  Website is truncating the value
        # field. So for now we will assume that there is only one TXT
        # field for the sub domain and just delete it. Currently this
        # is a safe assumption.
        _freedns_delete_txt_record $login_cookies $DNSdataid
        unset IFS
        return $?
#     fi
    fi
  done
  unset IFS
  
  # If we get this far we did not find a match.
  # Not necessarily an error, but log anyway.
  _debug2 "$subdomain_csv"
  _info "Cannot delete TXT record for $fulldomain/$txtvalue. Does not exist at FreeDNS"
  return 0
}

####################  Private functions below ##################################

# usage: _freedns_login username password
# echos string "cookie:value;cookie:value" etc
# returns 0 success
_freedns_login() {
  username=$1
  password=$2
  url="https://freedns.afraid.org/zc.php?step=2"
  
  _debug "Login to FreeDNS as user $username"
  # Not using acme.sh _post() function because I need to capture the cookies.
  cookie_file="$(curl --silent \
              --user-agent "$USER_AGENT" \
              --data "username=$(_freedns_urlencode "$username")&password=$(_freedns_urlencode "$password")&submit=Login&action=auth" \
              --cookie-jar - \
              $url )"
   
  if [ $? != 0 ]; then
    _err "FreeDNS login failed for user $username bad RC from cURL: $?"
    return $?
  fi
  
  # convert from cookie file format to cookie string
  cookies=""
  found=0
  IFS=$'\n'
  for line in $cookie_file
  do
    # strip spaces from start and end of line
    line="$(echo "$line" | xargs)"
    if [ $found = 0 ]; then
      # first line, validate that it is a cookie file
      if _contains "$line" "Netscape HTTP Cookie File"; then
        found=1
      else
        _debug2 "$cookie_file"
        _err "FreeDNS login failed for user $username bad cookie file"
        unset IFS
        return 1
      fi
    else
      # after first line skip blank line or comments
      if [ -n "$line" -a "$(echo $line | cut -c 1)" != "#" ]; then
        if [ -n "$cookies" ]; then
          cookies="$cookies;"
        fi
        cookies="$cookies$(echo $line | cut -d ' ' -f 6)=$(echo $line | cut -d ' ' -f 7)"
      fi
    fi
  done
  unset IFS
  
  # if cookies is not empty then logon successful
  if [ -z "$cookies" ]; then
    _err "FreeDNS login failed for user $username"
    return 1
  fi

  _debug "FreeDNS login cookies: $cookies"
  echo "$cookies"
  return 0
}

# usage _freedns_retrieve_subdomain_page login_cookies
# echo page retrieved (html)
# returns 0 success
_freedns_retrieve_subdomain_page() {
  cookies=$1
  url="https://freedns.afraid.org/subdomain/"

  _debug "Retrieve subdmoain page from FreeDNS"
  # Not using acme.sh _get() function becuase I need to pass in the cookies.
  htmlpage="$(curl --silent \
              --user-agent "$USER_AGENT" \
              --cookie "$cookies" \
              $url )"

  if [ $? != 0 ]; then
    _err "FreeDNS retrieve subdomins failed bad RC from cURL: $?"
    return $?
  fi
  
  if [ -z "$htmlpage" ]; then
    _err "FreeDNS returned empty subdomain page"
    return 1
  fi
  
  _debug2 "$htmlpage"

  echo "$htmlpage"
  return 0
}

_freedns_add_txt_record() {
  cookies=$1
  domain_id=$2
  subdomain=$3
  value="$(_freedns_urlencode "$4")"
  url="http://freedns.afraid.org/subdomain/save.php?step=2"

  # Not using acme.sh _get() function becuase I need to pass in the cookies.  
  htmlpage="$(curl --silent \
            --user-agent "$USER_AGENT" \
            --cookie "$cookies" \
            --data "type=TXT&domain_id=$domain_id&subdomain=$subdomain&address=%22$value%22&send=Save%21" \
            $url )"

  if [ $? != 0 ]; then
    _err "FreeDNS failed to add TXT record for $subdomain bad RC from cURL: $?"
    return $?
  fi
  
  # returned page should be empty on success
  if [ -n "$htmlpage" ]; then
    _debug2 "$htmlpage"
    _err "FreeDNS failed to add TXT record for $subdomain"
    return 1
  fi
  _info "Added acme challenge TXT record for $fulldomain at FreeDNS"
  return 0
}

_freedns_delete_txt_record() {
  cookies=$1
  data_id=$2
  url="https://freedns.afraid.org/subdomain/delete2.php"

  # Not using acme.sh _get() function becuase I need to pass in the cookies.
  htmlpage="$(curl --silent \
            --user-agent "$USER_AGENT" \
            --cookie "$cookies" \
            "$url?data_id%5B%5D=$data_id&submit=delete+selected" )"

  if [ $? != 0 ]; then
    _err "FreeDNS failed to delete TXT record for $subdomain bad RC from cURL: $?"
    return $?
  fi

  # returned page should be empty on success
  if [ -n "$htmlpage" ]; then
    _debug2 "$htmlpage"
    _err "FreeDNS failed to delete TXT record $data_id"
    return 1
  fi
  _info "Deleted acme challenge TXT record for $fulldomain at FreeDNS"
  return 0
}

# urlencode magic from...
# http://askubuntu.com/questions/53770/how-can-i-encode-and-decode-percent-encoded-strings-on-the-command-line
# The _urlencode function in acme.sh does not work !
_freedns_urlencode() {
  # urlencode <string>
  length="${#1}"
  for (( i = 0; i < length; i++ )); do
    c="${1:i:1}"
    case $c in
      [a-zA-Z0-9.~_-]) printf "$c" ;;
      *) printf '%%%02X' "'$c"
    esac
  done
}

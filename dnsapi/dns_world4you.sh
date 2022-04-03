#!/usr/bin/env sh

# World4You - www.world4you.com
# Lorenz Stechauner, 2020 - https://www.github.com/NerLOR

WORLD4YOU_API="https://my.world4you.com/en"
PAKETNR=''
TLD=''
RECORD=''

################ Public functions ################

# Usage: dns_world4you_add <fqdn> <value>
dns_world4you_add() {
  fqdn="$1"
  value="$2"
  _info "Using world4you to add record"
  _debug fulldomain "$fqdn"
  _debug txtvalue "$value"

  _login
  if [ "$?" != 0 ]; then
    return 1
  fi

  export _H1="Cookie: W4YSESSID=$sessid"
  form=$(_get "$WORLD4YOU_API/")
  _get_paketnr "$fqdn" "$form"
  paketnr="$PAKETNR"
  if [ -z "$paketnr" ]; then
    _err "Unable to parse paketnr"
    return 3
  fi
  _debug paketnr "$paketnr"

  export _H1="Cookie: W4YSESSID=$sessid"
  form=$(_get "$WORLD4YOU_API/$paketnr/dns")
  formiddp=$(echo "$form" | grep 'AddDnsRecordForm\[uniqueFormIdDP\]' | sed 's/^.*name="AddDnsRecordForm\[uniqueFormIdDP\]" value="\([^"]*\)".*$/\1/')
  form_token=$(echo "$form" | grep 'AddDnsRecordForm\[_token\]' | sed 's/^.*name="AddDnsRecordForm\[_token\]" value="\([^"]*\)".*$/\1/')
  if [ -z "$formiddp" ]; then
    _err "Unable to parse form"
    return 3
  fi

  _resethttp
  export ACME_HTTP_NO_REDIRECTS=1
  body="AddDnsRecordForm[name]=$RECORD&AddDnsRecordForm[dnsType][type]=TXT&AddDnsRecordForm[value]=$value&AddDnsRecordForm[uniqueFormIdDP]=$formiddp&AddDnsRecordForm[_token]=$form_token"
  _info "Adding record..."
  ret=$(_post "$body" "$WORLD4YOU_API/$paketnr/dns" '' POST 'application/x-www-form-urlencoded')
  _resethttp

  if _contains "$(_head_n 3 <"$HTTP_HEADER")" '302'; then
    res=$(_get "$WORLD4YOU_API/$paketnr/dns")
    if _contains "$res" "successfully"; then
      return 0
    else
      msg=$(echo "$res" | tr '\n' '\t' | sed 's/.*<h3 class="mb-5">[^\t]*\t *\([^\t]*\)\t.*/\1/')
      if _contains "$msg" '^<\!DOCTYPE html>'; then
        msg='Unknown error'
      fi
      _err "Unable to add record: $msg"
      if _contains "$msg" '^<\!DOCTYPE html>'; then
        echo "$ret" >'error-01.html'
        echo "$res" >'error-02.html'
        _err "View error-01.html and error-02.html for debugging"
      fi
      return 1
    fi
  else
    _err "$(_head_n 3 <"$HTTP_HEADER")"
    _err "View $HTTP_HEADER for debugging"
    return 1
  fi
}

# Usage: dns_world4you_rm <fqdn> <value>
dns_world4you_rm() {
  fqdn="$1"
  value="$2"
  _info "Using world4you to remove record"
  _debug fulldomain "$fqdn"
  _debug txtvalue "$value"

  _login
  if [ "$?" != 0 ]; then
    return 1
  fi

  export _H1="Cookie: W4YSESSID=$sessid"
  form=$(_get "$WORLD4YOU_API/")
  _get_paketnr "$fqdn" "$form"
  paketnr="$PAKETNR"
  if [ -z "$paketnr" ]; then
    _err "Unable to parse paketnr"
    return 3
  fi
  _debug paketnr "$paketnr"

  form=$(_get "$WORLD4YOU_API/$paketnr/dns")
  formiddp=$(echo "$form" | grep 'DeleteDnsRecordForm\[uniqueFormIdDP\]' | sed 's/^.*name="DeleteDnsRecordForm\[uniqueFormIdDP\]" value="\([^"]*\)".*$/\1/')
  form_token=$(echo "$form" | grep 'DeleteDnsRecordForm\[_token\]' | sed 's/^.*name="DeleteDnsRecordForm\[_token\]" value="\([^"]*\)".*$/\1/')
  if [ -z "$formiddp" ]; then
    _err "Unable to parse form"
    return 3
  fi

  recordid=$(printf "TXT:%s.:\"%s\"" "$fqdn" "$value" | _base64)
  _debug recordid "$recordid"

  _resethttp
  export ACME_HTTP_NO_REDIRECTS=1
  body="DeleteDnsRecordForm[recordId]=$recordid&DeleteDnsRecordForm[uniqueFormIdDP]=$formiddp&DeleteDnsRecordForm[_token]=$form_token"
  _info "Removing record..."
  ret=$(_post "$body" "$WORLD4YOU_API/$paketnr/dns/record/delete" '' POST 'application/x-www-form-urlencoded')
  _resethttp

  if _contains "$(_head_n 3 <"$HTTP_HEADER")" '302'; then
    res=$(_get "$WORLD4YOU_API/$paketnr/dns")
    if _contains "$res" "successfully"; then
      return 0
    else
      msg=$(echo "$res" | tr '\n' '\t' | sed 's/.*<h3 class="mb-5">[^\t]*\t *\([^\t]*\)\t.*/\1/')
      if _contains "$msg" '^<\!DOCTYPE html>'; then
        msg='Unknown error'
      fi
      _err "Unable to remove record: $msg"
      if _contains "$msg" '^<\!DOCTYPE html>'; then
        echo "$ret" >'error-01.html'
        echo "$res" >'error-02.html'
        _err "View error-01.html and error-02.html for debugging"
      fi
      return 1
    fi
  else
    _err "$(_head_n 3 <"$HTTP_HEADER")"
    _err "View $HTTP_HEADER for debugging"
    return 1
  fi
}

################ Private functions ################

# Usage: _login
_login() {
  WORLD4YOU_USERNAME="${WORLD4YOU_USERNAME:-$(_readaccountconf_mutable WORLD4YOU_USERNAME)}"
  WORLD4YOU_PASSWORD="${WORLD4YOU_PASSWORD:-$(_readaccountconf_mutable WORLD4YOU_PASSWORD)}"

  if [ -z "$WORLD4YOU_USERNAME" ] || [ -z "$WORLD4YOU_PASSWORD" ]; then
    WORLD4YOU_USERNAME=""
    WORLD4YOU_PASSWORD=""
    _err "You didn't specify world4you username and password yet."
    _err "Usage: export WORLD4YOU_USERNAME=<name>"
    _err "Usage: export WORLD4YOU_PASSWORD=<password>"
    return 1
  fi

  _saveaccountconf_mutable WORLD4YOU_USERNAME "$WORLD4YOU_USERNAME"
  _saveaccountconf_mutable WORLD4YOU_PASSWORD "$WORLD4YOU_PASSWORD"

  _info "Logging in..."

  username="$WORLD4YOU_USERNAME"
  password="$WORLD4YOU_PASSWORD"
  csrf_token=$(_get "$WORLD4YOU_API/login" | grep '_csrf_token' | sed 's/^.*<input[^>]*value=\"\([^"]*\)\".*$/\1/')
  sessid=$(grep 'W4YSESSID' <"$HTTP_HEADER" | sed 's/^.*W4YSESSID=\([^;]*\);.*$/\1/')

  export _H1="Cookie: W4YSESSID=$sessid"
  export _H2="X-Requested-With: XMLHttpRequest"
  body="_username=$username&_password=$password&_csrf_token=$csrf_token"
  ret=$(_post "$body" "$WORLD4YOU_API/login" '' POST 'application/x-www-form-urlencoded')
  unset _H2
  _debug ret "$ret"
  if _contains "$ret" "\"success\":true"; then
    _info "Successfully logged in"
    sessid=$(grep 'W4YSESSID' <"$HTTP_HEADER" | sed 's/^.*W4YSESSID=\([^;]*\);.*$/\1/')
  else
    _err "Unable to log in: $(echo "$ret" | sed 's/^.*"message":"\([^\"]*\)".*$/\1/')"
    return 1
  fi
}

# Usage _get_paketnr <fqdn> <form>
_get_paketnr() {
  fqdn="$1"
  form="$2"

  domains=$(echo "$form" | grep 'header-paket-domain' | sed 's/<[^>]*>//g' | sed 's/^.*>\([^>]*\)$/\1/')
  domain=''
  for domain in $domains; do
    if _contains "$fqdn" "$domain\$"; then
      break
    fi
    domain=''
  done
  if [ -z "$domain" ]; then
    return 1
  fi

  TLD="$domain"
  _debug domain "$domain"
  RECORD=$(echo "$fqdn" | cut -c"1-$((${#fqdn} - ${#TLD} - 1))")
  PAKETNR=$(echo "$form" | grep "data-textfilter=\".* $domain " | _head_n 1 | sed 's/^.* \([0-9]*\) .*$/\1/')
  return 0
}

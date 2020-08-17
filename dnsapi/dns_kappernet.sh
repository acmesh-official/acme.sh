#!/usr/bin/env sh

# kapper.net domain api
# for further questions please contact: support@kapper.net
# please report issues here: https://github.com/acmesh-official/acme.sh/issues/2977

#KAPPERNETDNS_Key="yourKAPPERNETapikey"
#KAPPERNETDNS_Secret="yourKAPPERNETapisecret"

KAPPERNETDNS_Api="https://dnspanel.kapper.net/API/1.2?APIKey=$KAPPERNETDNS_Key&APISecret=$KAPPERNETDNS_Secret"

###############################################################################
# called with
# fullhostname: something.example.com
# txtvalue:     someacmegenerated string
dns_kappernet_add() {
  fullhostname=$1
  txtvalue=$2

  KAPPERNETDNS_Key="${KAPPERNETDNS_Key:-$(_readaccountconf_mutable KAPPERNETDNS_Key)}"
  KAPPERNETDNS_Secret="${KAPPERNETDNS_Secret:-$(_readaccountconf_mutable KAPPERNETDNS_Secret)}"

  if [ -z "$KAPPERNETDNS_Key" ] || [ -z "$KAPPERNETDNS_Secret" ]; then
    KAPPERNETDNS_Key=""
    KAPPERNETDNS_Secret=""
    _err "Please specify your kapper.net api key and secret."
    _err "If you have not received yours - send your mail to"
    _err "support@kapper.net to get  your key and secret."
    return 1
  fi

  #store the api key and email to the account conf file.
  _saveaccountconf_mutable KAPPERNETDNS_Key "$KAPPERNETDNS_Key"
  _saveaccountconf_mutable KAPPERNETDNS_Secret "$KAPPERNETDNS_Secret"
  _debug "Checking Domain ..."
  if ! _get_root "$fullhostname"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "SUBDOMAIN: $_sub_domain"
  _debug _domain "DOMAIN: $_domain"

  _info "Trying to add TXT DNS Record"
  data="%7B%22name%22%3A%22$fullhostname%22%2C%22type%22%3A%22TXT%22%2C%22content%22%3A%22$txtvalue%22%2C%22ttl%22%3A%223600%22%2C%22prio%22%3A%22%22%7D"
  if _kappernet_api GET "action=new&subject=$_domain&data=$data"; then

    if _contains "$response" "{\"OK\":true"; then
      _info "Waiting 120 seconds for DNS to spread the new record"
      _sleep 120
      return 0
    else
      _err "Error creating a TXT DNS Record: $fullhostname TXT $txtvalue"
      _err "Error Message: $response"
      return 1
    fi
  fi
  _err "Failed creating TXT Record"
}

###############################################################################
# called with
# fullhostname: something.example.com
dns_kappernet_rm() {
  fullhostname=$1
  txtvalue=$2

  KAPPERNETDNS_Key="${KAPPERNETDNS_Key:-$(_readaccountconf_mutable KAPPERNETDNS_Key)}"
  KAPPERNETDNS_Secret="${KAPPERNETDNS_Secret:-$(_readaccountconf_mutable KAPPERNETDNS_Secret)}"

  if [ -z "$KAPPERNETDNS_Key" ] || [ -z "$KAPPERNETDNS_Secret" ]; then
    KAPPERNETDNS_Key=""
    KAPPERNETDNS_Secret=""
    _err "Please specify your kapper.net api key and secret."
    _err "If you have not received yours - send your mail to"
    _err "support@kapper.net to get  your key and secret."
    return 1
  fi

  #store the api key and email to the account conf file.
  _saveaccountconf_mutable KAPPERNETDNS_Key "$KAPPERNETDNS_Key"
  _saveaccountconf_mutable KAPPERNETDNS_Secret "$KAPPERNETDNS_Secret"

  _info "Trying to remove the TXT Record: $fullhostname containing $txtvalue"
  data="%7B%22name%22%3A%22$fullhostname%22%2C%22type%22%3A%22TXT%22%2C%22content%22%3A%22$txtvalue%22%2C%22ttl%22%3A%223600%22%2C%22prio%22%3A%22%22%7D"
  if _kappernet_api GET "action=del&subject=$fullhostname&data=$data"; then
    if _contains "$response" "{\"OK\":true"; then
      return 0
    else
      _err "Error deleting DNS Record: $fullhostname containing $txtvalue"
      _err "Problem: $response"
      return 1
    fi
  fi
  _err "Problem deleting TXT DNS record"
}

####################  Private functions below ##################################
# called with hostname
# e.g._acme-challenge.www.domain.com returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1
  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi
    if ! _kappernet_api GET "action=list&subject=$h"; then
      return 1
    fi
    if _contains "$response" '"OK":false'; then
      _debug "$h not found"
    else
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain="$h"
      return 0
    fi
    p="$i"
    i=$(_math "$i" + 1)
  done
  return 1
}

################################################################################
# calls the kapper.net DNS Panel API
# with
# method
# param
_kappernet_api() {
  method=$1
  param="$2"

  _debug param "PARAMETER=$param"
  url="$KAPPERNETDNS_Api&$param"
  _debug url "URL=$url"

  if [ "$method" = "GET" ]; then
    response="$(_get "$url")"
  else
    _err "Unsupported method"
    return 1
  fi

  _debug2 response "$response"
  return 0
}

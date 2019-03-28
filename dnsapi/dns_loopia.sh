#!/usr/bin/env sh

#
#LOOPIA_User="username"
#
#LOOPIA_Password="password"
#
#LOOPIA_Api="https://api.loopia.<TLD>/RPCSERV"

LOOPIA_Api_Default="https://api.loopia.se/RPCSERV"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_loopia_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _loopia_load_config; then
    return 1
  fi

  _loopia_save_config

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"

  _loopia_add_sub_domain "$_domain" "$_sub_domain"
  _loopia_add_record "$_domain" "$_sub_domain" "$txtvalue"

}

dns_loopia_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _loopia_load_config; then
    return 1
  fi

  _loopia_save_config

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  xml_content=$(printf '<?xml version="1.0" encoding="UTF-8"?>
  <methodCall>
    <methodName>removeSubdomain</methodName>
    <params>
      <param>
        <value><string>%s</string></value>
      </param>
      <param>
        <value><string>%s</string></value>
      </param>
      <param>
        <value><string>%s</string></value>
      </param>
      <param>
        <value><string>%s</string></value>
      </param>
    </params>
  </methodCall>' "$LOOPIA_User" "$LOOPIA_Password" "$_domain" "$_sub_domain")

  response="$(_post "$xml_content" "$LOOPIA_Api" "" "POST")"

  if ! _contains "$response" "OK"; then
    _err "Error could not get txt records"
    return 1
  fi
}

####################  Private functions below ##################################

_loopia_load_config() {
  LOOPIA_Api="${LOOPIA_Api:-$(_readaccountconf_mutable LOOPIA_Api)}"
  LOOPIA_User="${LOOPIA_User:-$(_readaccountconf_mutable LOOPIA_User)}"
  LOOPIA_Password="${LOOPIA_Password:-$(_readaccountconf_mutable LOOPIA_Password)}"

  if [ -z "$LOOPIA_Api" ]; then
    LOOPIA_Api="$LOOPIA_Api_Default"
  fi

  if [ -z "$LOOPIA_User" ] || [ -z "$LOOPIA_Password" ]; then
    LOOPIA_User=""
    LOOPIA_Password=""

    _err "A valid Loopia API user and password not provided."
    _err "Please provide a valid API user and try again."

    return 1
  fi

  return 0
}

_loopia_save_config() {
  if [ "$LOOPIA_Api" != "$LOOPIA_Api_Default" ]; then
    _saveaccountconf_mutable LOOPIA_Api "$LOOPIA_Api"
  fi
  _saveaccountconf_mutable LOOPIA_User "$LOOPIA_User"
  _saveaccountconf_mutable LOOPIA_Password "$LOOPIA_Password"
}

_loopia_get_records() {
  domain=$1
  sub_domain=$2

  xml_content=$(printf '<?xml version="1.0" encoding="UTF-8"?>
  <methodCall>
    <methodName>getZoneRecords</methodName>
    <params>
      <param>
        <value><string>%s</string></value>
      </param>
      <param>
        <value><string>%s</string></value>
      </param>
      <param>
        <value><string>%s</string></value>
      </param>
      <param>
        <value><string>%s</string></value>
      </param>
    </params>
  </methodCall>' $LOOPIA_User $LOOPIA_Password "$domain" "$sub_domain")

  response="$(_post "$xml_content" "$LOOPIA_Api" "" "POST")"
  if ! _contains "$response" "<array>"; then
    _err "Error"
    return 1
  fi
  return 0
}

_get_root() {
  domain=$1
  _debug "get root"

  domain=$1
  i=2
  p=1

  xml_content=$(printf '<?xml version="1.0" encoding="UTF-8"?>
  <methodCall>
  <methodName>getDomains</methodName>
  <params>
   <param>
    <value><string>%s</string></value>
   </param>
   <param>
    <value><string>%s</string></value>
   </param>
  </params>
  </methodCall>' $LOOPIA_User $LOOPIA_Password)

  response="$(_post "$xml_content" "$LOOPIA_Api" "" "POST")"
  while true; do
    h=$(echo "$domain" | cut -d . -f $i-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if _contains "$response" "$h"; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain="$h"
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1

}

_loopia_add_record() {
  domain=$1
  sub_domain=$2
  txtval=$3

  xml_content=$(printf '<?xml version="1.0" encoding="UTF-8"?>
  <methodCall>
    <methodName>addZoneRecord</methodName>
    <params>
      <param>
        <value><string>%s</string></value>
      </param>
      <param>
        <value><string>%s</string></value>
      </param>
      <param>
        <value><string>%s</string></value>
      </param>
      <param>
        <value><string>%s</string></value>
      </param>
      <param>
        <struct>
          <member>
            <name>type</name>
            <value><string>TXT</string></value>
          </member>
          <member>
            <name>priority</name>
            <value><int>0</int></value>
          </member>
          <member>
            <name>ttl</name>
            <value><int>60</int></value>
          </member>
          <member>
            <name>rdata</name>
            <value><string>%s</string></value>
          </member>
        </struct>
      </param>
    </params>
  </methodCall>' $LOOPIA_User $LOOPIA_Password "$domain" "$sub_domain" "$txtval")

  response="$(_post "$xml_content" "$LOOPIA_Api" "" "POST")"

  if ! _contains "$response" "OK"; then
    _err "Error"
    return 1
  fi
  return 0
}

_sub_domain_exists() {
  domain=$1
  sub_domain=$2

  xml_content=$(printf '<?xml version="1.0" encoding="UTF-8"?>
  <methodCall>
    <methodName>getSubdomains</methodName>
    <params>
      <param>
        <value><string>%s</string></value>
      </param>
      <param>
        <value><string>%s</string></value>
      </param>
      <param>
        <value><string>%s</string></value>
      </param>
    </params>
  </methodCall>' $LOOPIA_User $LOOPIA_Password "$domain")

  response="$(_post "$xml_content" "$LOOPIA_Api" "" "POST")"

  if _contains "$response" "$sub_domain"; then
    return 0
  fi
  return 1
}

_loopia_add_sub_domain() {
  domain=$1
  sub_domain=$2

  if _sub_domain_exists "$domain" "$sub_domain"; then
    return 0
  fi

  xml_content=$(printf '<?xml version="1.0" encoding="UTF-8"?>
  <methodCall>
    <methodName>addSubdomain</methodName>
    <params>
      <param>
        <value><string>%s</string></value>
      </param>
      <param>
        <value><string>%s</string></value>
      </param>
      <param>
        <value><string>%s</string></value>
      </param>
      <param>
        <value><string>%s</string></value>
      </param>
    </params>
  </methodCall>' $LOOPIA_User $LOOPIA_Password "$domain" "$sub_domain")

  response="$(_post "$xml_content" "$LOOPIA_Api" "" "POST")"

  if ! _contains "$response" "OK"; then
    _err "Error"
    return 1
  fi
  return 0
}

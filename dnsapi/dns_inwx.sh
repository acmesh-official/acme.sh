#!/usr/bin/env sh

#
#INWX_User="username"
#
#INWX_Password="password"
#
# Dependencies:
# -------------
# - oathtool (When using 2 Factor Authentication)

INWX_Api="https://api.domrobot.com/xmlrpc/"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_inwx_add() {
  fulldomain=$1
  txtvalue=$2

  INWX_User="${INWX_User:-$(_readaccountconf_mutable INWX_User)}"
  INWX_Password="${INWX_Password:-$(_readaccountconf_mutable INWX_Password)}"
  INWX_Shared_Secret="${INWX_Shared_Secret:-$(_readaccountconf_mutable INWX_Shared_Secret)}"
  if [ -z "$INWX_User" ] || [ -z "$INWX_Password" ]; then
    INWX_User=""
    INWX_Password=""
    _err "You don't specify inwx user and password yet."
    _err "Please create you key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable INWX_User "$INWX_User"
  _saveaccountconf_mutable INWX_Password "$INWX_Password"
  _saveaccountconf_mutable INWX_Shared_Secret "$INWX_Shared_Secret"

  if ! _inwx_login; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"
  _inwx_add_record "$_domain" "$_sub_domain" "$txtvalue"

}

#fulldomain txtvalue
dns_inwx_rm() {

  fulldomain=$1
  txtvalue=$2

  INWX_User="${INWX_User:-$(_readaccountconf_mutable INWX_User)}"
  INWX_Password="${INWX_Password:-$(_readaccountconf_mutable INWX_Password)}"
  INWX_Shared_Secret="${INWX_Shared_Secret:-$(_readaccountconf_mutable INWX_Shared_Secret)}"
  if [ -z "$INWX_User" ] || [ -z "$INWX_Password" ]; then
    INWX_User=""
    INWX_Password=""
    _err "You don't specify inwx user and password yet."
    _err "Please create you key and try again."
    return 1
  fi

  if ! _inwx_login; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"

  xml_content=$(printf '<?xml version="1.0" encoding="UTF-8"?>
  <methodCall>
  <methodName>nameserver.info</methodName>
  <params>
   <param>
    <value>
     <struct>
      <member>
       <name>domain</name>
       <value>
        <string>%s</string>
       </value>
      </member>
      <member>
       <name>type</name>
       <value>
        <string>TXT</string>
       </value>
      </member>
      <member>
       <name>name</name>
       <value>
        <string>%s</string>
       </value>
      </member>
     </struct>
    </value>
   </param>
  </params>
  </methodCall>' "$_domain" "$_sub_domain")
  response="$(_post "$xml_content" "$INWX_Api" "" "POST")"

  if ! _contains "$response" "Command completed successfully"; then
    _err "Error could not get txt records"
    return 1
  fi

  if ! printf "%s" "$response" | grep "count" >/dev/null; then
    _info "Do not need to delete record"
  else
    _record_id=$(printf '%s' "$response" | _egrep_o '.*(<member><name>record){1}(.*)([0-9]+){1}' | _egrep_o '<name>id<\/name><value><int>[0-9]+' | _egrep_o '[0-9]+')
    _info "Deleting record"
    _inwx_delete_record "$_record_id"
  fi

}

####################  Private functions below ##################################

_inwx_check_cookie() {
  INWX_Cookie="${INWX_Cookie:-$(_readaccountconf_mutable INWX_Cookie)}"
  if [ -z "$INWX_Cookie" ]; then
    _debug "No cached cookie found"
    return 1
  fi
  _H1="$INWX_Cookie"
  export _H1

  xml_content=$(printf '<?xml version="1.0" encoding="UTF-8"?>
  <methodCall>
  <methodName>account.info</methodName>
  </methodCall>')

  response="$(_post "$xml_content" "$INWX_Api" "" "POST")"

  if _contains "$response" "<member><name>code</name><value><int>1000</int></value></member>"; then
    _debug "Cached cookie still valid"
    return 0
  fi

  _debug "Cached cookie no longer valid"
  _H1=""
  export _H1
  INWX_Cookie=""
  _saveaccountconf_mutable INWX_Cookie "$INWX_Cookie"
  return 1
}

_inwx_login() {

  if _inwx_check_cookie; then
    _debug "Already logged in"
    return 0
  fi

  xml_content=$(printf '<?xml version="1.0" encoding="UTF-8"?>
  <methodCall>
  <methodName>account.login</methodName>
  <params>
   <param>
    <value>
     <struct>
      <member>
       <name>user</name>
       <value>
        <string>%s</string>
       </value>
      </member>
      <member>
       <name>pass</name>
       <value>
        <string>%s</string>
       </value>
      </member>
     </struct>
    </value>
   </param>
  </params>
  </methodCall>' "$INWX_User" "$INWX_Password")

  response="$(_post "$xml_content" "$INWX_Api" "" "POST")"

  INWX_Cookie=$(printf "Cookie: %s" "$(grep "domrobot=" "$HTTP_HEADER" | grep "^Set-Cookie:" | _tail_n 1 | _egrep_o 'domrobot=[^;]*;' | tr -d ';')")
  _H1=$INWX_Cookie
  export _H1
  export INWX_Cookie
  _saveaccountconf_mutable INWX_Cookie "$INWX_Cookie"

  if ! _contains "$response" "<member><name>code</name><value><int>1000</int></value></member>"; then
    _err "INWX API: Authentication error (username/password correct?)"
    return 1
  fi

  #https://github.com/inwx/php-client/blob/master/INWX/Domrobot.php#L71
  if _contains "$response" "<member><name>tfa</name><value><string>GOOGLE-AUTH</string></value></member>"; then
    if [ -z "$INWX_Shared_Secret" ]; then
      _err "INWX API: Mobile TAN detected."
      _err "Please define a shared secret."
      return 1
    fi

    if ! _exists oathtool; then
      _err "Please install oathtool to use 2 Factor Authentication."
      _err ""
      return 1
    fi

    tan="$(oathtool --base32 --totp "${INWX_Shared_Secret}" 2>/dev/null)"

    xml_content=$(printf '<?xml version="1.0" encoding="UTF-8"?>
    <methodCall>
    <methodName>account.unlock</methodName>
    <params>
     <param>
      <value>
       <struct>
        <member>
         <name>tan</name>
         <value>
          <string>%s</string>
         </value>
        </member>
       </struct>
      </value>
     </param>
    </params>
    </methodCall>' "$tan")

    response="$(_post "$xml_content" "$INWX_Api" "" "POST")"

    if ! _contains "$response" "<member><name>code</name><value><int>1000</int></value></member>"; then
      _err "INWX API: Mobile TAN not correct."
      return 1
    fi
  fi

}

_get_root() {
  domain=$1
  _debug "get root"

  domain=$1
  i=2
  p=1

  xml_content='<?xml version="1.0" encoding="UTF-8"?>
  <methodCall>
  <methodName>nameserver.list</methodName>
  </methodCall>'

  response="$(_post "$xml_content" "$INWX_Api" "" "POST")"
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
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

_inwx_delete_record() {
  record_id=$1
  xml_content=$(printf '<?xml version="1.0" encoding="UTF-8"?>
  <methodCall>
  <methodName>nameserver.deleteRecord</methodName>
  <params>
   <param>
    <value>
     <struct>
      <member>
       <name>id</name>
       <value>
        <int>%s</int>
       </value>
      </member>
     </struct>
    </value>
   </param>
  </params>
  </methodCall>' "$record_id")

  response="$(_post "$xml_content" "$INWX_Api" "" "POST")"

  if ! printf "%s" "$response" | grep "Command completed successfully" >/dev/null; then
    _err "Error"
    return 1
  fi
  return 0

}

_inwx_update_record() {
  record_id=$1
  txtval=$2
  xml_content=$(printf '<?xml version="1.0" encoding="UTF-8"?>
  <methodCall>
  <methodName>nameserver.updateRecord</methodName>
  <params>
   <param>
    <value>
     <struct>
      <member>
       <name>content</name>
       <value>
        <string>%s</string>
       </value>
      </member>
      <member>
       <name>id</name>
       <value>
        <int>%s</int>
       </value>
      </member>
     </struct>
    </value>
   </param>
  </params>
  </methodCall>' "$txtval" "$record_id")

  response="$(_post "$xml_content" "$INWX_Api" "" "POST")"

  if ! printf "%s" "$response" | grep "Command completed successfully" >/dev/null; then
    _err "Error"
    return 1
  fi
  return 0

}

_inwx_add_record() {

  domain=$1
  sub_domain=$2
  txtval=$3

  xml_content=$(printf '<?xml version="1.0" encoding="UTF-8"?>
  <methodCall>
  <methodName>nameserver.createRecord</methodName>
  <params>
   <param>
    <value>
     <struct>
      <member>
       <name>domain</name>
       <value>
        <string>%s</string>
       </value>
      </member>
      <member>
       <name>type</name>
       <value>
        <string>TXT</string>
       </value>
      </member>
      <member>
       <name>content</name>
       <value>
        <string>%s</string>
       </value>
      </member>
      <member>
       <name>name</name>
       <value>
        <string>%s</string>
       </value>
      </member>
     </struct>
    </value>
   </param>
  </params>
  </methodCall>' "$domain" "$txtval" "$sub_domain")

  response="$(_post "$xml_content" "$INWX_Api" "" "POST")"

  if ! printf "%s" "$response" | grep "Command completed successfully" >/dev/null; then
    _err "Error"
    return 1
  fi
  return 0
}

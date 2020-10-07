#!/usr/bin/env sh

#This is the euserv.eu api wrapper for acme.sh
#
#Author: Michael Brueckner
#Report Bugs: https://www.github.com/initit/acme.sh  or  mbr@initit.de

#
#EUSERV_Username="username"
#
#EUSERV_Password="password"
#
# Dependencies:
# -------------
# - none -

EUSERV_Api="https://api.euserv.net"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_euserv_add() {
  fulldomain="$(echo "$1" | _lower_case)"
  txtvalue=$2

  EUSERV_Username="${EUSERV_Username:-$(_readaccountconf_mutable EUSERV_Username)}"
  EUSERV_Password="${EUSERV_Password:-$(_readaccountconf_mutable EUSERV_Password)}"
  if [ -z "$EUSERV_Username" ] || [ -z "$EUSERV_Password" ]; then
    EUSERV_Username=""
    EUSERV_Password=""
    _err "You don't specify euserv user and password yet."
    _err "Please create your key and try again."
    return 1
  fi

  #save the user and email to the account conf file.
  _saveaccountconf_mutable EUSERV_Username "$EUSERV_Username"
  _saveaccountconf_mutable EUSERV_Password "$EUSERV_Password"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug "_sub_domain" "$_sub_domain"
  _debug "_domain" "$_domain"
  _info "Adding record"
  if ! _euserv_add_record "$_domain" "$_sub_domain" "$txtvalue"; then
    return 1
  fi

}

#fulldomain txtvalue
dns_euserv_rm() {

  fulldomain="$(echo "$1" | _lower_case)"
  txtvalue=$2

  EUSERV_Username="${EUSERV_Username:-$(_readaccountconf_mutable EUSERV_Username)}"
  EUSERV_Password="${EUSERV_Password:-$(_readaccountconf_mutable EUSERV_Password)}"
  if [ -z "$EUSERV_Username" ] || [ -z "$EUSERV_Password" ]; then
    EUSERV_Username=""
    EUSERV_Password=""
    _err "You don't specify euserv user and password yet."
    _err "Please create your key and try again."
    return 1
  fi

  #save the user and email to the account conf file.
  _saveaccountconf_mutable EUSERV_Username "$EUSERV_Username"
  _saveaccountconf_mutable EUSERV_Password "$EUSERV_Password"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug "_sub_domain" "$_sub_domain"
  _debug "_domain" "$_domain"

  _debug "Getting txt records"

  xml_content=$(printf '<?xml version="1.0" encoding="UTF-8"?>
  <methodCall>
    <methodName>domain.dns_get_active_records</methodName>
    <params>
      <param>
       <value>
         <struct>
           <member>
             <name>login</name>
             <value>
               <string>%s</string>
             </value>
            </member>
            <member>
              <name>password</name>
              <value>
                <string>%s</string>
              </value>
            </member>
            <member>
              <name>domain_id</name>
              <value>
                <int>%s</int>
              </value>
            </member>
          </struct>
        </value>
      </param>
    </params>
  </methodCall>' "$EUSERV_Username" "$EUSERV_Password" "$_euserv_domain_id")

  export _H1="Content-Type: text/xml"
  response="$(_post "$xml_content" "$EUSERV_Api" "" "POST")"

  if ! _contains "$response" "<member><name>status</name><value><i4>100</i4></value></member>"; then
    _err "Error could not get txt records"
    _debug "xml_content" "$xml_content"
    _debug "response" "$response"
    return 1
  fi

  if ! echo "$response" | grep '>dns_record_content<.*>'"$txtvalue"'<' >/dev/null; then
    _info "Do not need to delete record"
  else
    # find XML block where txtvalue is in. The record_id is allways prior this line!
    _endLine=$(echo "$response" | grep -n '>dns_record_content<.*>'"$txtvalue"'<' | cut -d ':' -f 1)
    # record_id is the last <name> Tag with a number before the row _endLine, identified by </name><value><struct>
    _record_id=$(echo "$response" | sed -n '1,'"$_endLine"'p' | grep '</name><value><struct>' | _tail_n 1 | sed 's/.*<name>\([0-9]*\)<\/name>.*/\1/')
    _info "Deleting record"
    _euserv_delete_record "$_record_id"
  fi

}

####################  Private functions below ##################################

_get_root() {
  domain=$1
  _debug "get root"

  # Just to read the domain_orders once

  domain=$1
  i=2
  p=1

  if ! _euserv_get_domain_orders; then
    return 1
  fi

  # Get saved response with domain_orders
  response="$_euserv_domain_orders"

  while true; do
    h=$(echo "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if _contains "$response" "$h"; then
      _sub_domain=$(echo "$domain" | cut -d . -f 1-$p)
      _domain="$h"
      if ! _euserv_get_domain_id "$_domain"; then
        _err "invalid domain"
        return 1
      fi
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done

  return 1
}

_euserv_get_domain_orders() {
  # returns: _euserv_domain_orders

  _debug "get domain_orders"

  xml_content=$(printf '<?xml version="1.0" encoding="UTF-8"?>
  <methodCall>
    <methodName>domain.get_domain_orders</methodName>
    <params>
      <param>
        <value>
          <struct>
            <member>
              <name>login</name>
              <value><string>%s</string></value>
            </member>
            <member>
              <name>password</name>
              <value><string>%s</string></value>
            </member>
          </struct>
        </value>
      </param>
    </params>
  </methodCall>' "$EUSERV_Username" "$EUSERV_Password")

  export _H1="Content-Type: text/xml"
  response="$(_post "$xml_content" "$EUSERV_Api" "" "POST")"

  if ! _contains "$response" "<member><name>status</name><value><i4>100</i4></value></member>"; then
    _err "Error could not get domain orders"
    _debug "xml_content" "$xml_content"
    _debug "response" "$response"
    return 1
  fi

  # save response to reduce API calls
  _euserv_domain_orders="$response"
  return 0
}

_euserv_get_domain_id() {
  # returns: _euserv_domain_id
  domain=$1
  _debug "get domain_id"

  # find line where the domain name is within the $response
  _startLine=$(echo "$_euserv_domain_orders" | grep -n '>domain_name<.*>'"$domain"'<' | cut -d ':' -f 1)
  # next occurency of domain_id after the domain_name is the correct one
  _euserv_domain_id=$(echo "$_euserv_domain_orders" | sed -n "$_startLine"',$p' | grep '>domain_id<' | _head_n 1 | sed 's/.*<i4>\([0-9]*\)<\/i4>.*/\1/')

  if [ -z "$_euserv_domain_id" ]; then
    _err "Could not find domain_id for domain $domain"
    _debug "_euserv_domain_orders" "$_euserv_domain_orders"
    return 1
  fi

  return 0
}

_euserv_delete_record() {
  record_id=$1
  xml_content=$(printf '<?xml version="1.0" encoding="UTF-8"?>
  <methodCall>
    <methodName>domain.dns_delete_record</methodName>
    <params>
      <param>
       <value>
         <struct>
           <member>
             <name>login</name>
             <value>
               <string>%s</string>
             </value>
            </member>
            <member>
              <name>password</name>
              <value>
                <string>%s</string>
              </value>
            </member>
            <member>
              <name>dns_record_id</name>
              <value>
                <int>%s</int>
              </value>
            </member>
          </struct>
        </value>
      </param>
    </params>
  </methodCall>' "$EUSERV_Username" "$EUSERV_Password" "$record_id")

  export _H1="Content-Type: text/xml"
  response="$(_post "$xml_content" "$EUSERV_Api" "" "POST")"

  if ! _contains "$response" "<member><name>status</name><value><i4>100</i4></value></member>"; then
    _err "Error deleting record"
    _debug "xml_content" "$xml_content"
    _debug "response" "$response"
    return 1
  fi

  return 0

}

_euserv_add_record() {
  domain=$1
  sub_domain=$2
  txtval=$3

  xml_content=$(printf '<?xml version="1.0" encoding="UTF-8"?>
  <methodCall>
  <methodName>domain.dns_create_record</methodName>
  <params>
   <param>
    <value>
     <struct>
      <member>
       <name>login</name>
       <value>
        <string>%s</string>
       </value>
      </member>
      <member>
       <name>password</name>
       <value>
        <string>%s</string></value>
      </member>
      <member>
       <name>domain_id</name>
       <value>
        <int>%s</int>
       </value>
      </member>
      <member>
       <name>dns_record_subdomain</name>
       <value>
        <string>%s</string>
       </value>
      </member>
      <member>
       <name>dns_record_type</name>
       <value>
        <string>TXT</string>
       </value>
      </member>
      <member>
       <name>dns_record_value</name>
       <value>
        <string>%s</string>
       </value>
      </member>
      <member>
       <name>dns_record_ttl</name>
       <value>
        <int>300</int>
       </value>
      </member>
     </struct>
    </value>
   </param>
  </params>
  </methodCall>' "$EUSERV_Username" "$EUSERV_Password" "$_euserv_domain_id" "$sub_domain" "$txtval")

  export _H1="Content-Type: text/xml"
  response="$(_post "$xml_content" "$EUSERV_Api" "" "POST")"

  if ! _contains "$response" "<member><name>status</name><value><i4>100</i4></value></member>"; then
    _err "Error could not create record"
    _debug "xml_content" "$xml_content"
    _debug "response" "$response"
    return 1
  fi

  return 0
}

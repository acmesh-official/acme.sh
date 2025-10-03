#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_selectel_info='Selectel.com
Domains: Selectel.ru
Site: Selectel.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_selectel
Options: For old API version v1 (deprecated)
   SL_Ver API version. Use "v1".
   SL_Key API Key
OptionsAlt: For the current API version v2
   SL_Ver API version. Use "v2".
   SL_Login_ID Account ID
   SL_Project_Name Project name
   SL_Login_Name Service user name
   SL_Pswd Service user password
   SL_Expire Token lifetime. In minutes (0-1440). Default "1400"
Issues: github.com/acmesh-official/acme.sh/issues/5126
'

SL_Api="https://api.selectel.ru/domains"
auth_uri="https://cloud.api.selcloud.ru/identity/v3/auth/tokens"
_sl_sep='#'

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_selectel_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _sl_init_vars; then
    return 1
  fi
  _debug2 SL_Ver "$SL_Ver"
  _debug2 SL_Expire "$SL_Expire"
  _debug2 SL_Login_Name "$SL_Login_Name"
  _debug2 SL_Login_ID "$SL_Login_ID"
  _debug2 SL_Project_Name "$SL_Project_Name"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"
  if [ "$SL_Ver" = "v2" ]; then
    _ext_srv1="/zones/"
    _ext_srv2="/rrset/"
    _text_tmp=$(echo "$txtvalue" | sed -En "s/[\"]*([^\"]*)/\1/p")
    _text_tmp='\"'$_text_tmp'\"'
    _data="{\"type\": \"TXT\", \"ttl\": 60, \"name\": \"${fulldomain}.\", \"records\": [{\"content\":\"$_text_tmp\"}]}"
  elif [ "$SL_Ver" = "v1" ]; then
    _ext_srv1="/"
    _ext_srv2="/records/"
    _data="{\"type\":\"TXT\",\"ttl\":60,\"name\":\"$fulldomain\",\"content\":\"$txtvalue\"}"
  else
    _err "Error. Unsupported version API $SL_Ver"
    return 1
  fi
  _ext_uri="${_ext_srv1}$_domain_id${_ext_srv2}"
  _debug _ext_uri "$_ext_uri"
  _debug _data "$_data"

  if _sl_rest POST "$_ext_uri" "$_data"; then
    if _contains "$response" "$txtvalue"; then
      _info "Added, OK"
      return 0
    fi
    if _contains "$response" "already_exists"; then
      # record TXT with $fulldomain already exists
      if [ "$SL_Ver" = "v2" ]; then
        # It is necessary to add one more content to the comments
        # read all records rrset
        _debug "Getting txt records"
        _sl_rest GET "${_ext_uri}"
        # There is already a $txtvalue value, no need to add it
        if _contains "$response" "$txtvalue"; then
          _info "Added, OK"
          _info "Txt record ${fulldomain} with value ${txtvalue} already exists"
          return 0
        fi
        # group \1 - full record rrset; group \2 - records attribute value, exactly {"content":"\"value1\""},{"content":"\"value2\""}",...
        _record_seg="$(echo "$response" | sed -En "s/.*(\{\"id\"[^}]*${fulldomain}[^}]*records[^}]*\[(\{[^]]*\})\][^}]*}).*/\1/p")"
        _record_array="$(echo "$response" | sed -En "s/.*(\{\"id\"[^}]*${fulldomain}[^}]*records[^}]*\[(\{[^]]*\})\][^}]*}).*/\2/p")"
        # record id
        _record_id="$(echo "$_record_seg" | tr "," "\n" | tr "}" "\n" | tr -d " " | grep "\"id\"" | cut -d : -f 2 | tr -d "\"")"
        # preparing _data
        _tmp_str="${_record_array},{\"content\":\"${_text_tmp}\"}"
        _data="{\"ttl\": 60, \"records\": [${_tmp_str}]}"
        _debug2 _record_seg "$_record_seg"
        _debug2 _record_array "$_record_array"
        _debug2 _record_array "$_record_id"
        _debug "New data for record" "$_data"
        if _sl_rest PATCH "${_ext_uri}${_record_id}" "$_data"; then
          _info "Added, OK"
          return 0
        fi
      elif [ "$SL_Ver" = "v1" ]; then
        _info "Added, OK"
        return 0
      fi
    fi
  fi
  _err "Add txt record error."
  return 1
}

#fulldomain txtvalue
dns_selectel_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _sl_init_vars "nosave"; then
    return 1
  fi
  _debug2 SL_Ver "$SL_Ver"
  _debug2 SL_Expire "$SL_Expire"
  _debug2 SL_Login_Name "$SL_Login_Name"
  _debug2 SL_Login_ID "$SL_Login_ID"
  _debug2 SL_Project_Name "$SL_Project_Name"
  #
  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  #
  if [ "$SL_Ver" = "v2" ]; then
    _ext_srv1="/zones/"
    _ext_srv2="/rrset/"
  elif [ "$SL_Ver" = "v1" ]; then
    _ext_srv1="/"
    _ext_srv2="/records/"
  else
    _err "Error. Unsupported version API $SL_Ver"
    return 1
  fi
  #
  _debug "Getting txt records"
  _ext_uri="${_ext_srv1}$_domain_id${_ext_srv2}"
  _debug _ext_uri "$_ext_uri"
  _sl_rest GET "${_ext_uri}"
  #
  if ! _contains "$response" "$txtvalue"; then
    _err "Txt record not found"
    return 1
  fi
  #
  if [ "$SL_Ver" = "v2" ]; then
    _record_seg="$(echo "$response" | sed -En "s/.*(\{\"id\"[^}]*records[^[]*(\[(\{[^]]*${txtvalue}[^]]*)\])[^}]*}).*/\1/gp")"
    _record_arr="$(echo "$response" | sed -En "s/.*(\{\"id\"[^}]*records[^[]*(\[(\{[^]]*${txtvalue}[^]]*)\])[^}]*}).*/\3/p")"
  elif [ "$SL_Ver" = "v1" ]; then
    _record_seg="$(echo "$response" | _egrep_o "[^{]*\"content\" *: *\"$txtvalue\"[^}]*}")"
  else
    _err "Error. Unsupported version API $SL_Ver"
    return 1
  fi
  _debug2 "_record_seg" "$_record_seg"
  if [ -z "$_record_seg" ]; then
    _err "can not find _record_seg"
    return 1
  fi
  # record id
  # the following lines change the algorithm for deleting records with the value $txtvalue
  # if you use the 1st line, then all such records are deleted at once
  # if you use the 2nd line, then only the first entry from them is deleted
  #_record_id="$(echo "$_record_seg" | tr "," "\n" | tr "}" "\n" | tr -d " " | grep "\"id\"" | cut -d : -f 2 | tr -d "\"")"
  _record_id="$(echo "$_record_seg" | tr "," "\n" | tr "}" "\n" | tr -d " " | grep "\"id\"" | cut -d : -f 2 | tr -d "\"" | sed '1!d')"
  if [ -z "$_record_id" ]; then
    _err "can not find _record_id"
    return 1
  fi
  _debug2 "_record_id" "$_record_id"
  # delete all record type TXT with text $txtvalue
  if [ "$SL_Ver" = "v2" ]; then
    # actual
    _new_arr="$(echo "$_record_seg" | sed -En "s/.*(\{\"id\"[^}]*records[^[]*(\[(\{[^]]*${txtvalue}[^]]*)\])[^}]*}).*/\3/gp" | sed -En "s/(\},\{)/}\n{/gp" | sed "/${txtvalue}/d" | sed ":a;N;s/\n/,/;ta")"
    # uri record for DEL or PATCH
    _del_uri="${_ext_uri}${_record_id}"
    _debug _del_uri "$_del_uri"
    if [ -z "$_new_arr" ]; then
      # remove record
      if ! _sl_rest DELETE "${_del_uri}"; then
        _err "Delete record error: ${_del_uri}."
      else
        info "Delete record success: ${_del_uri}."
      fi
    else
      # update a record by removing one element in content
      _data="{\"ttl\": 60, \"records\": [${_new_arr}]}"
      _debug2 _data "$_data"
      # REST API PATCH call
      if _sl_rest PATCH "${_del_uri}" "$_data"; then
        _info "Patched, OK: ${_del_uri}"
      else
        _err "Patched record error: ${_del_uri}."
      fi
    fi
  else
    # legacy
    for _one_id in $_record_id; do
      _del_uri="${_ext_uri}${_one_id}"
      _debug _del_uri "$_del_uri"
      if ! _sl_rest DELETE "${_del_uri}"; then
        _err "Delete record error: ${_del_uri}."
      else
        info "Delete record success: ${_del_uri}."
      fi
    done
  fi
  return 0
}

####################  Private functions below ##################################

_get_root() {
  domain=$1

  if [ "$SL_Ver" = 'v1' ]; then
    # version API 1
    if ! _sl_rest GET "/"; then
      return 1
    fi
    i=2
    p=1
    while true; do
      h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
      _debug h "$h"
      if [ -z "$h" ]; then
        return 1
      fi
      if _contains "$response" "\"name\" *: *\"$h\","; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
        _domain=$h
        _debug "Getting domain id for $h"
        if ! _sl_rest GET "/$h"; then
          _err "Error read records of all domains $SL_Ver"
          return 1
        fi
        _domain_id="$(echo "$response" | tr "," "\n" | tr "}" "\n" | tr -d " " | grep "\"id\":" | cut -d : -f 2)"
        return 0
      fi
      p=$i
      i=$(_math "$i" + 1)
    done
    _err "Error read records of all domains $SL_Ver"
    return 1
  elif [ "$SL_Ver" = "v2" ]; then
    # version API 2
    _ext_uri='/zones/'
    domain="${domain}."
    _debug "domain:: " "$domain"
    # read records of all domains
    if ! _sl_rest GET "$_ext_uri"; then
      _err "Error read records of all domains $SL_Ver"
      return 1
    fi
    i=1
    p=1
    while true; do
      h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
      _debug h "$h"
      if [ -z "$h" ]; then
        _err "The domain was not found among the registered ones"
        return 1
      fi
      _domain_record=$(echo "$response" | sed -En "s/.*(\{[^}]*id[^}]*\"name\" *: *\"$h\"[^}]*}).*/\1/p")
      _debug "_domain_record:: " "$_domain_record"
      if [ -n "$_domain_record" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
        _domain=$h
        _debug "Getting domain id for $h"
        _domain_id=$(echo "$_domain_record" | sed -En "s/\{[^}]*\"id\" *: *\"([^\"]*)\"[^}]*\}/\1/p")
        return 0
      fi
      p=$i
      i=$(_math "$i" + 1)
    done
    _err "Error read records of all domains $SL_Ver"
    return 1
  else
    _err "Error. Unsupported version API $SL_Ver"
    return 1
  fi
}

#################################################################
# use: method add_url body
_sl_rest() {
  m=$1
  ep="$2"
  data="$3"

  _token=$(_get_auth_token)
  if [ -z "$_token" ]; then
    _err "BAD key or token $ep"
    return 1
  fi
  if [ "$SL_Ver" = v2 ]; then
    _h1_name="X-Auth-Token"
  else
    _h1_name='X-Token'
  fi
  export _H1="${_h1_name}: ${_token}"
  export _H2="Content-Type: application/json"
  _debug2 "Full URI: " "$SL_Api/${SL_Ver}${ep}"
  _debug2 "_H1:" "$_H1"
  _debug2 "_H2:" "$_H2"
  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$SL_Api/${SL_Ver}${ep}" "" "$m")"
  else
    response="$(_get "$SL_Api/${SL_Ver}${ep}")"
  fi
  # shellcheck disable=SC2181
  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

_get_auth_token() {
  if [ "$SL_Ver" = 'v1' ]; then
    # token for v1
    _debug "Token v1"
    _token_keystone=$SL_Key
  elif [ "$SL_Ver" = 'v2' ]; then
    # token for v2. Get a token for calling the API
    _debug "Keystone Token v2"
    token_v2=$(_readaccountconf_mutable SL_Token_V2)
    if [ -n "$token_v2" ]; then
      # The structure with the token was considered. Let's check its validity
      # field 1 - SL_Login_Name
      # field 2 - token keystone
      # field 3 - SL_Login_ID
      # field 4 - SL_Project_Name
      # field 5 - Receipt time
      # separator - '$_sl_sep'
      _login_name=$(_getfield "$token_v2" 1 "$_sl_sep")
      _token_keystone=$(_getfield "$token_v2" 2 "$_sl_sep")
      _project_name=$(_getfield "$token_v2" 4 "$_sl_sep")
      _receipt_time=$(_getfield "$token_v2" 5 "$_sl_sep")
      _login_id=$(_getfield "$token_v2" 3 "$_sl_sep")
      _debug2 _login_name "$_login_name"
      _debug2 _login_id "$_login_id"
      _debug2 _project_name "$_project_name"
      # check the validity of the token for the user and the project and its lifetime
      _dt_diff_minute=$((($(date +%s) - _receipt_time) / 60))
      _debug2 _dt_diff_minute "$_dt_diff_minute"
      [ "$_dt_diff_minute" -gt "$SL_Expire" ] && unset _token_keystone
      if [ "$_project_name" != "$SL_Project_Name" ] || [ "$_login_name" != "$SL_Login_Name" ] || [ "$_login_id" != "$SL_Login_ID" ]; then
        unset _token_keystone
      fi
      _debug "Get exists token"
    fi
    if [ -z "$_token_keystone" ]; then
      # the previous token is incorrect or was not received, get a new one
      _debug "Update (get new) token"
      _data_auth="{\"auth\":{\"identity\":{\"methods\":[\"password\"],\"password\":{\"user\":{\"name\":\"${SL_Login_Name}\",\"domain\":{\"name\":\"${SL_Login_ID}\"},\"password\":\"${SL_Pswd}\"}}},\"scope\":{\"project\":{\"name\":\"${SL_Project_Name}\",\"domain\":{\"name\":\"${SL_Login_ID}\"}}}}}"
      export _H1="Content-Type: application/json"
      _result=$(_post "$_data_auth" "$auth_uri")
      _token_keystone=$(grep 'x-subject-token' "$HTTP_HEADER" | sed -nE "s/[[:space:]]*x-subject-token:[[:space:]]*([[:print:]]*)(\r*)/\1/p")
      _dt_curr=$(date +%s)
      SL_Token_V2="${SL_Login_Name}${_sl_sep}${_token_keystone}${_sl_sep}${SL_Login_ID}${_sl_sep}${SL_Project_Name}${_sl_sep}${_dt_curr}"
      _saveaccountconf_mutable SL_Token_V2 "$SL_Token_V2"
    fi
  else
    # token set empty for unsupported version API
    _token_keystone=""
  fi
  printf -- "%s" "$_token_keystone"
}

#################################################################
# use: [non_save]
_sl_init_vars() {
  _non_save="${1}"
  _debug2 _non_save "$_non_save"

  _debug "First init variables"
  # version API
  SL_Ver="${SL_Ver:-$(_readaccountconf_mutable SL_Ver)}"
  if [ -z "$SL_Ver" ]; then
    SL_Ver="v1"
  fi
  if ! [ "$SL_Ver" = "v1" ] && ! [ "$SL_Ver" = "v2" ]; then
    _err "You don't specify selectel.ru API version."
    _err "Please define specify API version."
  fi
  _debug2 SL_Ver "$SL_Ver"
  if [ "$SL_Ver" = "v1" ]; then
    # token
    SL_Key="${SL_Key:-$(_readaccountconf_mutable SL_Key)}"

    if [ -z "$SL_Key" ]; then
      SL_Key=""
      _err "You don't specify selectel.ru api key yet."
      _err "Please create you key and try again."
      return 1
    fi
    #save the api key to the account conf file.
    if [ -z "$_non_save" ]; then
      _saveaccountconf_mutable SL_Key "$SL_Key"
    fi
  elif [ "$SL_Ver" = "v2" ]; then
    # time expire token
    SL_Expire="${SL_Expire:-$(_readaccountconf_mutable SL_Expire)}"
    if [ -z "$SL_Expire" ]; then
      SL_Expire=1400 # 23h 20 min
    fi
    if [ -z "$_non_save" ]; then
      _saveaccountconf_mutable SL_Expire "$SL_Expire"
    fi
    # login service user
    SL_Login_Name="${SL_Login_Name:-$(_readaccountconf_mutable SL_Login_Name)}"
    if [ -z "$SL_Login_Name" ]; then
      SL_Login_Name=''
      _err "You did not specify the selectel.ru API service user name."
      _err "Please provide a service user name and try again."
      return 1
    fi
    if [ -z "$_non_save" ]; then
      _saveaccountconf_mutable SL_Login_Name "$SL_Login_Name"
    fi
    # user ID
    SL_Login_ID="${SL_Login_ID:-$(_readaccountconf_mutable SL_Login_ID)}"
    if [ -z "$SL_Login_ID" ]; then
      SL_Login_ID=''
      _err "You did not specify the selectel.ru API user ID."
      _err "Please provide a user ID and try again."
      return 1
    fi
    if [ -z "$_non_save" ]; then
      _saveaccountconf_mutable SL_Login_ID "$SL_Login_ID"
    fi
    # project name
    SL_Project_Name="${SL_Project_Name:-$(_readaccountconf_mutable SL_Project_Name)}"
    if [ -z "$SL_Project_Name" ]; then
      SL_Project_Name=''
      _err "You did not specify the project name."
      _err "Please provide a project name and try again."
      return 1
    fi
    if [ -z "$_non_save" ]; then
      _saveaccountconf_mutable SL_Project_Name "$SL_Project_Name"
    fi
    # service user password
    SL_Pswd="${SL_Pswd:-$(_readaccountconf_mutable SL_Pswd)}"
    if [ -z "$SL_Pswd" ]; then
      SL_Pswd=''
      _err "You did not specify the service user password."
      _err "Please provide a service user password and try again."
      return 1
    fi
    if [ -z "$_non_save" ]; then
      _saveaccountconf_mutable SL_Pswd "$SL_Pswd" "12345678"
    fi
  else
    SL_Ver=""
    _err "You also specified the wrong version of the selectel.ru API."
    _err "Please provide the correct API version and try again."
    return 1
  fi
  if [ -z "$_non_save" ]; then
    _saveaccountconf_mutable SL_Ver "$SL_Ver"
  fi

  return 0
}

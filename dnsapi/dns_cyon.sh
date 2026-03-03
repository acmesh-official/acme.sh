#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_cyon_info='cyon.ch
Site: cyon.ch
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_cyon
Options:
 CY_Username Username
 CY_Password API Token
 CY_OTP_Secret OTP token. Only required if using 2FA
Issues: github.com/noplanman/cyon-api/issues
Author: Armando Lüscher <armando@noplanman.ch>
'

dns_cyon_add() {
  _cyon_load_credentials &&
    _cyon_load_parameters "$@" &&
    _cyon_print_header "add" &&
    _cyon_login &&
    _cyon_change_domain_env &&
    _cyon_add_txt &&
    _cyon_logout
}

dns_cyon_rm() {
  _cyon_load_credentials &&
    _cyon_load_parameters "$@" &&
    _cyon_print_header "delete" &&
    _cyon_login &&
    _cyon_change_domain_env &&
    _cyon_delete_txt &&
    _cyon_logout
}

#########################
### PRIVATE FUNCTIONS ###
#########################

_cyon_load_credentials() {
  # Convert loaded password to/from base64 as needed.
  if [ "${CY_Password_B64}" ]; then
    CY_Password="$(printf "%s" "${CY_Password_B64}" | _dbase64)"
  elif [ "${CY_Password}" ]; then
    CY_Password_B64="$(printf "%s" "${CY_Password}" | _base64)"
  fi

  if [ -z "${CY_Username}" ] || [ -z "${CY_Password}" ]; then
    # Dummy entries to satisfy script checker.
    CY_Username=""
    CY_Password=""
    CY_OTP_Secret=""

    _err ""
    _err "You haven't set your cyon.ch login credentials yet."
    _err "Please set the required cyon environment variables."
    _err ""
    return 1
  fi

  # Save the login credentials to the account.conf file.
  _debug "Save credentials to account.conf"
  _saveaccountconf CY_Username "${CY_Username}"
  _saveaccountconf CY_Password_B64 "$CY_Password_B64"
  if [ -n "${CY_OTP_Secret}" ]; then
    _saveaccountconf CY_OTP_Secret "$CY_OTP_Secret"
  else
    _clearaccountconf CY_OTP_Secret
  fi
}

_cyon_is_idn() {
  _idn_temp="$(printf "%s" "${1}" | tr -d "0-9a-zA-Z.,-_")"
  _idn_temp2="$(printf "%s" "${1}" | grep -o "xn--")"
  [ "$_idn_temp" ] || [ "$_idn_temp2" ]
}

_cyon_load_parameters() {
  # Read the required parameters to add the TXT entry.
  # shellcheck disable=SC2018,SC2019
  fulldomain="$(printf "%s" "${1}" | tr "A-Z" "a-z")"
  fulldomain_idn="${fulldomain}"

  # Special case for IDNs, as cyon needs a domain environment change,
  # which uses the "pretty" instead of the punycode version.
  if _cyon_is_idn "${fulldomain}"; then
    if ! _exists idn; then
      _err "Please install idn to process IDN names."
      _err ""
      return 1
    fi

    fulldomain="$(idn -u "${fulldomain}")"
    fulldomain_idn="$(idn -a "${fulldomain}")"
  fi

  _debug fulldomain "${fulldomain}"
  _debug fulldomain_idn "${fulldomain_idn}"

  txtvalue="${2}"
  _debug txtvalue "${txtvalue}"

  # This header is required for curl calls.
  _H1="X-Requested-With: XMLHttpRequest"
  export _H1
  _H3="User-Agent: cyon-dns-acmesh/1.0"
  export _H3
}

_cyon_print_header() {
  if [ "${1}" = "add" ]; then
    _info ""
    _info "+---------------------------------------------+"
    _info "| Adding DNS TXT entry to your cyon.ch domain |"
    _info "+---------------------------------------------+"
    _info ""
    _info "  * Full Domain: ${fulldomain}"
    _info "  * TXT Value:   ${txtvalue}"
    _info ""
  elif [ "${1}" = "delete" ]; then
    _info ""
    _info "+-------------------------------------------------+"
    _info "| Deleting DNS TXT entry from your cyon.ch domain |"
    _info "+-------------------------------------------------+"
    _info ""
    _info "  * Full Domain: ${fulldomain}"
    _info ""
  fi
}

_cyon_get_cookie_header() {
  # Extract all cookies from the response headers (case-insensitive)
  _cookies="$(grep -i "^set-cookie:" "$HTTP_HEADER" | sed 's/^[Ss]et-[Cc]ookie: //' | sed 's/;.*//' | tr '\n' '; ' | sed 's/; $//')"
  if [ -n "$_cookies" ]; then
    printf "Cookie: %s" "$_cookies"
  fi
}

_cyon_login() {
  _info "  - Logging in..."

  username_encoded="$(printf "%s" "${CY_Username}" | _url_encode)"
  password_encoded="$(printf "%s" "${CY_Password}" | _url_encode)"

  login_url="https://my.cyon.ch/auth/index/dologin-async"
  login_data="$(printf "%s" "username=${username_encoded}&password=${password_encoded}&pathname=%2F")"

  login_response="$(_post "$login_data" "$login_url")"
  _debug login_response "${login_response}"

  # Bail if login fails.
  if [ "$(printf "%s" "${login_response}" | _cyon_get_response_success)" != "success" ]; then
    _err "    $(printf "%s" "${login_response}" | _cyon_get_response_message)"
    _err ""
    return 1
  fi

  _info "    success"

  # NECESSARY!! Load the main page after login, to get the new cookie.
  _H2="$(_cyon_get_cookie_header)"
  export _H2

  _get "https://my.cyon.ch/" >/dev/null

  # Update cookie after loading main page (only if new cookies are set)
  _new_cookies="$(_cyon_get_cookie_header)"
  if [ -n "$_new_cookies" ]; then
    _H2="$_new_cookies"
    export _H2
  fi

  # 2FA authentication with OTP?
  if [ -n "${CY_OTP_Secret}" ]; then
    _info "  - Authorising with OTP code..."

    if ! _exists oathtool; then
      _err "Please install oathtool to use 2 Factor Authentication."
      _err ""
      return 1
    fi

    # Get OTP code with the defined secret.
    otp_code="$(oathtool --base32 --totp "${CY_OTP_Secret}" 2>/dev/null)"

    login_otp_url="https://my.cyon.ch/auth/multi-factor/domultifactorauth-async"
    login_otp_data="totpcode=${otp_code}&pathname=%2F&rememberme=0"

    login_otp_response="$(_post "$login_otp_data" "$login_otp_url")"
    _debug login_otp_response "${login_otp_response}"

    # Bail if OTP authentication fails.
    if [ "$(printf "%s" "${login_otp_response}" | _cyon_get_response_success)" != "success" ]; then
      _err "    $(printf "%s" "${login_otp_response}" | _cyon_get_response_message)"
      _err ""
      return 1
    fi

    _info "    success"

    # Update cookie after 2FA (only if new cookies are set)
    _new_cookies="$(_cyon_get_cookie_header)"
    if [ -n "$_new_cookies" ]; then
      _H2="$_new_cookies"
      export _H2
    fi
  fi

  _info ""
}

_cyon_logout() {
  _info "  - Logging out..."

  _get "https://my.cyon.ch/auth/index/dologout" >/dev/null

  _info "    success"
  _info ""
}

_cyon_change_domain_env() {
  _info "  - Changing domain environment..."

  # Get the "example.com" part of the full domain name.
  domain_env="$(printf "%s" "${fulldomain}" | sed -E -e 's/.*\.(.*\..*)$/\1/')"
  _debug "Changing domain environment to ${domain_env}"

  domain_page_response="$(_get "https://my.cyon.ch/domain/")"
  _debug domain_page_response "${domain_page_response}"

  # Check if we got an error response (JSON) instead of HTML
  if printf "%s" "${domain_page_response}" | grep -q '"iserror":true'; then
    _err "    $(printf "%s" "${domain_page_response}" | _cyon_get_response_message)"
    _err ""
    return 1
  fi

  gloo_item_key="$(printf "%s" "${domain_page_response}" | tr '\n' ' ' | sed -E -e "s/.*data-domain=\"${domain_env}\"[^<]*data-itemkey=\"([^\"]*).*/\1/")"
  _debug gloo_item_key "${gloo_item_key}"

  domain_env_url="https://my.cyon.ch/user/environment/setdomain/d/${domain_env}/gik/${gloo_item_key}"

  domain_env_response="$(_get "${domain_env_url}")"
  _debug domain_env_response "${domain_env_response}"

  if ! _cyon_check_if_2fa_missed "${domain_env_response}"; then return 1; fi

  # Bail if domain environment change fails.
  if [ "$(printf "%s" "${domain_env_response}" | _cyon_get_environment_change_status)" != "true" ]; then
    _err "    $(printf "%s" "${domain_env_response}" | _cyon_get_response_message)"
    _err ""
    return 1
  fi

  _info "    success"
  _info ""
}

_cyon_add_txt() {
  _info "  - Adding DNS TXT entry..."

  add_txt_url="https://my.cyon.ch/domain/dnseditor/add-record-async"
  add_txt_data="name=${fulldomain_idn}.&ttl=900&type=TXT&dnscontent=${txtvalue}"

  add_txt_response="$(_post "$add_txt_data" "$add_txt_url")"
  _debug add_txt_response "${add_txt_response}"

  if ! _cyon_check_if_2fa_missed "${add_txt_response}"; then return 1; fi

  add_txt_message="$(printf "%s" "${add_txt_response}" | _cyon_get_response_message)"
  add_txt_status="$(printf "%s" "${add_txt_response}" | _cyon_get_response_status)"
  add_txt_validation="$(printf "%s" "${add_txt_response}" | _cyon_get_validation_status)"

  # Bail if adding TXT entry fails.
  if [ "${add_txt_status}" != "true" ] || [ "${add_txt_validation}" != "true" ]; then
    _err "    ${add_txt_message}"
    _err ""
    return 1
  fi

  _info "    success (TXT|${fulldomain_idn}.|${txtvalue})"
  _info ""
}

_cyon_delete_txt() {
  _info "  - Deleting DNS TXT entry..."

  list_txt_url="https://my.cyon.ch/domain/dnseditor/list-async"

  list_txt_response="$(_get "${list_txt_url}" | sed -e 's/data-hash/\\ndata-hash/g')"
  _debug list_txt_response "${list_txt_response}"

  if ! _cyon_check_if_2fa_missed "${list_txt_response}"; then return 1; fi

  # Find and delete all acme challenge entries for the $fulldomain.
  _dns_entries="$(printf "%b\n" "${list_txt_response}" | sed -n 's/data-hash=\\"\([^"]*\)\\" data-identifier=\\"\([^"]*\)\\".*/\1 \2/p')"

  printf "%s" "${_dns_entries}" | while read -r _hash _identifier; do
    dns_type="$(printf "%s" "$_identifier" | cut -d'|' -f1)"
    dns_domain="$(printf "%s" "$_identifier" | cut -d'|' -f2)"

    if [ "${dns_type}" != "TXT" ] || [ "${dns_domain}" != "${fulldomain_idn}." ]; then
      continue
    fi

    hash_encoded="$(printf "%s" "${_hash}" | _url_encode)"
    identifier_encoded="$(printf "%s" "${_identifier}" | _url_encode)"

    delete_txt_url="https://my.cyon.ch/domain/dnseditor/delete-record-async"
    delete_txt_data="$(printf "%s" "hash=${hash_encoded}&identifier=${identifier_encoded}")"

    delete_txt_response="$(_post "$delete_txt_data" "$delete_txt_url")"
    _debug delete_txt_response "${delete_txt_response}"

    if ! _cyon_check_if_2fa_missed "${delete_txt_response}"; then return 1; fi

    delete_txt_message="$(printf "%s" "${delete_txt_response}" | _cyon_get_response_message)"
    delete_txt_status="$(printf "%s" "${delete_txt_response}" | _cyon_get_response_status)"

    # Skip if deleting TXT entry fails.
    if [ "${delete_txt_status}" != "true" ]; then
      _err "    ${delete_txt_message} (${_identifier})"
    else
      _info "    success (${_identifier})"
    fi
  done

  _info "    done"
  _info ""
}

_cyon_get_response_message() {
  _egrep_o '"message":"[^"]*"' | cut -d : -f 2 | tr -d '"'
}

_cyon_get_response_status() {
  _egrep_o '"status":[a-zA-Z0-9]*' | cut -d : -f 2
}

_cyon_get_validation_status() {
  _egrep_o '"valid":[a-zA-Z0-9]*' | cut -d : -f 2
}

_cyon_get_response_success() {
  _egrep_o '"onSuccess":"[^"]*"' | cut -d : -f 2 | tr -d '"'
}

_cyon_get_environment_change_status() {
  _egrep_o '"authenticated":[a-zA-Z0-9]*' | cut -d : -f 2
}

_cyon_check_if_2fa_missed() {
  # Did we miss the 2FA?
  if test "${1#*multi_factor_form}" != "${1}"; then
    _err "    Missed OTP authentication!"
    _err ""
    return 1
  fi
}

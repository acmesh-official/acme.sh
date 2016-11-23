#!/usr/bin/env sh

########
# Custom cyon.ch DNS API for use with [acme.sh](https://github.com/Neilpang/acme.sh)
#
# Usage: acme.sh --issue --dns dns_cyon -d www.domain.com
#
# Dependencies:
# -------------
# - oathtool (When using 2 Factor Authentication)
#
# Author: Armando Lüscher <armando@noplanman.ch>
########

########
# Define cyon.ch login credentials:
#
# Either set them here: (uncomment these lines)
#
# cyon_username='your_cyon_username'
# cyon_password='your_cyon_password'
# cyon_otp_secret='your_otp_secret' # Only required if using 2FA
#
# ...or export them as environment variables in your shell:
#
# $ export cyon_username='your_cyon_username'
# $ export cyon_password='your_cyon_password'
# $ export cyon_otp_secret='your_otp_secret' # Only required if using 2FA
#
# *Note:*
# After the first run, the credentials are saved in the "account.conf"
# file, so any hard-coded or environment variables can then be removed.
########

dns_cyon_add() {
  _load_credentials \
  && _load_parameters "$@" \
  && _info_header "add" \
  && _login \
  && _domain_env \
  && _add_txt \
  && _logout
}

dns_cyon_rm() {
  _load_credentials \
  && _load_parameters "$@" \
  && _info_header "delete" \
  && _login \
  && _domain_env \
  && _delete_txt \
  && _logout
}

#########################
### PRIVATE FUNCTIONS ###
#########################

_load_credentials() {
  # Convert loaded password to/from base64 as needed.
  if [ "${cyon_password_b64}" ]; then
    cyon_password="$(printf "%s" "${cyon_password_b64}" | _dbase64 "multiline")"
  elif [ "${cyon_password}" ]; then
    cyon_password_b64="$(printf "%s" "${cyon_password}" | _base64)"
  fi

  if [ -z "${cyon_username}" ] || [ -z "${cyon_password}" ]; then
    # Dummy entries to satify script checker.
    cyon_username=""
    cyon_password=""
    cyon_otp_secret=""

    _err ""
    _err "You haven't set your cyon.ch login credentials yet."
    _err "Please set the required cyon environment variables."
    _err ""
    return 1
  fi

  # Save the login credentials to the account.conf file.
  _debug "Save credentials to account.conf"
  _saveaccountconf cyon_username "${cyon_username}"
  _saveaccountconf cyon_password_b64 "$cyon_password_b64"
  if [ ! -z "${cyon_otp_secret}" ]; then
    _saveaccountconf cyon_otp_secret "$cyon_otp_secret"
  else
    _clearaccountconf cyon_otp_secret
  fi
}

_is_idn_cyon() {
  _idn_temp="$(printf "%s" "${1}" | tr -d "[0-9a-zA-Z.,-_]")"
  _idn_temp2="$(printf "%s" "${1}" | grep -o "xn--")"
  [ "$_idn_temp" ] || [ "$_idn_temp2" ]
}

# comment on https://stackoverflow.com/a/10797966
_urlencode_cyon() {
  curl -Gso /dev/null -w %{url_effective} --data-urlencode @- "" | cut -c 3-
}

_load_parameters() {
  # Read the required parameters to add the TXT entry.
  fulldomain="$(printf "%s" "${1}" | tr '[:upper:]' '[:lower:]')"
  fulldomain_idn="${fulldomain}"

  # Special case for IDNs, as cyon needs a domain environment change,
  # which uses the "pretty" instead of the punycode version.
  if _is_idn_cyon "${fulldomain}"; then
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
}

_info_header() {
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

_get_cookie_header() {
  printf "%s" "$(sed -n 's/Set-\(Cookie:.*cyon=[^;]*\).*/\1/p' "$HTTP_HEADER" | _tail_n 1)"
}

_login() {
  _info "  - Logging in..."

  username_encoded="$(printf "%s" "${cyon_username}" | _urlencode_cyon)"
  password_encoded="$(printf "%s" "${cyon_password}" | _urlencode_cyon)"

  login_url="https://my.cyon.ch/auth/index/dologin-async"
  login_data="$(printf "%s" "username=${username_encoded}&password=${password_encoded}&pathname=%2F")"

  login_response="$(_post "$login_data" "$login_url")"
  _debug login_response "${login_response}"

  # Bail if login fails.
  if [ "$(printf "%s" "${login_response}" | _get_response_success)" != "success" ]; then
    _err "    $(printf "%s" "${login_response}" | _get_response_message)"
    _err ""
    return 1
  fi

  _info "    success"

  # NECESSARY!! Load the main page after login, to get the new cookie.
  _H2="$(_get_cookie_header)"
  _get "https://my.cyon.ch/" > /dev/null

  # todo: instead of just checking if the env variable is defined, check if we actually need to do a 2FA auth request.

  # 2FA authentication with OTP?
  if [ ! -z "${cyon_otp_secret}" ]; then
    _info "  - Authorising with OTP code..."

    if ! _exists oathtool; then
      _err "Please install oathtool to use 2 Factor Authentication."
      _err ""
      return 1
    fi

    # Get OTP code with the defined secret.
    otp_code="$(oathtool --base32 --totp "${cyon_otp_secret}" 2>/dev/null)"

    login_otp_url="https://my.cyon.ch/auth/multi-factor/domultifactorauth-async"
    login_otp_data="totpcode=${otp_code}&pathname=%2F&rememberme=0"

    login_otp_response="$(_post "$login_otp_data" "$login_otp_url")"
    _debug login_otp_response "${login_otp_response}"

    # Bail if OTP authentication fails.
    if [ "$(printf "%s" "${login_otp_response}" | _get_response_success)" != "success" ]; then
      _err "    $(printf "%s" "${login_otp_response}" | _get_response_message)"
      _err ""
      return 1
    fi

    _info "    success"
  fi

  _info ""
}

_logout() {
  _info "  - Logging out..."

  _get "https://my.cyon.ch/auth/index/dologout" > /dev/null

  _info "    success"
  _info ""
}

_domain_env() {
  _info "  - Changing domain environment..."

  # Get the "example.com" part of the full domain name.
  domain_env="$(printf "%s" "${fulldomain}" | sed -E -e 's/.*\.(.*\..*)$/\1/')"
  _debug "Changing domain environment to ${domain_env}"

  domain_env_url="https://my.cyon.ch/user/environment/setdomain/d/${domain_env}/gik/domain%3A${domain_env}"

  domain_env_response="$(_get "${domain_env_url}")"
  _debug domain_env_response "${domain_env_response}"

  if ! _check_if_2fa_missed "${domain_env_response}"; then return 1; fi

  domain_env_success="$(printf "%s" "${domain_env_response}" | _egrep_o '"authenticated":\w*' | cut -d : -f 2)"

  # Bail if domain environment change fails.
  if [ "${domain_env_success}" != "true" ]; then
    _err "    $(printf "%s" "${domain_env_response}" | _get_response_message)"
    _err ""
    return 1
  fi

  _info "    success"
  _info ""
}

_add_txt() {
  _info "  - Adding DNS TXT entry..."

  add_txt_url="https://my.cyon.ch/domain/dnseditor/add-record-async"
  add_txt_data="zone=${fulldomain_idn}.&ttl=900&type=TXT&value=${txtvalue}"

  add_txt_response="$(_post "$add_txt_data" "$add_txt_url")"
  _debug add_txt_response "${add_txt_response}"

  if ! _check_if_2fa_missed "${add_txt_response}"; then return 1; fi

  add_txt_message="$(printf "%s" "${add_txt_response}" | _get_response_message)"
  add_txt_status="$(printf "%s" "${add_txt_response}" | _get_response_status)"

  # Bail if adding TXT entry fails.
  if [ "${add_txt_status}" != "true" ]; then
    _err "    ${add_txt_message}"
    _err ""
    return 1
  fi

  _info "    success (TXT|${fulldomain_idn}.|${txtvalue})"
  _info ""
}

_delete_txt() {
  _info "  - Deleting DNS TXT entry..."

  list_txt_url="https://my.cyon.ch/domain/dnseditor/list-async"

  list_txt_response="$(_get "${list_txt_url}" | sed -e 's/data-hash/\\ndata-hash/g')"
  _debug list_txt_response "${list_txt_response}"

  if ! _check_if_2fa_missed "${list_txt_response}"; then return 1; fi

  # Find and delete all acme challenge entries for the $fulldomain.
  _dns_entries="$(printf "%b\n" "${list_txt_response}" | sed -n 's/data-hash=\\"\([^"]*\)\\" data-identifier=\\"\([^"]*\)\\".*/\1 \2/p')"

  printf "%s" "${_dns_entries}" | while read -r _hash _identifier; do
    dns_type="$(printf "%s" "$_identifier" | cut -d'|' -f1)"
    dns_domain="$(printf "%s" "$_identifier" | cut -d'|' -f2)"

    if [ "${dns_type}" != "TXT" ] || [ "${dns_domain}" != "${fulldomain_idn}." ]; then
      continue
    fi

    hash_encoded="$(printf "%s" "${_hash}" | _urlencode_cyon)"
    identifier_encoded="$(printf "%s" "${_identifier}" | _urlencode_cyon)"

    delete_txt_url="https://my.cyon.ch/domain/dnseditor/delete-record-async"
    delete_txt_data="$(printf "%s" "hash=${hash_encoded}&identifier=${identifier_encoded}")"

    delete_txt_response="$(_post "$delete_txt_data" "$delete_txt_url")"
    _debug delete_txt_response "${delete_txt_response}"

    if ! _check_if_2fa_missed "${delete_txt_response}"; then return 1; fi

    delete_txt_message="$(printf "%s" "${delete_txt_response}" | _get_response_message)"
    delete_txt_status="$(printf "%s" "${delete_txt_response}" | _get_response_status)"

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

_get_response_message() {
  _egrep_o '"message":"[^"]*"' | cut -d : -f 2 | tr -d '"'
}

_get_response_status() {
  _egrep_o '"status":\w*' | cut -d : -f 2
}

_get_response_success() {
  _egrep_o '"onSuccess":"[^"]*"' | cut -d : -f 2 | tr -d '"'
}

_check_if_2fa_missed() {
  # Did we miss the 2FA?
  if test "${1#*multi_factor_form}" != "${1}"; then
    _err "    Missed OTP authentication!"
  _err ""
  return 1
  fi
}

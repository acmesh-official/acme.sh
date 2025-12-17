#!/usr/bin/env sh

# JamoTech Customer Domain amce Helper
# This script is intended to be run via
# acme.sh on managed customer systems
# to allow customers to create and renew
# SSL certificates on their client
# subdomain e.g (client.jamo.tech)
# without the need for support staff
# to create TXT records.

# API Calls to be made
# _get("https://api.corp-jamo.tech/dns/v1/records/exists.php?access=accesskey&hostname=subdomain&target=10.8.0.1&type=A")
# _get("https://api.corp-jamo.tech/dns/v1/records/exists.php?access=accesskey&hostname=_acme-challenge.subdomain&target=ACMEKEY&type=TXT")
# _get("https://api.corp-jamo.tech/dns/v1/records/add.php?access=accesskey&hostname=subdomain&target=10.8.0.1&type=A")
# _get("https://api.corp-jamo.tech/dns/v1/records/add.php?access=accesskey&hostname=_acme-challenge.subdomain&target=ACMEKEY&type=TXT")
# _get("https://api.corp-jamo.tech/dns/v1/records/remove.php?access=accesskey&hostname=subdomain&target=10.8.0.1&type=A")
# _get("https://api.corp-jamo.tech/dns/v1/records/remove.php?access=accesskey&hostname=_acme-challenge.subdomain&target=ACMEKEY&type=TXT")

dns_jamotech_add() {
  fulldomain=$1
  txtvalue=$2
  JTECH_ENDIP="${JTECH_ENDIP:-$(_readaccountconf_mutable JTECH_ENDIP)}"
  JTECH_KEY="${JTECH_KEY:-$(_readaccountconf_mutable JTECH_KEY)}"

  if [ "$JTECH_ENDIP" ]; then
    _saveaccountconf_mutable JTECH_ENDIP "$JTECH_ENDIP"
  else
    _err "You need to specify an end IP by running 'export JTECH_ENDIP=IP'"
    return 1
  fi

  if [ "$JTECH_KEY" ]; then
    _saveaccountconf_mutable JTECH_KEY "$JTECH_KEY"
  else
    _err "You need to specify an API Key by running 'export JTECH_KEY=APIKEY'"
    return 1
  fi
  _info "Using jamotech-register to add the TXT record"
  _get_root
  _create_record
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

}

dns_jamotech_rm() {
  fulldomain=$1
  txtvalue=$2

  JTECH_ENDIP="${JTECH_ENDIP:-$(_readaccountconf_mutable JTECH_ENDIP)}"
  JTECH_KEY="${JTECH_KEY:-$(_readaccountconf_mutable JTECH_KEY)}"

  if [ "$JTECH_ENDIP" ]; then
    _saveaccountconf_mutable JTECH_ENDIP "$JTECH_ENDIP"
  else
    _err "You need to specify an end IP by running 'export JTECH_ENDIP=IP'"
    return 1
  fi

  if [ "$JTECH_KEY" ]; then
    _saveaccountconf_mutable JTECH_KEY "$JTECH_KEY"
  else
    _err "You need to specify an API Key by running 'export JTECH_KEY=APIKEY'"
    return 1
  fi

  _info "Using jamotech-clean to remove the TXT record"
  _get_root
  _remove_record
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

}

####################  Private functions below ##################################

_get_root() {
  domain=$fulldomain
  txtdomain=${domain%.jamo.tech}
  subdomain=$(echo "$txtdomain" | cut -d'.' -f2-)
  _debug "txtdomain = $txtdomain"
  _debug "subdomain = $subdomain"
  _debug "Domain: $domain       TXTDomain: $txtdomain     Subdomain: $subdomain"
  if [ -z "$domain" ] || [ -z "$txtdomain" ] || [ -z "$subdomain" ]; then
    _err "We weren't able to determine the records which need to be created."
    return 1
  fi
  _txthost="$txtdomain"
  _subhost="$subdomain"
  _err "$domain not found"
  return 1
}

_check_record() {
  server_record="https://api.corp-jamo.tech/dns/v1/records/exists.php?access=$JTECH_KEY&hostname=$_subhost&target=$JTECH_ENDIP&type=A"
  txt_record="https://api.corp-jamo.tech/dns/v1/records/exists.php?access=$JTECH_KEY&hostname=$_txthost&target=$txtvalue&type=TXT"
  _debug "API ENDPOINTS $server_record $txt_record"

  response="$(_get "$server_record")"
  if [ "$?" != "0" ]; then
    _err "error"
    return 1
  fi

  if _contains "$response" '"exists":"true"}'; then
    _err "Record already exists."
    return 1
  fi

  response="$(_get "$txt_record")"
  if [ "$?" != "0" ]; then
    _err "error"
    return 1
  fi

  if _contains "$response" '"exists":"true"}'; then
    _err "Record already exists."
    return 1
  fi
}

_create_record() {
  _check_record
  server_record="https://api.corp-jamo.tech/dns/v1/records/add.php?access=$JTECH_KEY&hostname=$_subhost&target=$JTECH_ENDIP&type=A"
  txt_record="https://api.corp-jamo.tech/dns/v1/records/add.php?access=$JTECH_KEY&hostname=$_txthost&target=$txtvalue&type=TXT"
  _debug "API ENDPOINTS $server_record $txt_record"

  response="$(_get "$server_record")"
  if [ "$?" != "0" ]; then
    _err "error"
    return 1
  fi

  response="$(_get "$txt_record")"
  if [ "$?" != "0" ]; then
    _err "error"
    return 1
  fi

  return 0
}

_remove_record() {
  server_record="https://api.corp-jamo.tech/dns/v1/records/remove.php?access=$JTECH_KEY&hostname=$_subhost&target=$JTECH_ENDIP&type=A"
  txt_record="https://api.corp-jamo.tech/dns/v1/records/remove.php?access=$JTECH_KEY&hostname=$_txthost&target=$txtvalue&type=TXT"
  _debug "API ENDPOINTS $server_record $txt_record"

  response="$(_get "$server_record")"
  if [ "$?" != "0" ]; then
    _err "error"
    return 1
  fi

  response="$(_get "$txt_record")"
  if [ "$?" != "0" ]; then
    _err "error"
    return 1
  fi

  return 0
}

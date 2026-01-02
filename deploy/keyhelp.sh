#!/usr/bin/env sh

# Script to deploy certificate to KeyHelp
# This deployment required following variables
# export DEPLOY_KEYHELP_BASEURL="https://keyhelp.example.com"
# export DEPLOY_KEYHELP_USERNAME="Your KeyHelp Username"
# export DEPLOY_KEYHELP_PASSWORD="Your KeyHelp Password"
# export DEPLOY_KEYHELP_DOMAIN_ID="Depoly certificate to this Domain ID"

# Open the 'Edit domain' page, and you will see id=xxx at the end of the URL. This is the Domain ID.
# https://DEPLOY_KEYHELP_BASEURL/index.php?page=domains&action=edit&id=xxx

# If have more than one domain name
# export DEPLOY_KEYHELP_DOMAIN_ID="111 222 333"

keyhelp_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  if [ -z "$DEPLOY_KEYHELP_BASEURL" ]; then
    _err "DEPLOY_KEYHELP_BASEURL is not defined."
    return 1
  else
    _savedomainconf DEPLOY_KEYHELP_BASEURL "$DEPLOY_KEYHELP_BASEURL"
  fi

  if [ -z "$DEPLOY_KEYHELP_USERNAME" ]; then
    _err "DEPLOY_KEYHELP_USERNAME is not defined."
    return 1
  else
    _savedomainconf DEPLOY_KEYHELP_USERNAME "$DEPLOY_KEYHELP_USERNAME"
  fi

  if [ -z "$DEPLOY_KEYHELP_PASSWORD" ]; then
    _err "DEPLOY_KEYHELP_PASSWORD is not defined."
    return 1
  else
    _savedomainconf DEPLOY_KEYHELP_PASSWORD "$DEPLOY_KEYHELP_PASSWORD"
  fi

  if [ -z "$DEPLOY_KEYHELP_DOMAIN_ID" ]; then
    _err "DEPLOY_KEYHELP_DOMAIN_ID is not defined."
    return 1
  else
    _savedomainconf DEPLOY_KEYHELP_DOMAIN_ID "$DEPLOY_KEYHELP_DOMAIN_ID"
  fi

  # Optional DEPLOY_KEYHELP_ENFORCE_HTTPS
  _getdeployconf DEPLOY_KEYHELP_ENFORCE_HTTPS
  # set default values for DEPLOY_KEYHELP_ENFORCE_HTTPS
  [ -n "${DEPLOY_KEYHELP_ENFORCE_HTTPS}" ] || DEPLOY_KEYHELP_ENFORCE_HTTPS="1"

  _info "Logging in to keyhelp panel"
  username_encoded="$(printf "%s" "${DEPLOY_KEYHELP_USERNAME}" | _url_encode)"
  password_encoded="$(printf "%s" "${DEPLOY_KEYHELP_PASSWORD}" | _url_encode)"
  _H1="Content-Type: application/x-www-form-urlencoded"
  _response=$(_get "$DEPLOY_KEYHELP_BASEURL/index.php?submit=1&username=$username_encoded&password=$password_encoded" "TRUE")
  _cookie="$(grep -i '^set-cookie:' "$HTTP_HEADER" | _head_n 1 | cut -d " " -f 2)"

  # If cookies is not empty then logon successful
  if [ -z "$_cookie" ]; then
    _err "Fail to get cookie."
    return 1
  fi
  _debug "cookie" "$_cookie"

  _info "Uploading certificate"
  _date=$(date +"%Y%m%d")
  encoded_key="$(_url_encode <"$_ckey")"
  encoded_ccert="$(_url_encode <"$_ccert")"
  encoded_cca="$(_url_encode <"$_cca")"
  certificate_name="$_cdomain-$_date"

  _request_body="submit=1&certificate_name=$certificate_name&add_type=upload&text_private_key=$encoded_key&text_certificate=$encoded_ccert&text_ca_certificate=$encoded_cca"
  _H1="Cookie: $_cookie"
  _response=$(_post "$_request_body" "$DEPLOY_KEYHELP_BASEURL/index.php?page=ssl_certificates&action=add" "" "POST")
  _message=$(echo "$_response" | grep -A 2 'message-body' | sed -n '/<div class="message-body ">/,/<\/div>/{//!p;}' | sed 's/<[^>]*>//g' | sed 's/^ *//;s/ *$//')
  _info "_message" "$_message"
  if [ -z "$_message" ]; then
    _err "Fail to upload certificate."
    return 1
  fi

  for DOMAIN_ID in $DEPLOY_KEYHELP_DOMAIN_ID; do
    _info "Apply certificate to domain id $DOMAIN_ID"
    _response=$(_get "$DEPLOY_KEYHELP_BASEURL/index.php?page=domains&action=edit&id=$DOMAIN_ID")
    cert_value=$(echo "$_response" | grep "$certificate_name" | sed -n 's/.*value="\([^"]*\).*/\1/p')
    target_type=$(echo "$_response" | grep 'target_type' | grep 'checked' | sed -n 's/.*value="\([^"]*\).*/\1/p')
    if [ "$target_type" = "directory" ]; then
      path=$(echo "$_response" | awk '/name="path"/{getline; print}' | sed -n 's/.*value="\([^"]*\).*/\1/p')
    fi
    echo "$_response" | grep "is_prefer_https" | grep "checked" >/dev/null
    if [ $? -eq 0 ]; then
      is_prefer_https=1
    else
      is_prefer_https=0
    fi
    echo "$_response" | grep "hsts_enabled" | grep "checked" >/dev/null
    if [ $? -eq 0 ]; then
      hsts_enabled=1
    else
      hsts_enabled=0
    fi
    _debug "cert_value" "$cert_value"
    if [ -z "$cert_value" ]; then
      _err "Fail to get certificate id."
      return 1
    fi

    _request_body="submit=1&id=$DOMAIN_ID&target_type=$target_type&path=$path&is_prefer_https=$is_prefer_https&hsts_enabled=$hsts_enabled&certificate_type=custom&certificate_id=$cert_value&enforce_https=$DEPLOY_KEYHELP_ENFORCE_HTTPS"
    _response=$(_post "$_request_body" "$DEPLOY_KEYHELP_BASEURL/index.php?page=domains&action=edit" "" "POST")
    _message=$(echo "$_response" | grep -A 2 'message-body' | sed -n '/<div class="message-body ">/,/<\/div>/{//!p;}' | sed 's/<[^>]*>//g' | sed 's/^ *//;s/ *$//')
    _info "_message" "$_message"
    if [ -z "$_message" ]; then
      _err "Fail to apply certificate."
      return 1
    fi
  done

  _info "Domain $_cdomain certificate successfully deployed to KeyHelp Domain ID $DEPLOY_KEYHELP_DOMAIN_ID."
  return 0
}

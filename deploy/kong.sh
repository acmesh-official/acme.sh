#!/usr/bin/env sh

# This deploy hook will deploy ssl cert on kong proxy engine based on api request_host parameter.
# Note that ssl plugin should be available on Kong instance
# The hook will match cdomain to request_host, in case of multiple domain it will always take the first
# one (acme.sh behaviour).
# If ssl config already exist it will update only cert and key not touching other parameter
# If ssl config doesn't exist it will only upload cert and key and not set other parameter
# Not that we deploy full chain
# See https://getkong.org/plugins/dynamic-ssl/ for other options
# Written by Geoffroi Genot <ggenot@voxbone.com>

########  Public functions #####################

#domain keyfile certfile cafile fullchain
kong_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"
  _info "Deploying certificate on Kong instance"
  if [ -z "$KONG_URL" ]; then
    _debug "KONG_URL Not set, using default http://localhost:8001"
    KONG_URL="http://localhost:8001"
  fi

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  #Get uuid linked to the domain
  uuid=$(_get "$KONG_URL/apis?request_host=$_cdomain" | _normalizeJson | _egrep_o '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
  if [ -z "$uuid" ]; then
    _err "Unable to get Kong uuid for domain $_cdomain"
    _err "Make sure that KONG_URL is correctly configured"
    _err "Make sure that a Kong api request_host match the domain"
    _err "Kong url: $KONG_URL"
    return 1
  fi
  #Save kong url if it's succesful (First run case)
  _saveaccountconf KONG_URL "$KONG_URL"
  #Generate DEIM
  delim="-----MultipartDelimiter$(date "+%s%N")"
  nl="\015\012"
  #Set Header
  _H1="Content-Type: multipart/form-data; boundary=$delim"
  #Generate data for request (Multipart/form-data with mixed content)
  #set name to ssl
  content="--$delim${nl}Content-Disposition: form-data; name=\"name\"${nl}${nl}ssl"
  #add key
  content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"config.key\"; filename=\"$(basename "$_ckey")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_ckey")"
  #Add cert
  content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"config.cert\"; filename=\"$(basename "$_cfullchain")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_cfullchain")"
  #Close multipart
  content="$content${nl}--$delim--${nl}"
  #Convert CRLF
  content=$(printf %b "$content")
  #DEBUG
  _debug header "$_H1"
  _debug content "$content"
  #Check if ssl plugins is aready enabled (if not => POST else => PATCH)
  ssl_uuid=$(_get "$KONG_URL/apis/$uuid/plugins" | _egrep_o '"id":"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"[a-zA-Z0-9\-\,\"_\:]*"name":"ssl"' | _egrep_o '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
  _debug ssl_uuid "$ssl_uuid"
  if [ -z "$ssl_uuid" ]; then
    #Post certificate to Kong
    response=$(_post "$content" "$KONG_URL/apis/$uuid/plugins" "" "POST")
  else
    #patch
    response=$(_post "$content" "$KONG_URL/apis/$uuid/plugins/$ssl_uuid" "" "PATCH")
  fi
  if ! [ "$(echo "$response" | _egrep_o "ssl")" = "ssl" ]; then
    _err "An error occurred with cert upload. Check response:"
    _err "$response"
    return 1
  fi
  _debug response "$response"
  _info "Certificate successfully deployed"
}

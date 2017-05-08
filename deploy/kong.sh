#!/usr/bin/env sh
# If certificate already exist it will update only cert and key not touching other parameter
# If certificate  doesn't exist it will only upload cert and key and not set other parameter
# Note that we deploy full chain
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

  #Get ssl_uuid linked to the domain
  ssl_uuid=$(_get "$KONG_URL/certificates/$_cdomain" | _normalizeJson | _egrep_o '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
  if [ -z "$ssl_uuid" ]; then
    _debug "Unable to get Kong ssl_uuid for domain $_cdomain"
    _debug "Make sure that KONG_URL is correctly configured"
    _debug "Make sure that a Kong certificate match the sni"
    _debug "Kong url: $KONG_URL"
    _info "No existing certificate, creating..."
    #return 1
  fi
  #Save kong url if it's succesful (First run case)
  _saveaccountconf KONG_URL "$KONG_URL"
  #Generate DEIM
  delim="-----MultipartDelimiter$(date "+%s%N")"
  nl="\015\012"
  #Set Header
  _H1="Content-Type: multipart/form-data; boundary=$delim"
  #Generate data for request (Multipart/form-data with mixed content)
  if [ -z "$ssl_uuid" ]; then
    #set sni to domain
    content="--$delim${nl}Content-Disposition: form-data; name=\"snis\"${nl}${nl}$_cdomain"
  fi
  #add key
  content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"key\"; filename=\"$(basename "$_ckey")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_ckey")"
  #Add cert
  content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"cert\"; filename=\"$(basename "$_cfullchain")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_cfullchain")"
  #Close multipart
  content="$content${nl}--$delim--${nl}"
  #Convert CRLF
  content=$(printf %b "$content")
  #DEBUG
  _debug header "$_H1"
  _debug content "$content"
  #Check if sslcreated (if not => POST else => PATCH)

  if [ -z "$ssl_uuid" ]; then
    #Post certificate to Kong
    response=$(_post "$content" "$KONG_URL/certificates" "" "POST")
  else
    #patch
    response=$(_post "$content" "$KONG_URL/certificates/$ssl_uuid" "" "PATCH")
  fi
  if ! [ "$(echo "$response" | _egrep_o "created_at")" = "created_at" ]; then
    _err "An error occurred with cert upload. Check response:"
    _err "$response"
    return 1
  fi
  _debug response "$response"
  _info "Certificate successfully deployed"
}

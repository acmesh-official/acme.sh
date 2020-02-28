#!/usr/bin/env sh

# This script used to automatically deploy dokku
# global wildcard domain's certificate.
# If your dokku global domain is dokku.example.com
# and you dokku app is domains-app-enabled
# and the app heve domains like dokku.example.com
# *.dokku.example.com, this script will
# automatic execute `dokku certs:update app <certs`
# to enable and update the app SSL certificate.

# DOKKU_SSL_DOCUMENTATION='http://dokku.viewdocs.io/dokku/configuration/ssl/'

########  Public functions #####################

# domain keyfile certfile cafile fullchain
dokku_deploy() {
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

  temp_dir=$(mktemp -d -t cert_pack-XXXXXX)
  _debug "Create temp dir at $temp_dir"
  cd "$temp_dir" || return 1
  cp "$_cfullchain" "server.crt"
  cp "$_ckey" "server.key"
  _debug "Create cert-key.tar at temp dir"
  tar cf cert-key.tar server.crt server.key

  _debug "Get dokku app list"
  apps=$(dokku apps:list --quiet)
  _debug "Dokku apps: $apps"

  _debug "Find domain $_cdomain in dokku domain enabled apps"
  for app in $apps; do
    app_enable=$(dokku domains:report "$app" --domains-app-enabled)
    if [[ $app_enable == "true" ]]; then
      app_vhosts=$(dokku domains:report "$app" --domains-app-vhosts)
      _debug "App '$app' domains: $app_vhosts"
      for domain in $app_vhosts; do
        if [[ $domain == "$_cdomain" || $domain == *.$_cdomain ]]; then
          _debug "Update dokku app '$app' cert"
          dokku certs:update "$app" <cert-key.tar
          _debug "Dokku app '$app' cert update finished"
          break
        fi
      done
    fi
  done

  cd - || return 0
  _debug "Remove temp dir: $temp_dir"
  rm -rf "$temp_dir"
  _debug "Clean."
  _debug "Deploy finish."

  return 0

}

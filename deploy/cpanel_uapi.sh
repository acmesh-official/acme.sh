#!/usr/bin/env sh
# Here is the script to deploy the cert to your cpanel using the cpanel API.
# Uses command line uapi.  --user option is needed only if run as root.
# Returns 0 when success.
#
# Configure DEPLOY_CPANEL_AUTO_<...> options to enable or restrict automatic
# detection of deployment targets through UAPI (if not set, defaults below are used.)
# - ENABLED : 'true' for multi-site / wildcard capability; otherwise single-site mode.
# - NOMATCH : 'true' to allow deployment to sites that do not match the certificate.
# - INCLUDE : Comma-separated list - sites must match this field.
# - EXCLUDE : Comma-separated list - sites must NOT match this field.
# INCLUDE/EXCLUDE both support non-lexical, glob-style matches using '*'
#
# Please note that I am no longer using Github. If you want to report an issue
# or contact me, visit https://forum.webseodesigners.com/web-design-seo-and-hosting-f16/
#
# Written by Santeri Kannisto <santeri.kannisto@webseodesigners.com>
# Public domain, 2017-2018
#
# export DEPLOY_CPANEL_USER=myusername
# export DEPLOY_CPANEL_AUTO_ENABLED='true'
# export DEPLOY_CPANEL_AUTO_NOMATCH='false'
# export DEPLOY_CPANEL_AUTO_INCLUDE='*'
# export DEPLOY_CPANEL_AUTO_EXCLUDE=''

########  Public functions #####################

#domain keyfile certfile cafile fullchain
cpanel_uapi_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  # re-declare vars inherited from acme.sh but not passed to make ShellCheck happy
  : "${Le_Alt:=""}"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  if ! _exists uapi; then
    _err "The command uapi is not found."
    return 1
  fi

  # declare useful constants
  uapi_error_response='status: 0'

  # read cert and key files and urlencode both
  _cert=$(_url_encode <"$_ccert")
  _key=$(_url_encode <"$_ckey")

  _debug2 _cert "$_cert"
  _debug2 _key "$_key"

  if [ "$(id -u)" = 0 ]; then
    _getdeployconf DEPLOY_CPANEL_USER
    # fallback to _readdomainconf for old installs
    if [ -z "${DEPLOY_CPANEL_USER:=$(_readdomainconf DEPLOY_CPANEL_USER)}" ]; then
      _err "It seems that you are root, please define the target user name: export DEPLOY_CPANEL_USER=username"
      return 1
    fi
    _debug DEPLOY_CPANEL_USER "$DEPLOY_CPANEL_USER"
    _savedeployconf DEPLOY_CPANEL_USER "$DEPLOY_CPANEL_USER"

    _uapi_user="$DEPLOY_CPANEL_USER"
  fi

  # Load all AUTO envars and set defaults - see above for usage
  __cpanel_initautoparam ENABLED 'true'
  __cpanel_initautoparam NOMATCH 'false'
  __cpanel_initautoparam INCLUDE '*'
  __cpanel_initautoparam EXCLUDE ''

  # Auto mode
  if [ "$DEPLOY_CPANEL_AUTO_ENABLED" = "true" ]; then
    # call API for site config
    _response=$(uapi DomainInfo list_domains)
    # exit if error in response
    if [ -z "$_response" ] || [ "${_response#*"$uapi_error_response"}" != "$_response" ]; then
      _err "Error in deploying certificate - cannot retrieve sitelist:"
      _err "\n$_response"
      return 1
    fi

    # parse response to create site list
    sitelist=$(__cpanel_parse_response "$_response")
    _debug "UAPI sites found: $sitelist"

    # filter sitelist using configured domains
    # skip if NOMATCH is "true"
    if [ "$DEPLOY_CPANEL_AUTO_NOMATCH" = "true" ]; then
      _debug "DEPLOY_CPANEL_AUTO_NOMATCH is true"
      _info "UAPI nomatch mode is enabled - Will not validate sites are valid for the certificate"
    else
      _debug "DEPLOY_CPANEL_AUTO_NOMATCH is false"
      d="$(echo "${Le_Alt}," | sed -e "s/^$_cdomain,//" -e "s/,$_cdomain,/,/")"
      d="$(echo "$_cdomain,$d" | tr ',' '\n' | sed -e 's/\./\\./g' -e 's/\*/\[\^\.\]\*/g')"
      sitelist="$(echo "$sitelist" | grep -ix "$d")"
      _debug2 "Matched UAPI sites: $sitelist"
    fi

    # filter sites that do not match $DEPLOY_CPANEL_AUTO_INCLUDE
    _info "Applying sitelist filter DEPLOY_CPANEL_AUTO_INCLUDE: $DEPLOY_CPANEL_AUTO_INCLUDE"
    sitelist="$(echo "$sitelist" | grep -ix "$(echo "$DEPLOY_CPANEL_AUTO_INCLUDE" | tr ',' '\n' | sed -e 's/\./\\./g' -e 's/\*/\.\*/g')")"
    _debug2 "Remaining sites: $sitelist"

    # filter sites that match $DEPLOY_CPANEL_AUTO_EXCLUDE
    _info "Applying sitelist filter DEPLOY_CPANEL_AUTO_EXCLUDE: $DEPLOY_CPANEL_AUTO_EXCLUDE"
    sitelist="$(echo "$sitelist" | grep -vix "$(echo "$DEPLOY_CPANEL_AUTO_EXCLUDE" | tr ',' '\n' | sed -e 's/\./\\./g' -e 's/\*/\.\*/g')")"
    _debug2 "Remaining sites: $sitelist"

    # counter for success / failure check
    successes=0
    if [ -n "$sitelist" ]; then
      sitetotal="$(echo "$sitelist" | wc -l)"
      _debug "$sitetotal sites to deploy"
    else
      sitetotal=0
      _debug "No sites to deploy"
    fi

    # for each site: call uapi to publish cert and log result. Only return failure if all fail
    for site in $sitelist; do
      # call uapi to publish cert, check response for errors and log them.
      if [ -n "$_uapi_user" ]; then
        _response=$(uapi --user="$_uapi_user" SSL install_ssl domain="$site" cert="$_cert" key="$_key")
      else
        _response=$(uapi SSL install_ssl domain="$site" cert="$_cert" key="$_key")
      fi
      if [ "${_response#*"$uapi_error_response"}" != "$_response" ]; then
        _err "Error in deploying certificate to $site:"
        _err "$_response"
      else
        successes=$((successes + 1))
        _debug "$_response"
        _info "Succcessfully deployed to $site"
      fi
    done

    # Raise error if all updates fail
    if [ "$sitetotal" -gt 0 ] && [ "$successes" -eq 0 ]; then
      _err "Could not deploy to any of $sitetotal sites via UAPI"
      _debug "successes: $successes, sitetotal: $sitetotal"
      return 1
    fi

    _info "Successfully deployed certificate to $successes of $sitetotal sites via UAPI"
    return 0
  else
    # "classic" mode - will only try to deploy to the primary domain; will not check UAPI first
    if [ -n "$_uapi_user" ]; then
      _response=$(uapi --user="$_uapi_user" SSL install_ssl domain="$_cdomain" cert="$_cert" key="$_key")
    else
      _response=$(uapi SSL install_ssl domain="$_cdomain" cert="$_cert" key="$_key")
    fi

    if [ "${_response#*"$uapi_error_response"}" != "$_response" ]; then
      _err "Error in deploying certificate:"
      _err "$_response"
      return 1
    fi

    _debug response "$_response"
    _info "Certificate successfully deployed"
    return 0
  fi
}

########  Private functions #####################

# Internal utility to process YML from UAPI - looks at main_domain, sub_domains, addon domains and parked domains
#[response]
__cpanel_parse_response() {
  if [ $# -gt 0 ]; then resp="$*"; else resp="$(cat)"; fi

  echo "$resp" |
    sed -En \
      -e 's/\r$//' \
      -e 's/^( *)([_.[:alnum:]]+) *: *(.*)/\1,\2,\3/p' \
      -e 's/^( *)- (.*)/\1,-,\2/p' |
    awk -F, '{
      level = length($1)/2;
      section[level] = $2;
      for (i in section) {if (i > level) {delete section[i]}}
      if (length($3) > 0) {
        prefix="";
        for (i=0; i < level; i++)
          { prefix = (prefix)(section[i])("/") }
        printf("%s%s=%s\n", prefix, $2, $3);
      }
    }' |
    sed -En -e 's/^result\/data\/(main_domain|sub_domains\/-|addon_domains\/-|parked_domains\/-)=(.*)$/\2/p'
}

# Load parameter by prefix+name - fallback to default if not set, and save to config
#pname pdefault
__cpanel_initautoparam() {
  pname="$1"
  pdefault="$2"
  pkey="DEPLOY_CPANEL_AUTO_$pname"

  _getdeployconf "$pkey"
  [ -n "$(eval echo "\"\$$pkey\"")" ] || eval "$pkey=\"$pdefault\""
  _debug2 "$pkey" "$(eval echo "\"\$$pkey\"")"
  _savedeployconf "$pkey" "$(eval echo "\"\$$pkey\"")"
}

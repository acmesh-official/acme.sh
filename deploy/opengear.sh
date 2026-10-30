#!/usr/bin/env sh

# Script to deploy a certificate to an Opengear Operations Manager (and
# Lighthouse) appliance over SSH.
#
# See the Opengear documentation:
# https://opengear.zendesk.com/hc/en-us/articles/8141687682203-Installing-a-HTTPS-certificate-from-the-CLI
#
# Returns 0 when successful, otherwise an error.
#
# SSH must be able to log in to the remote host without a password (exchange
# SSH keys first) and the user must have password-less sudo access. Validate
# that you can log in to USER@HOST from the host running acme.sh before using
# this script.
#
# The following environment variables are used on the first run and then
# saved (encrypted) to the deploy configuration:
#
#   export OPENGEAR_USER="root"    # required
#   export OPENGEAR_HOST="om1234"  # optional, defaults to the domain name

Le_Deploy_ssh_cmd="ssh"

#domain keyfile certfile cafile fullchain
opengear_deploy() {
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

  # Load config: env vars take precedence over previously saved values.
  _getdeployconf OPENGEAR_USER
  _getdeployconf OPENGEAR_HOST

  _debug2 OPENGEAR_USER "$OPENGEAR_USER"
  _debug2 OPENGEAR_HOST "$OPENGEAR_HOST"

  if [ -z "$OPENGEAR_HOST" ]; then
    _info "OPENGEAR_HOST not set, defaulting to domain $_cdomain"
    OPENGEAR_HOST="$_cdomain"
  fi
  if [ -z "$OPENGEAR_USER" ]; then
    _err "OPENGEAR_USER is not set. Please export OPENGEAR_USER before deploying."
    return 1
  fi

  _info "Deploying certificate to $OPENGEAR_USER@$OPENGEAR_HOST"

  # base64 encode the material locally; the Opengear CLI expects the PEM data
  # as a single base64 string. _base64 (openssl) replaces the GNU-only
  # "base64 -w0".
  _og_cert="$(_base64 <"$_cfullchain")"
  _og_key="$(_base64 <"$_ckey")"

  # ogconfig-cli lives in a different path on Operations Manager vs Lighthouse,
  # so try the standard path first and fall back to the unsupported one.
  _og_config="set services.https.certificate =$_og_cert\nset services.https.private_key =$_og_key\npush"
  _cmdstr="sudo printf '%b\\n' \"$_og_config\" | /usr/bin/ogconfig-cli || \
           sudo printf '%b\\n' \"$_og_config\" | /usr/unsupported/bin/ogconfig-cli"

  _info "Submitting new certificate to the appliance"
  if ! _ssh_remote_cmd "$_cmdstr"; then
    _err "Failed to deploy certificate to $OPENGEAR_HOST"
    return 1
  fi

  # Persist the config only after a successful deploy.
  _savedeployconf OPENGEAR_USER "$OPENGEAR_USER" 1
  _savedeployconf OPENGEAR_HOST "$OPENGEAR_HOST" 1

  _info "Certificate successfully deployed to $OPENGEAR_HOST"
  return 0
}

#cmd
_ssh_remote_cmd() {
  _cmd="$1"
  _secure_debug "Remote command to execute" "$_cmd"
  _info "Submitting sequence of commands to remote server by ssh"
  # quotations in the ssh command below are intended
  # shellcheck disable=SC2029
  $Le_Deploy_ssh_cmd "$OPENGEAR_USER@$OPENGEAR_HOST" sh -c "'$_cmd'"
  _err_code="$?"

  if [ "$_err_code" != "0" ]; then
    _err "Error code $_err_code returned from ssh"
  fi

  return $_err_code
}

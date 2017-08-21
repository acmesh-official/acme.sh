#!/usr/bin/env sh

##########################################################################
# This is a very simple deployment script to move certificates to a remote
# server. The deployment uses scp (the remote cp method of ssh) and simply
# drops certs into a target directory. Targets have the original scp format
# e.g. like:
#
#   server.com:/var/spool/acme.sh/certs/
#   user@server.com:/var/spool/acme.sh/certs/
#   configuredserver:/var/spool/acme.sh/certs/
#
# You may use something like "configuredserver" which is the name of a host
# configuration in the ~/.ssh/config file. If you have a more complex setup
# like different ports, identity files, users or hostnames you are strongly
# encouraged to use an entry in your ~/.ssh/config file. This saves this
# little script from reimplementing every possible scp switch.
#
# You might wanto to configure ssh on the target server to use a special
# account with key based authentication and allow scp only. Have a further
# look at the rssh shell to allow scp only. You might as well put the user
# into a chroot.
#
# The main reason for this form of deployment is, that the acme.sh script
# can run in a safe and controlled environment. The acme.sh script needs
# detailed and sensitive information e.g. like your acme private keys or
# your dns providers credentials. Information like this you certainly don't
# want to have lying around on your public webserver.
#
# Further deployment of the certificates should be handled by a cron job on
# the remote server. That remote script could then move the new cert's to
# their proper position, set file owner and permissions and restart the
# belonging service.
#
# An example script for apache (on debian systems) might be:
#
#    #!/usr/bin/env sh
#    chown root:root /var/spool/acme.sh/certs/*
#    mv /var/spool/acme.sh/certs/* /etc/apache2/ssl.crt/
#    systemctl restart apache2
#
# To avoid misunderstandings, this script is NOT like other deployment
# scripts that target a specific type of server (apache/cyrus/exim/...)
# and do all ssl configuration for you. With this script YOU do all your
# ssl configuration on your target server yourself. Then, and only after
# the target server is properly configured, you use this script to deploy
# the forthcoming LE certificates.

# When called for the first time use the following env vars to setup the
# configuration. The vars will be stored on a per domain basis.
#DEPLOY_SCP_CA_TARGET="user@server.com:/etc/apache2/ssl.crt"
#DEPLOY_SCP_KEY_TARGET="user@server.com:/etc/apache2/ssl.key"
#DEPLOY_SCP_CERT_TARGET="user@server.com:/etc/apache2/ssl.crt"
#DEPLOY_SCP_FULLCHAIN_TARGET="user@server.com:/etc/apache2/ssl.crt"

########  public functions #####################

#domain keyfile certfile cafile fullchain
scp_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _SCP_check_params
  if [ "$?" -ne 0 ]; then
    _err "Please specify at least one scp target. For instance:"
    _info "DEPLOY_SCP_CERT_TARGET=\"user@server.com:/etc/apache2/ssl.crt\""
    _info "The target directory has to be writable by the user."
    _info "See the header of this script for more information."
    return 1
  fi

  _debug _cdomain "$_cdomain"
  _debug _cca "$_cca"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cfullchain "$_cfullchain"

  if [ ! -z "$DEPLOY_SCP_CA_TARGET" ]; then
    scp "$_cca" "$DEPLOY_SCP_CA_TARGET"
    if [ "$?" -ne 0 ]; then
      _err "scp copy to server failed"
      return 1
    fi
  fi

  if [ ! -z "$DEPLOY_SCP_KEY_TARGET" ]; then
    scp "$_ckey" "$DEPLOY_SCP_KEY_TARGET"
    if [ "$?" -ne 0 ]; then
      _err "scp copy to server failed"
      return 1
    fi
  fi

  if [ ! -z "$DEPLOY_SCP_CERT_TARGET" ]; then
    scp "$_ccert" "$DEPLOY_SCP_CERT_TARGET"
    if [ "$?" -ne 0 ]; then
      _err "scp copy to server failed"
      return 1
    fi
  fi

  if [ ! -z "$DEPLOY_SCP_FULLCHAIN_TARGET" ]; then
    scp "$_cfullchain" "$DEPLOY_SCP_FULLCHAIN_TARGET"
    if [ "$?" -ne 0 ]; then
      _err "scp copy to server failed"
      return 1
    fi
  fi

  return 0
}

####################  private functions below ##################################

_SCP_check_params() {
  # at least one of key, cert or fullchain must be set
  if [ -z "$DEPLOY_SCP_KEY_TARGET" ] && [ -z "$DEPLOY_SCP_CERT_TARGET" ] && [ -z "$DEPLOY_SCP_FULLCHAIN_TARGET " ]; then
    DEPLOY_SCP_CA_TARGET=""
    DEPLOY_SCP_KEY_TARGET=""
    DEPLOY_SCP_CERT_TARGET=""
    DEPLOY_SCP_FULLCHAIN_TARGET=""
    return 1
  fi

  if [ ! -z "$DEPLOY_SCP_CA_TARGET" ]; then
    _savedomainconf DEPLOY_SCP_CA_TARGET "${DEPLOY_SCP_CA_TARGET}"
  fi

  if [ ! -z "$DEPLOY_SCP_KEY_TARGET" ]; then
    _savedomainconf DEPLOY_SCP_KEY_TARGET "${DEPLOY_SCP_KEY_TARGET}"
  fi

  if [ ! -z "$DEPLOY_SCP_CERT_TARGET" ]; then
    _savedomainconf DEPLOY_SCP_CERT_TARGET "${DEPLOY_SCP_CERT_TARGET}"
  fi

  if [ ! -z "$DEPLOY_SCP_FULLCHAIN_TARGET" ]; then
    _savedomainconf DEPLOY_SCP_FULLCHAIN_TARGET "${DEPLOY_SCP_FULLCHAIN_TARGET}"
  fi

  return 0
}

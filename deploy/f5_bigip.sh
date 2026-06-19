#!/usr/bin/env sh
# Deployment script for F5 BIGIP
#
# IDNs are currently not supported (Only domain names that follow the [A-Za-z][0-9]()*+,-:;<=>?@[]^_|~. regex are supported)
#
# As ClientSSL profiles do not support * in their names, domain names with wildcards are replaced with a _ character, which can result in a conflict if a domain name similar to _.example.com is used
# however you can set a custom ClientSSL profile name to workaround this issue or use a regular subdomain as CN with wildcard or _ as alternative name
#
# All of the environment variables are optional
# DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE_DISABLE = yes/no - Whether to create ClientSSL profile or just install the cert/key/chain into certificate store (defaults to: no)
# (this also means that everytime a new cert/key/chain is generated you will have to add it manually to a clientssl profile)
# DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE - Changes the name of the ClientSSL profile. The limit is 255 chars (imposed by bigip itself) (defaults to: SSL-ACME-${domain})
# DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE_SETTINGS - allows you to change the ClientSSL profile settings (defaults to: cipher-group f5-secure ciphers none options {no-tlsv1 no-tlsv1.1 dont-insert-empty-fragments})
# DEPLOY_F5_BIGIP_BACKUP = yes/no - Whether to keep 2 cert/key/chain combos (the installed one and a backup) at all times or delete the previously installed ones straight away (defaults to: yes)

f5_bigip_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cfullchain "$_cfullchain"

  _domain="$(echo "${_cdomain}" | sed 's/\*/_/g')"

  _getdeployconf DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE_DISABLE

  if [ -z "${DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE_DISABLE}" ]; then
    DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE_DISABLE="no"
  elif [ "${DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE_DISABLE}" != "yes" ] && [ "${DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE_DISABLE}" != "no" ]; then
    _err "DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE_DISABLE can only contain yes or no"
    return 1
  fi

  _savedeployconf DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE_DISABLE "${DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE_DISABLE}"

  if [ "${DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE_DISABLE}" = "no" ]; then
    _getdeployconf DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE
    _getdeployconf DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE_SETTINGS

    if [ -z "${DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE}" ]; then
      DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE="SSL-ACME-${_domain}"
    fi

    # Since the path length limit is 255 and we are using the /Common/ partition, the length of SSL profile can only be 247 (including) (255 - 8)
    if [ ${#DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE} -gt 247 ]; then
      _err "The maximum Client SSL profile name length is 247"
      return 1
    fi

    if [ -z "${DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE_SETTINGS}" ]; then
      DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE_SETTINGS="cipher-group f5-secure ciphers none options {no-tlsv1 no-tlsv1.1 dont-insert-empty-fragments}"
    fi

    _savedeployconf DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE "${DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE}"
    _savedeployconf DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE_SETTINGS "${DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE_SETTINGS}"
  fi

  _getdeployconf DEPLOY_F5_BIGIP_BACKUP

  if [ -z "$DEPLOY_F5_BIGIP_BACKUP" ]; then
    DEPLOY_F5_BIGIP_BACKUP="yes"
  elif [ "${DEPLOY_F5_BIGIP_BACKUP}" != "yes" ] && [ "${DEPLOY_F5_BIGIP_BACKUP}" != "no" ]; then
    _err "DEPLOY_F5_BIGIP_BACKUP can only contain yes or no"
    return 1
  fi

  _savedeployconf DEPLOY_F5_BIGIP_BACKUP "$DEPLOY_F5_BIGIP_BACKUP"

  TMSH_CMD=$(command -v tmsh)
  f5_bigip_tmsh
}

f5_bigip_tmsh() {
  _now=$(date -u +%Y-%m-%d)
  _next_cert="${_domain}-cert-${_now}"
  _next_key="${_domain}-key-${_now}"
  _next_chain="${_domain}-chain-${_now}"

  if [ "${DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE_DISABLE}" = "no" ]; then
    _current_cert=$(tmsh list ltm profile client-ssl "${DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE}" cert 2>/dev/null | grep cert | awk '{print $2}')
    _current_key=$(tmsh list ltm profile client-ssl "${DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE}" key 2>/dev/null | grep key | awk '{print $2}')
    _current_chain=$(tmsh list ltm profile client-ssl "${DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE}" chain 2>/dev/null | grep chain | awk '{print $2}')
  fi

  _info "Installing new cert/key/chain into store"
  ${TMSH_CMD} install sys crypto cert "${_next_cert}" from-local-file "${_ccert}"
  ${TMSH_CMD} install sys crypto key "${_next_key}" from-local-file "${_ckey}"
  ${TMSH_CMD} install sys crypto cert "${_next_chain}" from-local-file "${_cfullchain}"

  if [ "${DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE_DISABLE}" = "no" ]; then
    _info "Cleaning up old cert/key/chain from the store"
    f5_bigip_cleanup "cert" "cert" "${_current_cert}"
    f5_bigip_cleanup "key" "key" "${_current_key}"
    f5_bigip_cleanup "cert" "chain" "${_current_chain}"

    if [ -z "$(${TMSH_CMD} list ltm profile client-ssl "${DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE}" 2>/dev/null)" ]; then
      _info "Creating new ${DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE} ClientSSL profile"
      # This has to be disabled because of ${DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE_SETTINGS}, otherwise it will throw an unknown property error
      # shellcheck disable=SC2086
      ${TMSH_CMD} create ltm profile client-ssl "${DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE}" \
        cert-key-chain add "{" ACME "{" cert "${_next_cert}" key "${_next_key}" chain "${_next_chain}" "}" "}" \
        ${DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE_SETTINGS}
    else
      _info "Updating ${DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE} ClientSSL profile with new cert/key/chain"
      ${TMSH_CMD} modify ltm profile client-ssl "${DEPLOY_F5_BIGIP_CLIENT_SSL_PROFILE}" \
        cert-key-chain replace-all-with "{" ACME "{" cert "${_next_cert}" key "${_next_key}" chain "${_next_chain}" "}" "}"
    fi
  fi
  ${TMSH_CMD} save sys config
}

f5_bigip_cleanup() {
  _cert_mgmt_type=$1
  _cert_type=$2
  _current=$3

  if [ -n "$_current" ]; then
    if [ "$DEPLOY_F5_BIGIP_BACKUP" = "yes" ]; then
      # Backup enabled leave 1 previous type as backup and delete everything older than it
      _old_date_list=$(${TMSH_CMD} list sys crypto "${_cert_mgmt_type}" | grep "${_domain}"-"${_cert_type}" | awk '{print $4}' | awk -F'-' '{print $(NF-2) "-" $(NF-1) "-" $NF}' | sort -r | tail -n +3)
      if [ -n "${_old_date_list}" ]; then
        echo "${_old_date_list}" | while IFS= read -r _old_date; do
          _old_name="${_domain}-${_cert_type}-${_old_date}"
          _debug "Deleting ${_cert_mgmt_type} ${_old_name}"
          ${TMSH_CMD} delete sys crypto "${_cert_mgmt_type}" "${_old_name}"
        done
      fi
    else
      # Backup disabled, remove current type
      _debug "Deleting ${_cert_mgmt_type} ${_current}"
      ${TMSH_CMD} delete sys crypto "${_cert_mgmt_type}" "${_current}"
    fi
  fi
}

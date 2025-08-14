#!/usr/bin/env sh

# Script for acme.sh to deploy certificates to haproxy
#
# The following variables can be exported:
#
# export DEPLOY_HAPROXY_PEM_NAME="${domain}.pem"
#
# Defines the name of the PEM file.
# Defaults to "<domain>.pem"
#
# export DEPLOY_HAPROXY_PEM_PATH="/etc/haproxy"
#
# Defines location of PEM file for HAProxy.
# Defaults to /etc/haproxy
#
# export DEPLOY_HAPROXY_RELOAD="systemctl reload haproxy"
#
# OPTIONAL: Reload command used post deploy
# This defaults to be a no-op (ie "true").
# It is strongly recommended to set this something that makes sense
# for your distro.
#
# export DEPLOY_HAPROXY_ISSUER="no"
#
# OPTIONAL: Places CA file as "${DEPLOY_HAPROXY_PEM}.issuer"
# Note: Required for OCSP stapling to work
#
# export DEPLOY_HAPROXY_BUNDLE="no"
#
# OPTIONAL: Deploy this certificate as part of a multi-cert bundle
# This adds a suffix to the certificate based on the certificate type
# eg RSA certificates will have .rsa as a suffix to the file name
# HAProxy will load all certificates and provide one or the other
# depending on client capabilities
# Note: This functionality requires HAProxy was compiled against
# a version of OpenSSL that supports this.
#
# export DEPLOY_HAPROXY_HOT_UPDATE="yes"
# export DEPLOY_HAPROXY_STATS_SOCKET="UNIX:/run/haproxy/admin.sock"
#
# OPTIONAL: Deploy the certificate over the HAProxy stats socket without
# needing to reload HAProxy. Default is "no".
#
# Require the socat binary. DEPLOY_HAPROXY_STATS_SOCKET variable uses the socat
# address format.
#
# export DEPLOY_HAPROXY_MASTER_CLI="UNIX:/run/haproxy-master.sock"
#
# OPTIONAL: To use the master CLI with DEPLOY_HAPROXY_HOT_UPDATE="yes" instead
# of a stats socket, use this variable.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
haproxy_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"
  _cmdpfx=""

  # Some defaults
  DEPLOY_HAPROXY_PEM_PATH_DEFAULT="/etc/haproxy"
  DEPLOY_HAPROXY_PEM_NAME_DEFAULT="${_cdomain}.pem"
  DEPLOY_HAPROXY_BUNDLE_DEFAULT="no"
  DEPLOY_HAPROXY_ISSUER_DEFAULT="no"
  DEPLOY_HAPROXY_RELOAD_DEFAULT="true"
  DEPLOY_HAPROXY_HOT_UPDATE_DEFAULT="no"
  DEPLOY_HAPROXY_STATS_SOCKET_DEFAULT="UNIX:/run/haproxy/admin.sock"

  _debug _cdomain "${_cdomain}"
  _debug _ckey "${_ckey}"
  _debug _ccert "${_ccert}"
  _debug _cca "${_cca}"
  _debug _cfullchain "${_cfullchain}"

  # PEM_PATH is optional. If not provided then assume "${DEPLOY_HAPROXY_PEM_PATH_DEFAULT}"
  _getdeployconf DEPLOY_HAPROXY_PEM_PATH
  _debug2 DEPLOY_HAPROXY_PEM_PATH "${DEPLOY_HAPROXY_PEM_PATH}"
  if [ -n "${DEPLOY_HAPROXY_PEM_PATH}" ]; then
    Le_Deploy_haproxy_pem_path="${DEPLOY_HAPROXY_PEM_PATH}"
    _savedomainconf Le_Deploy_haproxy_pem_path "${Le_Deploy_haproxy_pem_path}"
  elif [ -z "${Le_Deploy_haproxy_pem_path}" ]; then
    Le_Deploy_haproxy_pem_path="${DEPLOY_HAPROXY_PEM_PATH_DEFAULT}"
  fi

  # Ensure PEM_PATH exists
  if [ -d "${Le_Deploy_haproxy_pem_path}" ]; then
    _debug "PEM_PATH ${Le_Deploy_haproxy_pem_path} exists"
  else
    _err "PEM_PATH ${Le_Deploy_haproxy_pem_path} does not exist"
    return 1
  fi

  # PEM_NAME is optional. If not provided then assume "${DEPLOY_HAPROXY_PEM_NAME_DEFAULT}"
  _getdeployconf DEPLOY_HAPROXY_PEM_NAME
  _debug2 DEPLOY_HAPROXY_PEM_NAME "${DEPLOY_HAPROXY_PEM_NAME}"
  if [ -n "${DEPLOY_HAPROXY_PEM_NAME}" ]; then
    Le_Deploy_haproxy_pem_name="${DEPLOY_HAPROXY_PEM_NAME}"
    _savedomainconf Le_Deploy_haproxy_pem_name "${Le_Deploy_haproxy_pem_name}"
  elif [ -z "${Le_Deploy_haproxy_pem_name}" ]; then
    Le_Deploy_haproxy_pem_name="${DEPLOY_HAPROXY_PEM_NAME_DEFAULT}"
    # We better not have '*' as the first character
    if [ "${Le_Deploy_haproxy_pem_name%%"${Le_Deploy_haproxy_pem_name#?}"}" = '*' ]; then
      # removes the first characters and add a _ instead
      Le_Deploy_haproxy_pem_name="_${Le_Deploy_haproxy_pem_name#?}"
    fi
  fi

  # BUNDLE is optional. If not provided then assume "${DEPLOY_HAPROXY_BUNDLE_DEFAULT}"
  _getdeployconf DEPLOY_HAPROXY_BUNDLE
  _debug2 DEPLOY_HAPROXY_BUNDLE "${DEPLOY_HAPROXY_BUNDLE}"
  if [ -n "${DEPLOY_HAPROXY_BUNDLE}" ]; then
    Le_Deploy_haproxy_bundle="${DEPLOY_HAPROXY_BUNDLE}"
    _savedomainconf Le_Deploy_haproxy_bundle "${Le_Deploy_haproxy_bundle}"
  elif [ -z "${Le_Deploy_haproxy_bundle}" ]; then
    Le_Deploy_haproxy_bundle="${DEPLOY_HAPROXY_BUNDLE_DEFAULT}"
  fi

  # ISSUER is optional. If not provided then assume "${DEPLOY_HAPROXY_ISSUER_DEFAULT}"
  _getdeployconf DEPLOY_HAPROXY_ISSUER
  _debug2 DEPLOY_HAPROXY_ISSUER "${DEPLOY_HAPROXY_ISSUER}"
  if [ -n "${DEPLOY_HAPROXY_ISSUER}" ]; then
    Le_Deploy_haproxy_issuer="${DEPLOY_HAPROXY_ISSUER}"
    _savedomainconf Le_Deploy_haproxy_issuer "${Le_Deploy_haproxy_issuer}"
  elif [ -z "${Le_Deploy_haproxy_issuer}" ]; then
    Le_Deploy_haproxy_issuer="${DEPLOY_HAPROXY_ISSUER_DEFAULT}"
  fi

  # RELOAD is optional. If not provided then assume "${DEPLOY_HAPROXY_RELOAD_DEFAULT}"
  _getdeployconf DEPLOY_HAPROXY_RELOAD
  _debug2 DEPLOY_HAPROXY_RELOAD "${DEPLOY_HAPROXY_RELOAD}"
  if [ -n "${DEPLOY_HAPROXY_RELOAD}" ]; then
    Le_Deploy_haproxy_reload="${DEPLOY_HAPROXY_RELOAD}"
    _savedomainconf Le_Deploy_haproxy_reload "${Le_Deploy_haproxy_reload}"
  elif [ -z "${Le_Deploy_haproxy_reload}" ]; then
    Le_Deploy_haproxy_reload="${DEPLOY_HAPROXY_RELOAD_DEFAULT}"
  fi

  # HOT_UPDATE is optional. If not provided then assume "${DEPLOY_HAPROXY_HOT_UPDATE_DEFAULT}"
  _getdeployconf DEPLOY_HAPROXY_HOT_UPDATE
  _debug2 DEPLOY_HAPROXY_HOT_UPDATE "${DEPLOY_HAPROXY_HOT_UPDATE}"
  if [ -n "${DEPLOY_HAPROXY_HOT_UPDATE}" ]; then
    Le_Deploy_haproxy_hot_update="${DEPLOY_HAPROXY_HOT_UPDATE}"
    _savedomainconf Le_Deploy_haproxy_hot_update "${Le_Deploy_haproxy_hot_update}"
  elif [ -z "${Le_Deploy_haproxy_hot_update}" ]; then
    Le_Deploy_haproxy_hot_update="${DEPLOY_HAPROXY_HOT_UPDATE_DEFAULT}"
  fi

  # STATS_SOCKET is optional. If not provided then assume "${DEPLOY_HAPROXY_STATS_SOCKET_DEFAULT}"
  _getdeployconf DEPLOY_HAPROXY_STATS_SOCKET
  _debug2 DEPLOY_HAPROXY_STATS_SOCKET "${DEPLOY_HAPROXY_STATS_SOCKET}"
  if [ -n "${DEPLOY_HAPROXY_STATS_SOCKET}" ]; then
    Le_Deploy_haproxy_stats_socket="${DEPLOY_HAPROXY_STATS_SOCKET}"
    _savedomainconf Le_Deploy_haproxy_stats_socket "${Le_Deploy_haproxy_stats_socket}"
  elif [ -z "${Le_Deploy_haproxy_stats_socket}" ]; then
    Le_Deploy_haproxy_stats_socket="${DEPLOY_HAPROXY_STATS_SOCKET_DEFAULT}"
  fi

  # MASTER_CLI is optional. No defaults are used. When the master CLI is used,
  # all commands are sent with a prefix.
  _getdeployconf DEPLOY_HAPROXY_MASTER_CLI
  _debug2 DEPLOY_HAPROXY_MASTER_CLI "${DEPLOY_HAPROXY_MASTER_CLI}"
  if [ -n "${DEPLOY_HAPROXY_MASTER_CLI}" ]; then
    Le_Deploy_haproxy_stats_socket="${DEPLOY_HAPROXY_MASTER_CLI}"
    _savedomainconf Le_Deploy_haproxy_stats_socket "${Le_Deploy_haproxy_stats_socket}"
    _cmdpfx="@1 " # command prefix used for master CLI only.
  fi

  # Set the suffix depending if we are creating a bundle or not
  if [ "${Le_Deploy_haproxy_bundle}" = "yes" ]; then
    _info "Bundle creation requested"
    # Initialise $Le_Keylength if its not already set
    if [ -z "${Le_Keylength}" ]; then
      Le_Keylength=""
    fi
    if _isEccKey "${Le_Keylength}"; then
      _info "ECC key type detected"
      _suffix=".ecdsa"
    else
      _info "RSA key type detected"
      _suffix=".rsa"
    fi
  else
    _suffix=""
  fi
  _debug _suffix "${_suffix}"

  # Set variables for later
  _pem="${Le_Deploy_haproxy_pem_path}/${Le_Deploy_haproxy_pem_name}${_suffix}"
  _issuer="${_pem}.issuer"
  _ocsp="${_pem}.ocsp"
  _reload="${Le_Deploy_haproxy_reload}"
  _statssock="${Le_Deploy_haproxy_stats_socket}"

  _info "Deploying PEM file"
  # Create a temporary PEM file
  _temppem="$(_mktemp)"
  _debug _temppem "${_temppem}"
  cat "${_ccert}" "${_cca}" "${_ckey}" | grep . >"${_temppem}"
  _ret="$?"

  # Check that we could create the temporary file
  if [ "${_ret}" != "0" ]; then
    _err "Error code ${_ret} returned during PEM file creation"
    [ -f "${_temppem}" ] && rm -f "${_temppem}"
    return ${_ret}
  fi

  # Move PEM file into place
  _info "Moving new certificate into place"
  _debug _pem "${_pem}"
  cat "${_temppem}" >"${_pem}"
  _ret=$?

  # Clean up temp file
  [ -f "${_temppem}" ] && rm -f "${_temppem}"

  # Deal with any failure of moving PEM file into place
  if [ "${_ret}" != "0" ]; then
    _err "Error code ${_ret} returned while moving new certificate into place"
    return ${_ret}
  fi

  # Update .issuer file if requested
  if [ "${Le_Deploy_haproxy_issuer}" = "yes" ]; then
    _info "Updating .issuer file"
    _debug _issuer "${_issuer}"
    cat "${_cca}" >"${_issuer}"
    _ret="$?"

    if [ "${_ret}" != "0" ]; then
      _err "Error code ${_ret} returned while copying issuer/CA certificate into place"
      return ${_ret}
    fi
  else
    [ -f "${_issuer}" ] && _err "Issuer file update not requested but .issuer file exists"
  fi

  # Update .ocsp file if certificate was requested with --ocsp/--ocsp-must-staple option
  if [ -z "${Le_OCSP_Staple}" ]; then
    Le_OCSP_Staple="0"
  fi
  if [ "${Le_OCSP_Staple}" = "1" ]; then
    _info "Updating OCSP stapling info"
    _debug _ocsp "${_ocsp}"
    _info "Extracting OCSP URL"
    _ocsp_url=$(${ACME_OPENSSL_BIN:-openssl} x509 -noout -ocsp_uri -in "${_pem}")
    _debug _ocsp_url "${_ocsp_url}"

    # Only process OCSP if URL was present
    if [ "${_ocsp_url}" != "" ]; then
      # Extract the hostname from the OCSP URL
      _info "Extracting OCSP URL"
      _ocsp_host=$(echo "${_ocsp_url}" | cut -d/ -f3)
      _debug _ocsp_host "${_ocsp_host}"

      # Only process the certificate if we have a .issuer file
      if [ -r "${_issuer}" ]; then
        # Check if issuer cert is also a root CA cert
        _subjectdn=$(${ACME_OPENSSL_BIN:-openssl} x509 -in "${_issuer}" -subject -noout | cut -d'/' -f2,3,4,5,6,7,8,9,10)
        _debug _subjectdn "${_subjectdn}"
        _issuerdn=$(${ACME_OPENSSL_BIN:-openssl} x509 -in "${_issuer}" -issuer -noout | cut -d'/' -f2,3,4,5,6,7,8,9,10)
        _debug _issuerdn "${_issuerdn}"
        _info "Requesting OCSP response"
        # If the issuer is a CA cert then our command line has "-CAfile" added
        if [ "${_subjectdn}" = "${_issuerdn}" ]; then
          _cafile_argument="-CAfile \"${_issuer}\""
        else
          _cafile_argument=""
        fi
        _debug _cafile_argument "${_cafile_argument}"
        # if OpenSSL/LibreSSL is v1.1 or above, the format for the -header option has changed
        _openssl_version=$(${ACME_OPENSSL_BIN:-openssl} version | cut -d' ' -f2)
        _debug _openssl_version "${_openssl_version}"
        _openssl_major=$(echo "${_openssl_version}" | cut -d '.' -f1)
        _openssl_minor=$(echo "${_openssl_version}" | cut -d '.' -f2)
        if [ "${_openssl_major}" -eq "1" ] && [ "${_openssl_minor}" -ge "1" ] || [ "${_openssl_major}" -ge "2" ]; then
          _header_sep="="
        else
          _header_sep=" "
        fi
        # Request the OCSP response from the issuer and store it
        _openssl_ocsp_cmd="${ACME_OPENSSL_BIN:-openssl} ocsp \
          -issuer \"${_issuer}\" \
          -cert \"${_pem}\" \
          -url \"${_ocsp_url}\" \
          -header Host${_header_sep}\"${_ocsp_host}\" \
          -respout \"${_ocsp}\" \
          -verify_other \"${_issuer}\" \
          ${_cafile_argument} \
          | grep -q \"${_pem}: good\""
        _debug _openssl_ocsp_cmd "${_openssl_ocsp_cmd}"
        eval "${_openssl_ocsp_cmd}"
        _ret=$?
      else
        # Non fatal: No issuer file was present so no OCSP stapling file created
        _err "OCSP stapling in use but no .issuer file was present"
      fi
    else
      # Non fatal: No OCSP url was found int the certificate
      _err "OCSP update requested but no OCSP URL was found in certificate"
    fi

    # Non fatal: Check return code of openssl command
    if [ "${_ret}" != "0" ]; then
      _err "Updating OCSP stapling failed with return code ${_ret}"
    fi
  else
    # An OCSP file was already present but certificate did not have OCSP extension
    if [ -f "${_ocsp}" ]; then
      _err "OCSP was not requested but .ocsp file exists."
      # Could remove the file at this step, although HAProxy just ignores it in this case
      # rm -f "${_ocsp}" || _err "Problem removing stale .ocsp file"
    fi
  fi

  if [ "${Le_Deploy_haproxy_hot_update}" = "yes" ]; then
    # set the socket name for messages
    if [ -n "${_cmdpfx}" ]; then
      _socketname="master CLI"
    else
      _socketname="stats socket"
    fi

    # Update certificate over HAProxy stats socket or master CLI.
    if _exists socat; then
      # look for the certificate on the stats socket, to chose between updating or creating one
      _socat_cert_cmd="echo '${_cmdpfx}show ssl cert' | socat '${_statssock}' - | grep -q '^${_pem}$'"
      _debug _socat_cert_cmd "${_socat_cert_cmd}"
      eval "${_socat_cert_cmd}"
      _ret=$?
      if [ "${_ret}" != "0" ]; then
        _newcert="1"
        _info "Creating new certificate '${_pem}' over HAProxy ${_socketname}."
        # certificate wasn't found, it's a new one. We should check if the crt-list exists and creates/inserts the certificate.
        _socat_crtlist_show_cmd="echo '${_cmdpfx}show ssl crt-list' | socat '${_statssock}' - | grep -q '^${Le_Deploy_haproxy_pem_path}$'"
        _debug _socat_crtlist_show_cmd "${_socat_crtlist_show_cmd}"
        eval "${_socat_crtlist_show_cmd}"
        _ret=$?
        if [ "${_ret}" != "0" ]; then
          _err "Couldn't find '${Le_Deploy_haproxy_pem_path}' in haproxy 'show ssl crt-list'"
          return "${_ret}"
        fi
        # create a new certificate
        _socat_new_cmd="echo '${_cmdpfx}new ssl cert ${_pem}' | socat '${_statssock}' - | grep -q 'New empty'"
        _debug _socat_new_cmd "${_socat_new_cmd}"
        eval "${_socat_new_cmd}"
        _ret=$?
        if [ "${_ret}" != "0" ]; then
          _err "Couldn't create '${_pem}' in haproxy"
          return "${_ret}"
        fi
      else
        _info "Update existing certificate '${_pem}' over HAProxy ${_socketname}."
      fi
      _socat_cert_set_cmd="echo -e '${_cmdpfx}set ssl cert ${_pem} <<\n$(cat "${_pem}")\n' | socat '${_statssock}' - | grep -q 'Transaction created'"
      _secure_debug _socat_cert_set_cmd "${_socat_cert_set_cmd}"
      eval "${_socat_cert_set_cmd}"
      _ret=$?
      if [ "${_ret}" != "0" ]; then
        _err "Can't update '${_pem}' in haproxy"
        return "${_ret}"
      fi
      _socat_cert_commit_cmd="echo '${_cmdpfx}commit ssl cert ${_pem}' | socat '${_statssock}' - | grep -q '^Success!$'"
      _debug _socat_cert_commit_cmd "${_socat_cert_commit_cmd}"
      eval "${_socat_cert_commit_cmd}"
      _ret=$?
      if [ "${_ret}" != "0" ]; then
        _err "Can't commit '${_pem}' in haproxy"
        return ${_ret}
      fi
      if [ "${_newcert}" = "1" ]; then
        # if this is a new certificate, it needs to be inserted into the crt-list`
        _socat_cert_add_cmd="echo '${_cmdpfx}add ssl crt-list ${Le_Deploy_haproxy_pem_path} ${_pem}' | socat '${_statssock}' - | grep -q 'Success!'"
        _debug _socat_cert_add_cmd "${_socat_cert_add_cmd}"
        eval "${_socat_cert_add_cmd}"
        _ret=$?
        if [ "${_ret}" != "0" ]; then
          _err "Can't update '${_pem}' in haproxy"
          return "${_ret}"
        fi
      fi
    else
      _err "'socat' is not available, couldn't update over ${_socketname}"
    fi
  else
    # Reload HAProxy
    _debug _reload "${_reload}"
    eval "${_reload}"
    _ret=$?
    if [ "${_ret}" != "0" ]; then
      _err "Error code ${_ret} during reload"
      return ${_ret}
    else
      _info "Reload successful"
    fi
  fi

  return 0
}

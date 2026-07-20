#!/usr/bin/env sh

#Here is a sample custom api script.
#This file name is "myapi.sh"
#So, here must be a method   myapi_deploy()
#Which will be called by acme.sh to deploy the cert
#returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
strongswan_deploy() {
  _cdomain="${1}"
  _ckey="${2}"
  _ccert="${3}"
  _cca="${4}"
  _cfullchain="${5}"
  _info "Using strongswan"
  if _exists ipsec; then
    _ipsec=ipsec
  elif _exists strongswan; then
    _ipsec=strongswan
  fi
  if _exists swanctl; then
    _swanctl=swanctl
  fi
  # For legacy stroke mode
  if [ -n "${_ipsec}" ]; then
    _info "${_ipsec} command detected"
    _confdir=$(${_ipsec} --confdir)
    if [ -z "${_confdir}" ]; then
      _err "no strongswan --confdir is detected"
      return 1
    fi
    _info _confdir "${_confdir}"
    __deploy_cert "stroke" "${_confdir}" "$@"
    ${_ipsec} reload
  fi
  # For modern vici mode
  if [ -n "${_swanctl}" ]; then
    _info "${_swanctl} command detected"
    for _dir in /usr/local/etc/swanctl /etc/swanctl /etc/strongswan/swanctl; do
      if [ -d ${_dir} ]; then
        _confdir=${_dir}
        _info _confdir "${_confdir}"
        break
      fi
    done
    if [ -z "${_confdir}" ]; then
      _err "no swanctl config dir is found"
      return 1
    fi
    __deploy_cert "vici" "${_confdir}" "$@"
    ${_swanctl} --load-creds
  fi
  if [ -z "${_swanctl}" ] && [ -z "${_ipsec}" ]; then
    _err "no strongswan or ipsec command is detected"
    _err "no swanctl is detected"
    return 1
  fi
}

####################  Private functions below ##################################

__deploy_cert() {
  _swan_mode="${1}"
  _confdir="${2}"
  _cdomain="${3}"
  _ckey="${4}"
  _ccert="${5}"
  _cca="${6}"
  _cfullchain="${7}"
  _debug _cdomain "${_cdomain}"
  _debug _ckey "${_ckey}"
  _debug _ccert "${_ccert}"
  _debug _cca "${_cca}"
  _debug _cfullchain "${_cfullchain}"
  _debug _swan_mode "${_swan_mode}"
  _debug _confdir "${_confdir}"
  if [ "${_swan_mode}" = "vici" ]; then
    _dir_private="private"
    _dir_cert="x509"
    _dir_ca="x509ca"
  elif [ "${_swan_mode}" = "stroke" ]; then
    _dir_private="ipsec.d/private"
    _dir_cert="ipsec.d/certs"
    _dir_ca="ipsec.d/cacerts"
  else
    _err "unknown StrongSwan mode ${_swan_mode}"
    return 1
  fi
  cat "${_ckey}" >"${_confdir}/${_dir_private}/$(basename "${_ckey}")"
  cat "${_ccert}" >"${_confdir}/${_dir_cert}/$(basename "${_ccert}")"
  cat "${_cca}" >"${_confdir}/${_dir_ca}/$(basename "${_cca}")"
  if [ "${_swan_mode}" = "stroke" ]; then
    cat "${_cfullchain}" >"${_confdir}/${_dir_ca}/$(basename "${_cfullchain}")"
  fi
}

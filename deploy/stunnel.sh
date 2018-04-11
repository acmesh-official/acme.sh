#!/usr/bin/env sh

#Here is a sample custom api script.
#This file name is "stunnel.sh"
#So, here must be a method   stunnel_deploy()
#Which will be called by acme.sh to deploy the cert
#returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
stunnel_deploy() {
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

  ST_DIR="/etc/stunnel"
  _debug STUNNEL "$ST_DIR"
  _debug STUNNEL_CRT "$ST_DIR/stunnel.crt"
  _debug STUNNEL_KEY "$ST_DIR/stunnel.key"

  if [ ! -d "$ST_DIR" ]
  then
    _info "Creating the stunnel directory..."
    mkdir -p "$ST_DIR" || return 1
  fi

  if [ ! -f "$ST_DIR/stunnel.dh" ]
  then
    _info "Generating the Diffie-Hellman key..."
    openssl gendh 2048 > "$ST_DIR/stunnel.dh"
  fi
  
  _info "Saving the certificate..."
  cat "$_cfullchain" "$ST_DIR/stunnel.dh" > "$ST_DIR/stunnel.crt"

  if [ ! -f "$ST_DIR/stunnel.key" ]
  then
    _info "Saving the key..."
    cat "$_ckey" > "$ST_DIR/stunnel.key"
  fi

  _info "Setting file permissions..."
  chmod 600 "$ST_DIR/stunnel.crt" "$ST_DIR/stunnel.key" "$ST_DIR/stunnel.dh"
  chown nobody:root "$ST_DIR/stunnel.crt" "$ST_DIR/stunnel.key" "$ST_DIR/stunnel.dh"

  return 0
}

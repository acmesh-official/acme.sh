#!/usr/bin/bash
# Deploy hook to copy server certificate and key to kvmd user directory then restart.
# Some deployment notes:
# While looking for how the GL.iNet KVM software does certificates,
# I found something interesting...
# /etc/kvmd/nginx/certbot.ctx-server.conf ->
# location /.well-known/acme-challenge {
#	root /run/kvmd-certbot/webroot;
#	include /etc/kvmd/nginx/loc-nocache.conf;
#	auth_request off;
# }
# It looks like they were going to have an ACME client at some point,
# but either that isn't done yet or it got scrapped.
# Either way, they left that config there. So, running the following command...
# /root/.acme.sh/acme.sh -d <domain> --webroot /run/kvmd-certbot/webroot/ --issue --home /root/.acme.sh/
# meant that I was able to get a certificate straight away.
#
# And updating the certificates for the frontend was as simple as
# putting the certificates in /etc/kvmd/user/ssl
# as server.crt and server.key, and then running...
# /etc/init.d/S99kvmd-nginx restart
# The frontend restarted with shiny brand new certificates!

glinet_kvmd_deploy() {
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

  cp "$_cfullchain" /etc/kvmd/user/ssl/server.crt
  cp "$_ckey" /etc/kvmd/user/ssl/server.key
  /etc/init.d/S99kvmd-nginx restart
}

#!/usr/bin/env sh

#Here is the script to deploy the cert to your cpanel account by the cpanel APIs.

#returns 0 means success, otherwise error.

#export DEPLOY_CPANEL_USER=myusername
#export DEPLOY_CPANEL_PASSWORD=PASSWORD
#export DEPLOY_CPANEL_HOSTNAME=localhost:2083

########  Public functions #####################

#domain keyfile certfile cafile fullchain
cpanel_deploy() {
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

export _ckey _ccert _cdomain
# PHP code taken from https://documentation.cpanel.net/display/DD/Tutorial+-+Call+UAPI's+SSL::install_ssl+Function+in+Custom+Code
php <<'END'
<?php
// Log everything during development.
// If you run this on the CLI, set 'display_errors = On' in php.ini.
error_reporting(E_ALL);

// Authentication information.
$username = getenv('DEPLOY_CPANEL_USER');
$password = getenv('DEPLOY_CPANEL_PASSWORD');
$hostname = getenv('DEPLOY_CPANEL_HOSTNAME');

// The URL for the SSL::install_ssl UAPI function.
$request = "https://".$hostname."/execute/SSL/install_ssl";

// Read in the SSL certificate and key file.
$cert = getenv('_ccert');
$key = getenv('_ckey');

// Set up the payload to send to the server.
$domain = getenv('_cdomain');
$payload = array(
    'domain' => "$domain",
    'cert'   => file_get_contents($cert),
    'key'    => file_get_contents($key)
);

// Set up the cURL request object.
$ch = curl_init( $request );
curl_setopt( $ch, CURLOPT_HTTPAUTH, CURLAUTH_BASIC );
curl_setopt( $ch, CURLOPT_USERPWD, $username . ':' . $password );
curl_setopt( $ch, CURLOPT_SSL_VERIFYHOST, false );
curl_setopt( $ch, CURLOPT_SSL_VERIFYPEER, false );

// Set up a POST request with the payload.
curl_setopt( $ch, CURLOPT_POST, true );
curl_setopt( $ch, CURLOPT_POSTFIELDS, $payload );
curl_setopt( $ch, CURLOPT_RETURNTRANSFER, true );

// Make the call, and then terminate the cURL caller object.
$curl_response = curl_exec( $ch );
curl_close( $ch );

// Decode and validate output.
$response = json_decode( $curl_response );
if( empty( $response ) ) {
    echo "The cURL call did not return valid JSON:\n";
    die( $response );
} elseif ( !$response->status ) {
    echo "The cURL call returned valid JSON, but reported errors:\n";
    die( $response->errors[0] . "\n" );
}

// Print and exit.
die( print_r( $response ) );

END

}

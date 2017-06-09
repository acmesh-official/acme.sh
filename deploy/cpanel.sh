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
# Perl code taken from https://documentation.cpanel.net/display/SDK/Tutorial+-+Call+UAPI%27s+SSL%3A%3Ainstall_ssl+Function+in+Custom+Code
perl -f <<'END'
# Return errors if Perl experiences problems.
use strict;
use warnings;
# Allow my code to perform web requests.
use LWP::UserAgent;
use LWP::Protocol::https;
# Use the correct encoding to prevent wide character warnings.
use Encode;
use utf8;
# Properly decode JSON.
use JSON;
# Function properly with Base64 authentication headers.
use MIME::Base64;

# Authentication information.
my $username = $ENV{'DEPLOY_CPANEL_USER'};
my $password = $ENV{'DEPLOY_CPANEL_PASSWORD'};
my $hostname = $ENV{'DEPLOY_CPANEL_HOSTNAME'};

# The URL for the SSL::install_ssl UAPI function.
my $request = "https://".$hostname."/execute/SSL/install_ssl";

# Required to allow HTTPS connections to unsigned services.
# Services on localhost are always unsigned.
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

# Create a useragent object.
my $ua = LWP::UserAgent->new();

# Add authentication headers.
$ua->default_header(
    'Authorization' => 'Basic ' . MIME::Base64::encode("$username:$password"),
);

# Read in the SSL certificate and key file.
my $cert = $ENV{'_ccert'};
my $key = $ENV{'_ckey'};
{
    local $/;
    open ( my $fh, '<', $cert );
    $cert = <$fh>;
    close $fh;

    open ( $fh, '<', $key );
    $key = <$fh>;
    close $fh;
}

my $domain = $ENV{'_cdomain'};

# Make the call.
my $response = $ua->post($request,
    Content_Type => 'form-data',
    Content => [
        domain => $domain,
        cert   => $cert,
        key    => $key,
    ],
);

# Create an object to decode the JSON.
# Sorted by keys and pretty-printed.
my $json_printer = JSON->new->pretty->canonical(1);

# UTF-8 encode before decoding to avoid wide character warnings.
my $content = JSON::decode_json(Encode::encode_utf8($response->decoded_content));

# Print output, UTF-8 encoded to avoid wide character warnings.
print Encode::encode_utf8($json_printer->encode($content));

=pod
{
   "data" : {
      "action" : "none",
      "aliases" : [
         "mail.example.com"
      ],
      "cert_id" : "example_com_xxx_yyy_zzzzzzzzzzzzzzzzzz",
      "domain" : "example.com",
      "extra_certificate_domains" : [],
      "html" : "<br /><b>This certificate was already installed on this host. The system made no changes.</b><br />\n",
      "ip" : "127.0.0.1",
      "key_id" : "xxx_yyy_zzzzzzzzzzzzzzzz",
      "message" : "This certificate was already installed on this host. The system made no changes.",
      "servername" : "example.com",
      "status" : 1,
      "statusmsg" : "This certificate was already installed on this host. The system made no changes.",
      "user" : "username",
      "warning_domains" : [
         "mail.example.com"
      ],
      "working_domains" : [
         "example.com"
      ]
   },
   "errors" : null,
   "messages" : [
      "The certificate was successfully installed on the domain “example.com”."
   ],
   "metadata" : {},
   "status" : 1
}
=cut

END

}


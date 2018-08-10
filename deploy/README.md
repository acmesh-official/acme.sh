# Using deploy api

Before you can deploy your cert, you must [issue the cert first](https://github.com/Neilpang/acme.sh/wiki/How-to-issue-a-cert).

Here are the scripts to deploy the certs/key to the server/services.

## 1. Deploy the certs to your cpanel host

If you want to deploy using cpanel UAPI see 7.

(cpanel deploy hook is not finished yet, this is just an example.)



Then you can deploy now:

```sh
export DEPLOY_CPANEL_USER=myusername
export DEPLOY_CPANEL_PASSWORD=PASSWORD
acme.sh --deploy -d example.com --deploy-hook cpanel
```

## 2. Deploy ssl cert on kong proxy engine based on api

Before you can deploy your cert, you must [issue the cert first](https://github.com/Neilpang/acme.sh/wiki/How-to-issue-a-cert).
Currently supports Kong-v0.10.x.

```sh
acme.sh --deploy -d ftp.example.com --deploy-hook kong
```

## 3. Deploy the cert to remote server through SSH access

The ssh deploy plugin allows you to deploy certificates to a remote host
using SSH command to connect to the remote server.  The ssh plugin is invoked
with the following command...

```sh
acme.sh --deploy -d example.com --deploy-hook ssh
```
Prior to running this for the first time you must tell the plugin where
and how to deploy the certificates.  This is done by exporting the following
environment variables.  This is not required for subsequent runs as the
values are stored by acme.sh in the domain configuration files.

Required...
```
export DEPLOY_SSH_USER=username
```
Optional...
```
export DEPLOY_SSH_CMD=custom ssh command
export DEPLOY_SSH_SERVER=url or ip address of remote host
export DEPLOY_SSH_KEYFILE=filename for private key
export DEPLOY_SSH_CERTFILE=filename for certificate file
export DEPLOY_SSH_CAFILE=filename for intermediate CA file
export DEPLOY_SSH_FULLCHAIN=filename for fullchain file
export DEPLOY_SSH_REMOTE_CMD=command to execute on remote host
export DEPLOY_SSH_BACKUP=yes or no
```

**DEPLOY_SSH_USER**
Username at the remote host that SSH will login with. Note that
SSH must be able to login to remote host without a password... SSH Keys
must have been exchanged with the remote host. Validate and test that you
can login to USER@URL from the host running acme.sh before using this script.

The USER@URL at the remote server must also have has permissions to write to
the target location of the certificate files and to execute any commands
(e.g. to stop/start services).

**DEPLOY_SSH_CMD**
You can customize the ssh command used to connect to the remote host. For example
if you need to connect to a specific port at the remote server you can set this
to, for example, "ssh -p 22" or to use `sshpass` to provide password inline
instead of exchanging ssh keys (this is not recommended, using keys is
more secure).

**DEPLOY_SSH_SERVER**
URL or IP Address of the remote server.  If not provided then the domain
name provided on the acme.sh --deploy command line is used.

**DEPLOY_SSH_KEYFILE**
Target filename for the private key issued by LetsEncrypt.

**DEPLOY_SSH_CERTFILE**
Target filename for the certificate issued by LetsEncrypt.
If this is the same as the previous filename (for keyfile) then it is
appended to the same file.

**DEPLOY_SSH_CAFILE**
Target filename for the CA intermediate certificate issued by LetsEncrypt.
If this is the same as a previous filename (for keyfile or certfile) then
it is appended to the same file.

**DEPLOY_SSH_FULLCHAIN**
Target filename for the fullchain certificate issued by LetsEncrypt.
If this is the same as a previous filename (for keyfile, certfile or
cafile) then it is appended to the same file.

**DEPLOY_SSH_REMOTE_CMD**
Command to execute on the remote server after copying any certificates.  This
could be any additional command required for example to stop and restart
the service.

**DEPLOY_SSH_BACKUP**
Before writing a certificate file to the remote server the existing
certificate will be copied to a backup directory on the remote server.
These are placed in a hidden directory in the home directory of the SSH
user
```sh
~/.acme_ssh_deploy/[domain name]-backup-[timestamp]
```
Any backups older than 180 days will be deleted when new certificates
are deployed.  This defaults to "yes" set to "no" to disable backup.

###Examples using SSH deploy
The following example illustrates deploying certificates to a QNAP NAS
(tested with QTS version 4.2.3)

```sh
export DEPLOY_SSH_USER="admin"
export DEPLOY_SSH_KEYFILE="/etc/stunnel/stunnel.pem"
export DEPLOY_SSH_CERTFILE="/etc/stunnel/stunnel.pem"
export DEPLOY_SSH_CAFILE="/etc/stunnel/uca.pem"
export DEPLOY_SSH_REMOTE_CMD="/etc/init.d/stunnel.sh restart"

acme.sh --deploy -d qnap.example.com --deploy-hook ssh
```
Note how in this example both the private key and certificate point to
the same file.  This will result in the certificate being appended
to the same file as the private key... a common requirement of several
services.

The next example illustrates deploying certificates to a Unifi
Controller (tested with version 5.4.11).

```sh
export DEPLOY_SSH_USER="root"
export DEPLOY_SSH_KEYFILE="/var/lib/unifi/unifi.example.com.key"
export DEPLOY_SSH_FULLCHAIN="/var/lib/unifi/unifi.example.com.cer"
export DEPLOY_SSH_REMOTE_CMD="openssl pkcs12 -export \
   -inkey /var/lib/unifi/unifi.example.com.key \
   -in /var/lib/unifi/unifi.example.com.cer \
   -out /var/lib/unifi/unifi.example.com.p12 \
   -name ubnt -password pass:temppass \
 && keytool -importkeystore -deststorepass aircontrolenterprise \
   -destkeypass aircontrolenterprise \
   -destkeystore /var/lib/unifi/keystore \
   -srckeystore /var/lib/unifi/unifi.example.com.p12 \
   -srcstoretype PKCS12 -srcstorepass temppass -alias ubnt -noprompt \
 && service unifi restart"

acme.sh --deploy -d unifi.example.com --deploy-hook ssh
```
In this example we execute several commands on the remote host
after the certificate files have been copied... to generate a pkcs12 file
compatible with Unifi, to import it into the Unifi keystore and then finally
to restart the service.

Note also that once the certificate is imported
into the keystore the individual certificate files are no longer
required. We could if we desired delete those files immediately. If we
do that then we should disable backup at the remote host (as there are
no files to backup -- they were erased during deployment). For example...
```sh
export DEPLOY_SSH_BACKUP=no
# modify the end of the remote command...
&& rm /var/lib/unifi/unifi.example.com.key \
      /var/lib/unifi/unifi.example.com.cer \
      /var/lib/unifi/unifi.example.com.p12 \
&& service unifi restart
```

## 4. Deploy the cert to local vsftpd server

```sh
acme.sh --deploy -d ftp.example.com --deploy-hook vsftpd
```

The default vsftpd conf file is `/etc/vsftpd.conf`,  if your vsftpd conf is not in the default location, you can specify one:

```sh
export DEPLOY_VSFTPD_CONF="/etc/vsftpd.conf"

acme.sh --deploy -d ftp.example.com --deploy-hook vsftpd
```

The default command to restart vsftpd server is `service vsftpd restart`, if it doesn't work, you can specify one:

```sh
export DEPLOY_VSFTPD_RELOAD="/etc/init.d/vsftpd restart"

acme.sh --deploy -d ftp.example.com --deploy-hook vsftpd
```

## 5. Deploy the cert to local exim4 server

```sh
acme.sh --deploy -d ftp.example.com --deploy-hook exim4
```

The default exim4 conf file is `/etc/exim/exim.conf`,  if your exim4 conf is not in the default location, you can specify one:

```sh
export DEPLOY_EXIM4_CONF="/etc/exim4/exim4.conf.template"

acme.sh --deploy -d ftp.example.com --deploy-hook exim4
```

The default command to restart exim4 server is `service exim4 restart`, if it doesn't work, you can specify one:

```sh
export DEPLOY_EXIM4_RELOAD="/etc/init.d/exim4 restart"

acme.sh --deploy -d ftp.example.com --deploy-hook exim4
```

## 6. Deploy the cert to OSX Keychain

```sh
acme.sh --deploy -d ftp.example.com --deploy-hook keychain
```

## 7. Deploy to cpanel host using UAPI

This hook is using UAPI and works in cPanel & WHM version 56 or newer.
```
acme.sh  --deploy  -d example.com  --deploy-hook cpanel_uapi
```
DEPLOY_CPANEL_USER is required only if you run the script as root and it should contain cpanel username.
```sh
export DEPLOY_CPANEL_USER=username
acme.sh  --deploy  -d example.com  --deploy-hook cpanel_uapi
```
Please note, that the cpanel_uapi hook will deploy only the first domain when your certificate will automatically renew. Therefore you should issue a separate certificate for each domain. 

## 8. Deploy the cert to your FRITZ!Box router

You must specify the credentials that have administrative privileges on the FRITZ!Box in order to deploy the certificate, plus the URL of your FRITZ!Box, through the following environment variables:
```sh
$ export DEPLOY_FRITZBOX_USERNAME=my_username
$ export DEPLOY_FRITZBOX_PASSWORD=the_password
$ export DEPLOY_FRITZBOX_URL=https://fritzbox.example.com
```

After the first deployment, these values will be stored in your $HOME/.acme.sh/account.conf. You may now deploy the certificate like this:

```sh
acme.sh --deploy -d fritzbox.example.com --deploy-hook fritzbox
```

## 9. Deploy the cert to strongswan

```sh
acme.sh --deploy -d ftp.example.com --deploy-hook strongswan
```

## 10. Deploy the cert to HAProxy

You must specify the path where you want the concatenated key and certificate chain written.
```sh
export DEPLOY_HAPROXY_PEM_PATH=/etc/haproxy
```

You may optionally define the command to reload HAProxy. The value shown below will be used as the default if you don't set this environment variable.

```sh
export DEPLOY_HAPROXY_RELOAD="/usr/sbin/service haproxy restart"
```

You can then deploy the certificate as follows
```sh
acme.sh --deploy -d haproxy.example.com --deploy-hook haproxy
```

The path for the PEM file will be stored with the domain configuration and will be available when renewing, so that deploy will happen automatically when renewed.

## 11. Deploy the cert to AWS ACM

Ensure your access key owner or role has a polcy attached that allows the
actions `acm:ListCertificates` and `acm:ImportCertificate`. Role credentials
will be picked up automatically from EC2 instances and ECS containers, in other
cases you must set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in your
environment.

```sh
export AWS_ACM_REGIONS="us-east-1,us-west-2"

acme.sh --deploy -d ftp.example.com --deploy-hook aws_acm
```

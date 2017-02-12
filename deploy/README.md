# Using deploy api

Here are the scripts to deploy the certs/key to the server/services.

## 1. Deploy the certs to your cpanel host.

(cpanel deploy hook is not finished yet, this is just an example.)

Before you can deploy your cert, you must [issue the cert first](https://github.com/Neilpang/acme.sh/wiki/How-to-issue-a-cert).

Then you can deploy now:

```sh
export DEPLOY_CPANEL_USER=myusername
export DEPLOY_CPANEL_PASSWORD=PASSWORD
acme.sh --deploy -d example.com --deploy --deploy-hook cpanel
```

## 2. Deploy ssl cert on kong proxy engine based on api.

Before you can deploy your cert, you must [issue the cert first](https://github.com/Neilpang/acme.sh/wiki/How-to-issue-a-cert).

(TODO)

## 3. Deploy the cert to remote server through SSH access.

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
export ACME_DEPLOY_SSH_USER=username
```
Optional...
```
export ACME_DEPLOY_SSH_CMD=custom ssh command
export ACME_DEPLOY_SSH_SERVER=url or ip address of remote host
export ACME_DEPLOY_SSH_KEYFILE=filename for private key
export ACME_DEPLOY_SSH_CERTFILE=filename for certificate file
export ACME_DEPLOY_SSH_CAFILE=filename for intermediate CA file
export ACME_DEPLOY_SSH_FULLCHAIN=filename for fullchain file
export ACME_DEPLOY_SSH_REMOTE_CMD=command to execute on remote host
export ACME_DEPLOY_SSH_BACKUP=yes or no
```

**ACME_DEPLOY_SSH_USER**
Username at the remote host that SSH will login with. Note that
SSH must be able to login to remote host without a password... SSH Keys
must have been exchanged with the remote host. Validate and test that you
can login to USER@URL from the host running acme.sh before using this script.

The USER@URL at the remote server must also have has permissions to write to
the target location of the certificate files and to execute any commands
(e.g. to stop/start services).

**ACME_DEPLOY_SSH_CMD**
You can customize the ssh command used to connect to the remote host. For example
if you need to connect to a specific port at the remote server you can set this
to, for example, "ssh -p 22" or to use `sshpass` to provide password inline
instead of exchanging ssh keys (this is not recommended, using keys is
more secure).

**ACME_DEPLOY_SSH_SERVER**
URL or IP Address of the remote server.  If not provided then the domain
name provided on the acme.sh --deploy command line is used.

**ACME_DEPLOY_SSH_KEYFILE**
Target filename for the private key issued by LetsEncrypt.

**ACME_DEPLOY_SSH_CERTFILE**
Target filename for the certificate issued by LetsEncrypt.
If this is the same as the previous filename (for keyfile) then it is
appended to the same file.

**ACME_DEPLOY_SSH_CAFILE**
Target filename for the CA intermediate certificate issued by LetsEncrypt.
If this is the same as a previous filename (for keyfile or certfile) then
it is appended to the same file.

**ACME_DEPLOY_SSH_FULLCHAIN**
Target filename for the fullchain certificate issued by LetsEncrypt.
If this is the same as a previous filename (for keyfile, certfile or
cafile) then it is appended to the same file.

**ACME_DEPLOY_SSH_REMOTE_CMD**
Command to execute on the remote server after copying any certificates.  This
could be any additional command required for example to stop and restart
the service.

**ACME_DEPLOY_SSH_BACKUP**
Before writing a certificate file to the remote server the existing
certificate will be copied to a backup directory on the remote server.
These are placed in a hidden directory in the home directory of the SSH
user
```sh
~/.acme_ssh_deploy/[domain name]-backup-[timestamp]
```
Any backups older than 180 days will be deleted when new certificates
are deployed.  This defaults to "yes" set to "no" to disable backup.


###Eamples using SSH deploy
The following example illustrates deploying certifcates to a QNAP NAS
running QTS 4.2

```sh
export ACME_DEPLOY_SSH_USER="admin"
export ACME_DEPLOY_SSH_KEYFILE="/etc/stunnel/stunnel.pem"
export ACME_DEPLOY_SSH_CERTFILE="/etc/stunnel/stunnel.pem"
export ACME_DEPLOY_SSH_CAFILE="/etc/stunnel/uca.pem"
export ACME_DEPLOY_SSH_REMOTE_CMD="/etc/init.d/stunnel.sh restart"

acme.sh --deploy -d qnap.example.com --deploy-hook ssh
```

The next example illustates deploying certificates to a Unifi
Contolller (tested with version 5.4.11).

```sh
export ACME_DEPLOY_SSH_USER="root"
export ACME_DEPLOY_SSH_KEYFILE="/var/lib/unifi/unifi.example.com.key"
export ACME_DEPLOY_SSH_FULLCHAIN="/var/lib/unifi/unifi.example.com.cer"
export ACME_DEPLOY_SSH_REMOTE_CMD="openssl pkcs12 -export \
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
In this exmple we execute several commands on the remote host
after the certificate files have been copied... to generate a pkcs12 file
compatible with Unifi, to import it into the Unifi keystore and then finaly
to restart the service.

Note also that once the certificate is imported
into the keystore the individual certificate files are no longer
required. We could if we desired delete those files immediately. If we
do that then we should disable backup at the remote host (as there are
no files to backup -- they were erased during deployment). For example...
```sh
export ACME_DEPLOY_SSH_BACKUP=no
# modify the end of the remote command...
&& rm /var/lib/unifi/unifi.example.com.key \
      /var/lib/unifi/unifi.example.com.cer \
      /var/lib/unifi/unifi.example.com.p12 \
&& service unifi restart
```

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

```bash
acme.sh --deploy -d example.com --deploy-hook ssh
```
Prior to running this for the first time you must tell the plugin where
and how to deploy the certificates.  This is done by exporting the following
environment variables.  This is not required for subsequent runs as the
values are stored by acme.sh in the domain configuration files.

Required...
```bash
export ACME_DEPLOY_SSH_USER="admin"
```
Optional...
```bash
export ACME_DEPLOY_SSH_CMD=""
export ACME_DEPLOY_SSH_SERVER="qnap"
export ACME_DEPLOY_SSH_KEYFILE="/etc/stunnel/stunnel.pem"
export ACME_DEPLOY_SSH_CERTFILE="/etc/stunnel/stunnel.pem"
export ACME_DEPLOY_SSH_CAFILE="/etc/stunnel/uca.pem"
export ACME_DEPLOY_SSH_FULLCHAIN=""
export ACME_DEPLOY_SSH_REMOTE_CMD="/etc/init.d/stunnel.sh restart"
```
The values used above are illustrative only and represent those that could 
be used to deploy certificates to a QNAP NAS device running QTS 4.2

###ACME_DEPLOY_SSH_USER
Username at the remote host that SSH will login with. Note that
SSH must be able to login to remote host without a password... SSH Keys
must have been exchanged with the remote host. Validate and test that you
can login to USER@URL from the host running acme.sh before using this script.

The USER@URL at the remote server must also have has permissions to write to
the target location of the certificate files and to execute any commands
(e.g. to stop/start services).
###ACME_DEPLOY_SSH_CMD
You can customize the ssh command used to connect to the remote host. For example
if you need to connect to a specific port at the remote server you can set this
to, for example, "ssh -p 22"
###ACME_DEPLOY_SSH_SERVER
URL or IP Address of the remote server.  If not provided then the domain
name provided on the acme.sh --deploy command line is used.
###ACME_DEPLOY_SSH_KEYFILE
Target filename for the private key issued by LetsEncrypt.
###ACME_DEPLOY_SSH_CERTFILE
Target filename for the certificate issued by LetsEncrypt.  If this filename
is the same as that provided for ACME_DEPLOY_SSH_KEYFILE then this certificate
is appended to the same file as the private key.
###ACME_DEPLOY_SSH_CAFILE
Target filename for the CA intermediate certificate issued by LetsEncrypt.
If this is the same as a previous filename then it is appended to the same
file
###ACME_DEPLOY_SSH_FULLCHAIN
Target filename for the fullchain certificate issued by LetsEncrypt.
If this is the same as a previous filename then it is appended to the same
file
###ACME_DEPLOY_SSH_REMOTE_CMD
Command to execute on the remote server after copying any certificates.  This
could be any additional command required for example to stop and restart
the service.

###Backups
Before writing a certificate file to the remote server the existing
certificate will be copied to a backup directory on the remote server.
These are placed in a hidden directory in the home directory of the SSH
user
```bash
~/.acme_ssh_deploy/[domain name]-backup-[timestamp]
```
Any backups older than 180 days will be deleted when new certificates
are deployed.

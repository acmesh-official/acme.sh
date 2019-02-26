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

## 11. Deploy your cert to Gitlab pages

You must define the API key and the informations for the project and Gitlab page you are updating the certificate for.

```sh
# The token can be created in your user settings under "Access Tokens"
export GITLAB_TOKEN="xxxxxxxxxxx"

# The project ID is displayed on the home page of the project
export GITLAB_PROJECT_ID=12345678

# The domain must match the one defined for the Gitlab page, without "https://"
export GITLAB_DOMAIN="www.mydomain.com"
```

You can then deploy the certificate as follows

```sh
acme.sh --deploy -d www.mydomain.com --deploy-hook gitlab
```

## 12. Deploy your cert to Hashicorp Vault

```sh
export VAULT_PREFIX="acme"
```

You can then deploy the certificate as follows

```sh
acme.sh --deploy -d www.mydomain.com --deploy-hook vault_cli
```

Your certs will be saved in Vault using this structure:

```sh
vault write "${VAULT_PREFIX}/${domain}/cert.pem"      value=@"..."
vault write "${VAULT_PREFIX}/${domain}/cert.key"      value=@"..."
vault write "${VAULT_PREFIX}/${domain}/chain.pem"     value=@"..."
vault write "${VAULT_PREFIX}/${domain}/fullchain.pem" value=@"..."
```

You might be using Fabio load balancer (which can get certs from
Vault). It needs a bit different structure of your certs in Vault. It
gets certs only from keys that were saved in `prefix/domain`, like this:

```bash
vault write <PREFIX>/www.domain.com cert=@cert.pem key=@key.pem
```

If you want to save certs in Vault this way just set "FABIO" env
variable to anything (ex: "1") before running `acme.sh`:

```sh
export FABIO="1"
```

## 13. Deploy your certificate to Qiniu.com

使用 acme.sh 部署到七牛之前，需要确保部署的域名已打开 HTTPS 功能，您可以访问[融合 CDN - 域名管理](https://portal.qiniu.com/cdn/domain) 设置。
另外还需要先导出 AK/SK 环境变量，您可以访问[密钥管理](https://portal.qiniu.com/user/key) 获得。

```sh
$ export QINIU_AK="foo"
$ export QINIU_SK="bar"
```

完成准备工作之后，您就可以通过下面的命令开始部署 SSL 证书到七牛上：

```sh
$ acme.sh --deploy -d example.com --deploy-hook qiniu
```

假如您部署的证书为泛域名证书，您还需要设置 `QINIU_CDN_DOMAIN` 变量，指定实际需要部署的域名：

```sh
$ export QINIU_CDN_DOMAIN="cdn.example.com"
$ acme.sh --deploy -d example.com --deploy-hook qiniu
```

### English version

You should create AccessKey/SecretKey pair in https://portal.qiniu.com/user/key 
before deploying your certificate, and please ensure you have enabled HTTPS for
your domain name. You can enable it in https://portal.qiniu.com/cdn/domain.

```sh
$ export QINIU_AK="foo"
$ export QINIU_SK="bar"
```

then you can deploy certificate by following command:

```sh
$ acme.sh --deploy -d example.com --deploy-hook qiniu
```

(Optional), If you are using wildcard certificate,
you may need export `QINIU_CDN_DOMAIN` to specify which domain
you want to update:

```sh
$ export QINIU_CDN_DOMAIN="cdn.example.com"
$ acme.sh --deploy -d example.com --deploy-hook qiniu
```

## 14. Deploy your cert on MyDevil.net

Once you have acme.sh installed and certificate issued (see info in [DNS API](../dnsapi/README.md#61-use-mydevilnet)), you can install it by following command:

```sh
acme.sh --deploy --deploy-hook mydevil -d example.com
```

That will remove old certificate and install new one.

## 15. Deploy the cert to remote routeros

```sh
acme.sh --deploy -d ftp.example.com --deploy-hook routeros
```

Before you can deploy the certificate to router os, you need to add the id_rsa.pub key to the routeros and assign a user to that key.
The user need to have access to ssh, ftp, read and write.

There are no need to enable ftp service for the script to work, as they are transmitted over SCP, however ftp is needed to store the files on the router.

Then you need to set the environment variables for the deploy script to work.
```sh
export ROUTER_OS_USERNAME=certuser
export ROUTER_OS_HOST=router.example.com

acme.sh --deploy -d ftp.example.com --deploy-hook routeros
```

The deploy script will remove previously deployed certificates, and it does this with an assumption on how RouterOS names imported certificates, adding a "cer_0" suffix at the end. This is true for versions 6.32 -> 6.41.3, but it is not guaranteed that it will be true for future versions when upgrading.

If the router have other certificates with the same name as the one beeing deployed, then this script will remove those certificates.

At the end of the script, the services that use those certificates could be updated. Currently only the www-ssl service is beeing updated, but more services could be added.

For instance:
```
/ip service set www-ssl certificate=$_cdomain.cer_0
/ip service set api-ssl certificate=$_cdomain.cer_0
```

One optional thing to do as well is to create a script that updates all the required services and run that script in a single command.

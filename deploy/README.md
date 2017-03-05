# Using deploy api

Before you can deploy your cert, you must [issue the cert first](https://github.com/Neilpang/acme.sh/wiki/How-to-issue-a-cert).

Here are the scripts to deploy the certs/key to the server/services.

## 1. Deploy the certs to your cpanel host.

(cpanel deploy hook is not finished yet, this is just an example.)



Then you can deploy now:

```sh
export DEPLOY_CPANEL_USER=myusername
export DEPLOY_CPANEL_PASSWORD=PASSWORD
acme.sh --deploy -d example.com --deploy-hook cpanel
```

## 2. Deploy ssl cert on kong proxy engine based on api.

Before you can deploy your cert, you must [issue the cert first](https://github.com/Neilpang/acme.sh/wiki/How-to-issue-a-cert).

(TODO)

## 3. Deploy the cert to remote server through SSH access.

(TODO)

## 4. Deploy the cert to local vsftpd server.

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

## 5. Deploy the cert to local exim4 server.

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

## 6. Deploy the cert to remote routeros

```sh
acme.sh --deploy -d ftp.example.com --deploy-hook routeros
```

Before you can deploy the certificate to router os, you need to add the id_rsa.pub key to the routeros and assign a user to that key.
The user need to have access to ssh, ftp, read and write.

Then you need to set the environment variables for the deploy script to work.
```sh
export ROUTER_OS_USERNAME=certuser
export ROUTER_OS_HOST=router.example.com

acme.sh --deploy -d ftp.example.com --deploy-hook routeros
```

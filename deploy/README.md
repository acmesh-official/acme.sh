# Using deploy api

Before you can deploy your cert, you must [issue the cert first](https://github.com/Neilpang/acme.sh/wiki/How-to-issue-a-cert).

Here are the scripts to deploy the certs/key to the server/services.

## 1. Deploy the certs to your cpanel host.

If you want to deploy using cpanel UAPI see 7.

(cpanel deploy hook is not finished yet, this is just an example.)



Then you can deploy now:

```sh
export DEPLOY_CPANEL_USER=myusername
export DEPLOY_CPANEL_PASSWORD=PASSWORD
acme.sh --deploy -d example.com --deploy-hook cpanel
```

## 2. Deploy ssl cert on kong proxy engine based on api.

Before you can deploy your cert, you must [issue the cert first](https://github.com/Neilpang/acme.sh/wiki/How-to-issue-a-cert).
Currently supports Kong-v0.10.x.

```sh
acme.sh --deploy -d ftp.example.com --deploy-hook kong
```

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
Please note, that the cpanel_uapi hook will deploy only the first domain when your certificate will automatically renew. Therefore you should issue a separete certificate for each domain. 

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


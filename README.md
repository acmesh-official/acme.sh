# A acme Shell script: acme.sh
A acme protocol client in pure bash language.
Fully ACME protocol implementation. 
Simple, Powerful and very easy to use, you only need 3 minutes to learn.

Simplest shell script for LetsEncrypt free Certificate client
Pure written in bash, no dependencies to python or LetsEncrypt official client.
Just one script, to issue, renew your certificates automatically.

Probably it's the smallest&easiest&smartest shell script to automatically issue & renew the free certificates from LetsEncrypt.

NOT require to be `root/sudoer`.

Wiki: https://github.com/Neilpang/acme.sh/wiki

#Tested OS
1. Ubuntu [![](https://cdn.rawgit.com/Neilpang/letest/master/status/ubuntu-latest.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)
2. Debian [![](https://cdn.rawgit.com/Neilpang/letest/master/status/debian-latest.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)
3. CentOS [![](https://cdn.rawgit.com/Neilpang/letest/master/status/centos-latest.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)
4. Windows (cygwin with curl, openssl and crontab included) [![](https://cdn.rawgit.com/Neilpang/letest/master/status/windows.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)
5. FreeBSD with bash [![](https://cdn.rawgit.com/Neilpang/letest/master/status/freebsd.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)
6. pfsense with bash and curl
7. openSUSE [![](https://cdn.rawgit.com/Neilpang/letest/master/status/opensuse-latest.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)
8. Alpine Linux [![](https://cdn.rawgit.com/Neilpang/letest/master/status/alpine-latest.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status) (with bash, curl. https://github.com/Neilpang/le/issues/94)
9. Archlinux [![](https://cdn.rawgit.com/Neilpang/letest/master/status/base-archlinux.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)
10. fedora [![](https://cdn.rawgit.com/Neilpang/letest/master/status/fedora-latest.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)
11. Kali Linux [![](https://cdn.rawgit.com/Neilpang/letest/master/status/kalilinux-kali-linux-docker.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)
12. Oracle Linux [![](https://cdn.rawgit.com/Neilpang/letest/master/status/oraclelinux-latest.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)
13. Cloud Linux  https://github.com/Neilpang/le/issues/111
14. Proxmox https://pve.proxmox.com/wiki/HTTPSCertificateConfiguration#Let.27s_Encrypt_using_le.sh


For all the build status, check our daily build project: 

https://github.com/Neilpang/acmetest

#Supported Mode
1. Webroot mode
2. Standalone mode
3. Apache mode
4. Dns mode

# Upgrade from 1.x to 2.x
You can simply uninstall 1.x and re-install 2.x.
2.x is 100% compatible to 1.x.  You will feel nothing changed.

# le.sh renamed to acme.sh NOW!
All configurations are 100% compatible. You just need to uninstall `le.sh` and re-install `acme.sh` again.
Nothing broken.

#How to install

### 1. Install online:

Check this project:https://github.com/Neilpang/get.acme.sh

```
curl https://get.acme.sh | bash

```

Or:
```
wget -O -  https://get.acme.sh | bash

```


### 2. Or, Install from git:
Clone this project: 
```
git clone https://github.com/Neilpang/acme.sh.git
cd acme.sh
./acme.sh --install
```

You don't have to be root then, although it is recommended.

Which does 3 jobs:
* create and copy `acme.sh` to your home dir:  `~/.acme.sh/`
All the certs will be placed in this folder.
* create alias : `acme.sh=~/.acme.sh/acme.sh`. 
* create everyday cron job to check and renew the cert if needed.

After install, you must close current terminal and reopen again to make the alias take effect.

Ok, you are ready to issue cert now.
Show help message:
```
root@v1:~# acme.sh
https://github.com/Neilpang/acme.sh
v2.1.0
Usage: acme.sh  command ...[parameters]....
Commands:
  --help, -h               Show this help message.
  --version, -v            Show version info.
  --install                Install acme.sh to your system.
  --uninstall              Uninstall acme.sh, and uninstall the cron job.
  --issue                  Issue a cert.
  --installcert            Install the issued cert to apache/nginx or any other server.
  --renew, -r              Renew a cert.
  --renewAll               Renew all the certs
  --revoke                 Revoke a cert.
  --installcronjob         Install the cron job to renew certs, you don't need to call this. The 'install' command can automatically install the cron job.
  --uninstallcronjob       Uninstall the cron job. The 'uninstall' command can do this automatically.
  --cron                   Run cron job to renew all the certs.
  --toPkcs                 Export the certificate and key to a pfx file.
  --createAccountKey, -cak Create an account private key, professional use.
  --createDomainKey, -cdk  Create an domain private key, professional use.
  --createCSR, -ccsr       Create CSR , professional use.

Parameters:
  --domain, -d   domain.tld         Specifies a domain, used to issue, renew or revoke etc.
  --force, -f                       Used to force to install or force to renew a cert immediately.
  --staging, --test                 Use staging server, just for test.
  --debug                           Output debug info.

  --webroot, -w  /path/to/webroot   Specifies the web root folder for web root mode.
  --standalone                      Use standalone mode.
  --apache                          Use apache mode.
  --dns [dns-cf|dns-dp|dns-cx|/path/to/api/file]   Use dns mode or dns api.

  --keylength, -k [2048]            Specifies the domain key length: 2048, 3072, 4096, 8192 or ec-256, ec-384.
  --accountkeylength, -ak [2048]    Specifies the account key length.

  These parameters are to install the cert to nginx/apache or anyother server after issue/renew a cert:

  --certpath /path/to/real/cert/file  After issue/renew, the cert will be copied to this path.
  --keypath /path/to/real/key/file  After issue/renew, the key will be copied to this path.
  --capath /path/to/real/ca/file    After issue/renew, the intermediate cert will be copied to this path.
  --fullchainpath /path/to/fullchain/file After issue/renew, the fullchain cert will be copied to this path.

  --reloadcmd "service nginx reload" After issue/renew, it's used to reload the server.

  --accountconf                     Specifies a customized account config file.
  --home                            Specifies the home dir for acme.sh



```
 
# Just issue a cert:
Example 1:
Only one domain:
```
acme.sh --issue   -d aa.com  -w /home/wwwroot/aa.com   
```

Example 2:
Multiple domains in the same cert:

```
acme.sh --issue   -d aa.com   -d www.aa.com -d cp.aa.com  -w  /home/wwwroot/aa.com 
```

The parameter `/home/wwwroot/aa.com` is the web root folder, You must have `write` access to this folder.

Second argument "aa.com" is the main domain you want to issue cert for.
You must have at least domain there.

You must point and bind all the domains to the same webroot dir:`/home/wwwroot/aa.com`

The cert will be placed in `~/.acme.sh/aa.com/`

The issued cert will be renewed every 80 days automatically.


More examples: https://github.com/Neilpang/acme.sh/wiki/How-to-issue-a-cert


# Install issued cert to apache/nginx etc.
After you issue a cert, you probably want to install the cert to your nginx/apache or other servers to use.

```
acme.sh --installcert  -d aa.com \
--certpath /path/to/certfile/in/apache/nginx  \
--keypath  /path/to/keyfile/in/apache/nginx  \
--capath   /path/to/ca/certfile/apache/nginx   \
--fullchainpath path/to/fullchain/certfile/apache/nginx \
--reloadcmd  "service apache2|nginx reload"
```

Only the domain is required, all the other parameters are optional.

Install the issued cert/key to the production apache or nginx path.

The cert will be renewed every 80 days by default (which is configurable), Once the cert is renewed, the apache/nginx will be automatically reloaded by the command: `service apache2 reload` or `service nginx reload`


# Use Standalone server to issue cert 
(requires you be root/sudoer, or you have permission to listen tcp 80 port):
Same usage as all above,  just give `no` as the webroot.
The tcp `80` port must be free to listen, otherwise you will be prompted to free the `80` port and try again.

```
acme.sh --issue  --standalone    -d aa.com  -d www.aa.com  -d  cp.aa.com
```

More examples: https://github.com/Neilpang/acme.sh/wiki/How-to-issue-a-cert


# Use Apache mode 
(requires you be root/sudoer, since it is required to interact with apache server):
If you are running a web server, apache or nginx, it is recommended to use the Webroot mode.
Particularly,  if you are running an apache server, you can use apache mode instead. Which doesn't write any file to your web root folder.

Just set string "apache" to the first argument, it will use apache plugin automatically.

```
acme.sh  --issue  --apache  -d aa.com   -d www.aa.com -d user.aa.com
```

More examples: https://github.com/Neilpang/acme.sh/wiki/How-to-issue-a-cert


# Use DNS mode:
Support the dns-01 challenge.

```
acme.sh  --issue   --dns   -d aa.com  -d www.aa.com -d user.aa.com
```

You will get the output like bellow:
```
Add the following txt record:
Domain:_acme-challenge.aa.com
Txt value:9ihDbjYfTExAYeDs4DBUeuTo18KBzwvTEjUnSwd32-c

Add the following txt record:
Domain:_acme-challenge.www.aa.com
Txt value:9ihDbjxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Please add those txt records to the domains. Waiting for the dns to take effect.

Then just retry with 'renew' command:

```
acme.sh --renew  -d aa.com
```

Ok, it's finished.


#Automatic dns api integeration

If your dns provider supports api access, we can use api to automatically issue certs.
You don't have do anything manually.

###Currently we support:

1. Cloudflare.com api
2. Dnspod.cn api
3. Cloudxns.com api
4. AWS Route 53, see: https://github.com/Neilpang/acme.sh/issues/65

More apis are coming soon....

If your dns provider is not in the supported list above, you can write your own script api easily.

For more details: [How to use dns api](dnsapi)


# Issue ECC certificate:
LetsEncrypt now can issue ECDSA certificate.
And we also support it.

Just set the `length` parameter with a prefix `ec-`.
For example:

Single domain:
```
acme.sh --issue  -w /home/wwwroot/aa.com   -d aa.com   --keylength  ec-256
```

SAN multiple domains:
```
acme.sh --issue  -w /home/wwwroot/aa.com   -d aa.com  -d www.aa.com  --keylength  ec-256
```

Please look at the last parameter above.

Valid values are:

1. ec-256 (prime256v1,  "ECDSA P-256")
2. ec-384 (secp384r1,   "ECDSA P-384")
3. ec-521 (secp521r1,   "ECDSA P-521", which is not supported by letsencrypt yet.)



#Under the Hood

Speak ACME language with bash directly to Let's encrypt.

TODO:


#Acknowledgment
1. Acme-tiny: https://github.com/diafygi/acme-tiny
2. ACME protocol: https://github.com/ietf-wg-acme/acme
3. letsencrypt: https://github.com/letsencrypt/letsencrypt



#License & Other

License is GPLv3

Please Star and Fork me.

Issues and pull requests are welcomed.




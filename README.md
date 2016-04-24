# An ACME Shell script: acme.sh
- An ACME protocol client written purely in Shell (Unix shell) language.
- Fully ACME protocol implementation.
- Simple, powerful and very easy to use. You only need 3 minutes to learn.
- Bash, dash and sh compatible. 
- Simplest shell script for Let's Encrypt free certificate client.
- Purely written in Shell with no dependencies on python or Let's Encrypt official client.
- Just one script, to issue, renew and install your certificates automatically.
- DOES NOT require `root/sudoer` access.

It's probably the `easiest&smallest&smartest` shell script to automatically issue & renew the free certificates from Let's Encrypt.


Wiki: https://github.com/Neilpang/acme.sh/wiki

#Tested OS
| NO | Status| Platform|
|----|-------|---------|
|1|[![](https://cdn.rawgit.com/Neilpang/letest/master/status/ubuntu-latest.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)| Ubuntu
|2|[![](https://cdn.rawgit.com/Neilpang/letest/master/status/debian-latest.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)| Debian
|3|[![](https://cdn.rawgit.com/Neilpang/letest/master/status/centos-latest.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|CentOS
|4|[![](https://cdn.rawgit.com/Neilpang/letest/master/status/windows.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|Windows (cygwin with curl, openssl and crontab included)
|5|[![](https://cdn.rawgit.com/Neilpang/letest/master/status/freebsd.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|FreeBSD
|6|[![](https://cdn.rawgit.com/Neilpang/letest/master/status/pfsense.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|pfsense
|7|[![](https://cdn.rawgit.com/Neilpang/letest/master/status/opensuse-latest.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|openSUSE
|8|[![](https://cdn.rawgit.com/Neilpang/letest/master/status/alpine-latest.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|Alpine Linux (with curl)
|9|[![](https://cdn.rawgit.com/Neilpang/letest/master/status/base-archlinux.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|Archlinux
|10|[![](https://cdn.rawgit.com/Neilpang/letest/master/status/fedora-latest.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|fedora
|11|[![](https://cdn.rawgit.com/Neilpang/letest/master/status/kalilinux-kali-linux-docker.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|Kali Linux
|12|[![](https://cdn.rawgit.com/Neilpang/letest/master/status/oraclelinux-latest.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|Oracle Linux
|13|[![](https://cdn.rawgit.com/Neilpang/letest/master/status/proxmox.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)| Proxmox https://pve.proxmox.com/wiki/HTTPSCertificateConfiguration#Let.27s_Encrypt_using_acme.sh
|14|-----| Cloud Linux  https://github.com/Neilpang/le/issues/111
|15|[![](https://cdn.rawgit.com/Neilpang/letest/master/status/openbsd.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|OpenBSD

For all build statuses, check our [daily build project](https://github.com/Neilpang/acmetest): 

https://github.com/Neilpang/acmetest

# Supported Mode

1. Webroot mode
2. Standalone mode
3. Apache mode
4. Dns mode

# Upgrade from 1.x to 2.x

You can simply uninstall 1.x and re-install 2.x.
2.x is 100% compatible to 1.x. You will feel right at home as if nothing has changed.

# le.sh renamed to acme.sh NOW!

All configurations are 100% compatible between `le.sh` and `acme.sh`. You just need to uninstall `le.sh` and re-install `acme.sh` again.
Nothing will be broken during the process.

# How to install

### 1. Install online:

Check this project:https://github.com/Neilpang/get.acme.sh

```bash
curl https://get.acme.sh | sh

```

Or:

```bash
wget -O -  https://get.acme.sh | sh

```


### 2. Or, Install from git:

Clone this project: 

```bash
git clone https://github.com/Neilpang/acme.sh.git
cd ./acme.sh
./acme.sh --install
```

You `don't have to be root` then, although `it is recommended`.

Advanced Installation:  https://github.com/Neilpang/acme.sh/wiki/How-to-install

The installer will perform 3 actions:

1. Create and copy `acme.sh` to your home dir (`$HOME`):  `~/.acme.sh/`.
All certs will be placed in this folder.
2. Create alia for: `acme.sh=~/.acme.sh/acme.sh`. 
3. Create everyday cron job to check and renew the cert if needed.

Cron entry example:

```bash
0 0 * * * "/home/user/.acme.sh"/acme.sh --cron --home "/home/user/.acme.sh" > /dev/null
```

After the installation, you must close current terminal and reopen again to make the alias take effect.

Ok, you are ready to issue cert now.
Show help message:

```
root@v1:~# acme.sh
https://github.com/Neilpang/acme.sh
v2.1.1
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
  --home                            Specifies the home dir for acme.sh .
  --certhome                        Specifies the home dir to save all the certs, only valid for '--install' command.
  --useragent                       Specifies the user agent string. it will be saved for future use too.
  --accountemail                    Specifies the account email for registering, Only valid for the '--install' command.
  --accountkey                      Specifies the account key path, Only valid for the '--install' command.
  --days                            Specifies the days to renew the cert when using '--issue' command. The max value is 80 days.

```
 
# Just issue a cert:

**Example 1:** Single domain.

```bash
acme.sh --issue -d aa.com -w /home/wwwroot/aa.com
```

**Example 2:** Multiple domains in the same cert.

```bash
acme.sh --issue -d aa.com -d www.aa.com -d cp.aa.com -w /home/wwwroot/aa.com 
```

The parameter `/home/wwwroot/aa.com` is the web root folder. You **MUST** have `write access` to this folder.

Second argument **"aa.com"** is the main domain you want to issue cert for.
You must have at least a domain there.

You must point and bind all the domains to the same webroot dir: `/home/wwwroot/aa.com`.

Generate/issued certs will be placed in `~/.acme.sh/aa.com/`

The issued cert will be renewed every 80 days automatically.

More examples: https://github.com/Neilpang/acme.sh/wiki/How-to-issue-a-cert


# Install issued cert to apache/nginx etc.

After you issue a cert, you probably want to install the cert with your nginx/apache or other servers you may be using.

```bash
acme.sh --installcert -d aa.com \
--certpath /path/to/certfile/in/apache/nginx  \
--keypath  /path/to/keyfile/in/apache/nginx  \
--capath   /path/to/ca/certfile/apache/nginx   \
--fullchainpath path/to/fullchain/certfile/apache/nginx \
--reloadcmd  "service apache2|nginx reload"
```

Only the domain is required, all the other parameters are optional.

Install the issued cert/key to the production apache or nginx path.

The cert will be `renewed every 80 days by default` (which is configurable). Once the cert is renewed, the apache/nginx will be automatically reloaded by the command: `service apache2 reload` or `service nginx reload`.

# Use Standalone server to issue cert

**(requires you be root/sudoer, or you have permission to listen tcp 80 port)**

Same usage as above, just give `no` as `--webroot` or `-w`.

The tcp `80` port **MUST** be free to listen, otherwise you will be prompted to free the `80` port and try again.

```bash
acme.sh --issue --standalone -d aa.com -d www.aa.com -d cp.aa.com
```

More examples: https://github.com/Neilpang/acme.sh/wiki/How-to-issue-a-cert

# Use Apache mode

**(requires you be root/sudoer, since it is required to interact with apache server)**

If you are running a web server, apache or nginx, it is recommended to use the `Webroot mode`.

Particularly, if you are running an apache server, you should use apache mode instead. This mode doesn't write any files to your web root folder.

Just set string "apache" as the second argument, it will force use of apache plugin automatically.

```
acme.sh --issue --apache -d aa.com -d www.aa.com -d user.aa.com
```

More examples: https://github.com/Neilpang/acme.sh/wiki/How-to-issue-a-cert

# Use DNS mode:

Support the `dns-01` challenge.

```bash
acme.sh --issue --dns -d aa.com -d www.aa.com -d user.aa.com
```

You should get the output like below:

```
Add the following txt record:
Domain:_acme-challenge.aa.com
Txt value:9ihDbjYfTExAYeDs4DBUeuTo18KBzwvTEjUnSwd32-c

Add the following txt record:
Domain:_acme-challenge.www.aa.com
Txt value:9ihDbjxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

Please add those txt records to the domains. Waiting for the dns to take effect.

```

Then just rerun with `renew` argument:

```bash
acme.sh --renew -d aa.com
```

Ok, it's finished.

# Automatic DNS API integration

If your DNS provider supports API access, we can use API to automatically issue the certs.

You don't have do anything manually!

### Currently acme.sh supports:

1. Cloudflare.com API
2. Dnspod.cn API
3. Cloudxns.com API
4. AWS Route 53, see: https://github.com/Neilpang/acme.sh/issues/65

##### More APIs are coming soon...

If your DNS provider is not on the supported list above, you can write your own script API easily. If you do please consider submitting a [Pull Request](https://github.com/Neilpang/acme.sh/pulls) and contribute to the project.

For more details: [How to use dns api](dnsapi)

# Issue ECC certificate:

`Let's Encrypt` now can issue **ECDSA** certificates.

And we also support it.

Just set the `length` parameter with a prefix `ec-`.

For example:

### Single domain ECC cerfiticate:

```bash
acme.sh --issue -w /home/wwwroot/aa.com -d aa.com --keylength  ec-256
```

SAN multi domain ECC certificate:

```bash
acme.sh --issue -w /home/wwwroot/aa.com -d aa.com -d www.aa.com --keylength  ec-256
```

Please look at the last parameter above.

Valid values are:

1. **ec-256 (prime256v1, "ECDSA P-256")**
2. **ec-384 (secp384r1,  "ECDSA P-384")**
3. **ec-521 (secp521r1,  "ECDSA P-521", which is not supported by Let's Encrypt yet.)**

# Under the Hood

Speak ACME language using shell, directly to "Let's Encrypt".

TODO:

# Acknowledgment
1. Acme-tiny: https://github.com/diafygi/acme-tiny
2. ACME protocol: https://github.com/ietf-wg-acme/acme
3. letsencrypt: https://github.com/letsencrypt/letsencrypt

# License & Other

License is GPLv3

Please Star and Fork me.

[Issues](https://github.com/Neilpang/acme.sh/issues) and [pull requests](https://github.com/Neilpang/acme.sh/pulls) are welcomed.




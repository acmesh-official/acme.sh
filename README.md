# An ACME Shell script: acme.sh [![Build Status](https://travis-ci.org/Neilpang/acme.sh.svg?branch=master)](https://travis-ci.org/Neilpang/acme.sh)
- An ACME protocol client written purely in Shell (Unix shell) language.
- Full ACME protocol implementation.
- Simple, powerful and very easy to use. You only need 3 minutes to learn it.
- Bash, dash and sh compatible.
- Simplest shell script for Let's Encrypt free certificate client.
- Purely written in Shell with no dependencies on python or the official Let's Encrypt client.
- Just one script to issue, renew and install your certificates automatically.
- DOES NOT require `root/sudoer` access.

It's probably the `easiest&smallest&smartest` shell script to automatically issue & renew the free certificates from Let's Encrypt.

Wiki: https://github.com/Neilpang/acme.sh/wiki


# [中文说明](https://github.com/Neilpang/acme.sh/wiki/%E8%AF%B4%E6%98%8E)


# Tested OS

| NO | Status| Platform|
|----|-------|---------|
|1|[![](https://cdn.rawgit.com/Neilpang/acmetest/master/status/ubuntu-latest.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)| Ubuntu
|2|[![](https://cdn.rawgit.com/Neilpang/acmetest/master/status/debian-latest.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)| Debian
|3|[![](https://cdn.rawgit.com/Neilpang/acmetest/master/status/centos-latest.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|CentOS
|4|[![](https://cdn.rawgit.com/Neilpang/acmetest/master/status/windows-cygwin.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|Windows (cygwin with curl, openssl and crontab included)
|5|[![](https://cdn.rawgit.com/Neilpang/acmetest/master/status/freebsd.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|FreeBSD
|6|[![](https://cdn.rawgit.com/Neilpang/acmetest/master/status/pfsense.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|pfsense
|7|[![](https://cdn.rawgit.com/Neilpang/acmetest/master/status/opensuse-latest.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|openSUSE
|8|[![](https://cdn.rawgit.com/Neilpang/acmetest/master/status/alpine-latest.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|Alpine Linux (with curl)
|9|[![](https://cdn.rawgit.com/Neilpang/acmetest/master/status/base-archlinux.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|Archlinux
|10|[![](https://cdn.rawgit.com/Neilpang/acmetest/master/status/fedora-latest.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|fedora
|11|[![](https://cdn.rawgit.com/Neilpang/acmetest/master/status/kalilinux-kali-linux-docker.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|Kali Linux
|12|[![](https://cdn.rawgit.com/Neilpang/acmetest/master/status/oraclelinux-latest.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|Oracle Linux
|13|[![](https://cdn.rawgit.com/Neilpang/acmetest/master/status/proxmox.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)| Proxmox https://pve.proxmox.com/wiki/HTTPSCertificateConfiguration#Let.27s_Encrypt_using_acme.sh
|14|-----| Cloud Linux  https://github.com/Neilpang/le/issues/111
|15|[![](https://cdn.rawgit.com/Neilpang/acmetest/master/status/openbsd.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|OpenBSD
|16|[![](https://cdn.rawgit.com/Neilpang/acmetest/master/status/mageia.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|Mageia
|17|-----| OpenWRT: Tested and working. See [wiki page](https://github.com/Neilpang/acme.sh/wiki/How-to-run-on-OpenWRT)
|18|[![](https://cdn.rawgit.com/Neilpang/acmetest/master/status/solaris.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|SunOS/Solaris
|19|[![](https://cdn.rawgit.com/Neilpang/acmetest/master/status/gentoo-stage3-amd64.svg)](https://github.com/Neilpang/letest#here-are-the-latest-status)|Gentoo Linux
|20|[![Build Status](https://travis-ci.org/Neilpang/acme.sh.svg?branch=master)](https://travis-ci.org/Neilpang/acme.sh)|Mac OSX

For all build statuses, check our [daily build project](https://github.com/Neilpang/acmetest):

https://github.com/Neilpang/acmetest


# Supported modes

- Webroot mode
- Standalone mode
- Apache mode
- DNS mode


# 1. How to install

### 1. Install online

Check this project: https://github.com/Neilpang/get.acme.sh

```bash
curl https://get.acme.sh | sh
```

Or:

```bash
wget -O -  https://get.acme.sh | sh
```


### 2. Or, Install from git

Clone this project and launch installation:

```bash
git clone https://github.com/Neilpang/acme.sh.git
cd ./acme.sh
./acme.sh --install
```

You `don't have to be root` then, although `it is recommended`.

Advanced Installation: https://github.com/Neilpang/acme.sh/wiki/How-to-install

The installer will perform 3 actions:

1. Create and copy `acme.sh` to your home dir (`$HOME`): `~/.acme.sh/`.
All certs will be placed in this folder too.
2. Create alias for: `acme.sh=~/.acme.sh/acme.sh`.
3. Create daily cron job to check and renew the certs if needed.

Cron entry example:

```bash
0 0 * * * "/home/user/.acme.sh"/acme.sh --cron --home "/home/user/.acme.sh" > /dev/null
```

After the installation, you must close the current terminal and reopen it to make the alias take effect.

Ok, you are ready to issue certs now.

Show help message:

```
root@v1:~# acme.sh -h
```

# 2. Just issue a cert

**Example 1:** Single domain.

```bash
acme.sh --issue -d example.com -w /home/wwwroot/example.com
```

**Example 2:** Multiple domains in the same cert.

```bash
acme.sh --issue -d example.com -d www.example.com -d cp.example.com -w /home/wwwroot/example.com
```

The parameter `/home/wwwroot/example.com` is the web root folder. You **MUST** have `write access` to this folder.

Second argument **"example.com"** is the main domain you want to issue the cert for.
You must have at least one domain there.

You must point and bind all the domains to the same webroot dir: `/home/wwwroot/example.com`.

Generated/issued certs will be placed in `~/.acme.sh/example.com/`

The issued cert will be renewed automatically every **60** days.

More examples: https://github.com/Neilpang/acme.sh/wiki/How-to-issue-a-cert


# 3. Install the issued cert to Apache/Nginx etc.

After you issue a cert, you probably want to install/copy the cert to your Apache/Nginx or other servers.
You **MUST** use this command to copy the certs to the target files, **DO NOT** use the certs files in **~/.acme.sh/** folder, they are for internal use only, the folder structure may change in the future.

**Apache** example:
```bash
acme.sh --installcert -d example.com \
--certpath      /path/to/certfile/in/apache/cert.pem  \
--keypath       /path/to/keyfile/in/apache/key.pem  \
--fullchainpath /path/to/fullchain/certfile/apache/fullchain.pem \
--reloadcmd     "service apache2 restart"
```

**Nginx** example:
```bash
acme.sh --installcert -d example.com \
--keypath       /path/to/keyfile/in/nginx/key.pem  \
--fullchainpath /path/to/fullchain/nginx/cert.pem \
--reloadcmd     "service nginx restart"
```

Only the domain is required, all the other parameters are optional.

Install/copy the issued cert/key to the production Apache or Nginx path.

The cert will be `renewed every **60** days by default` (which is configurable). Once the cert is renewed, the Apache/Nginx service will be restarted automatically by the command: `service apache2 restart` or `service nginx restart`.


# 4. Use Standalone server to issue cert

**(requires you to be root/sudoer or have permission to listen on port 80 (TCP))**

Port `80` (TCP) **MUST** be free to listen on, otherwise you will be prompted to free it and try again.

```bash
acme.sh --issue --standalone -d example.com -d www.example.com -d cp.example.com
```

More examples: https://github.com/Neilpang/acme.sh/wiki/How-to-issue-a-cert


# 5. Use Standalone TLS server to issue cert

**(requires you to be root/sudoer or have permission to listen on port 443 (TCP))**

acme.sh supports `tls-sni-01` validation.

Port `443` (TCP) **MUST** be free to listen on, otherwise you will be prompted to free it and try again.

```bash
acme.sh --issue --tls -d example.com -d www.example.com -d cp.example.com
```

More examples: https://github.com/Neilpang/acme.sh/wiki/How-to-issue-a-cert


# 6. Use Apache mode

**(requires you to be root/sudoer, since it is required to interact with Apache server)**

If you are running a web server, Apache or Nginx, it is recommended to use the `Webroot mode`.

Particularly, if you are running an Apache server, you should use Apache mode instead. This mode doesn't write any files to your web root folder.

Just set string "apache" as the second argument and it will force use of apache plugin automatically.

```
acme.sh --issue --apache -d example.com -d www.example.com -d cp.example.com
```

More examples: https://github.com/Neilpang/acme.sh/wiki/How-to-issue-a-cert


# 7. Use DNS mode:

Support the `dns-01` challenge.

```bash
acme.sh --issue --dns -d example.com -d www.example.com -d cp.example.com
```

You should get an output like below:

```
Add the following txt record:
Domain:_acme-challenge.example.com
Txt value:9ihDbjYfTExAYeDs4DBUeuTo18KBzwvTEjUnSwd32-c

Add the following txt record:
Domain:_acme-challenge.www.example.com
Txt value:9ihDbjxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

Please add those txt records to the domains. Waiting for the dns to take effect.
```

Then just rerun with `renew` argument:

```bash
acme.sh --renew -d example.com
```

Ok, it's finished.


# 8. Automatic DNS API integration

If your DNS provider supports API access, we can use that API to automatically issue the certs.

You don't have to do anything manually!

### Currently acme.sh supports:

1. CloudFlare.com API
1. DNSPod.cn API
1. CloudXNS.com API
1. GoDaddy.com API
1. OVH, kimsufi, soyoustart and runabove API
1. AWS Route 53
1. PowerDNS.com API
1. lexicon DNS API: https://github.com/Neilpang/acme.sh/wiki/How-to-use-lexicon-dns-api
   (DigitalOcean, DNSimple, DNSMadeEasy, DNSPark, EasyDNS, Namesilo, NS1, PointHQ, Rage4 and Vultr etc.)
1. LuaDNS.com API
1. DNSMadeEasy.com API
1. nsupdate API
1. aliyun.com(阿里云) API
1. ISPConfig 3.1 API

**More APIs coming soon...**

If your DNS provider is not on the supported list above, you can write your own DNS API script easily. If you do, please consider submitting a [Pull Request](https://github.com/Neilpang/acme.sh/pulls) and contribute it to the project.

For more details: [How to use DNS API](dnsapi)


# 9. Issue ECC certificates

`Let's Encrypt` can now issue **ECDSA** certificates.

And we support them too!

Just set the `length` parameter with a prefix `ec-`.

For example:

### Single domain ECC cerfiticate

```bash
acme.sh --issue -w /home/wwwroot/example.com -d example.com --keylength ec-256
```

### SAN multi domain ECC certificate

```bash
acme.sh --issue -w /home/wwwroot/example.com -d example.com -d www.example.com --keylength ec-256
```

Please look at the last parameter above.

Valid values are:

1. **ec-256 (prime256v1, "ECDSA P-256")**
2. **ec-384 (secp384r1,  "ECDSA P-384")**
3. **ec-521 (secp521r1,  "ECDSA P-521", which is not supported by Let's Encrypt yet.)**


# 10. How to renew the issued certs

No, you don't need to renew the certs manually. All the certs will be renewed automatically every **60** days.

However, you can also force to renew any cert:

```
acme.sh --renew -d example.com --force
```

or, for ECC cert:

```
acme.sh --renew -d example.com --force --ecc
```


# 11. How to upgrade `acme.sh`

acme.sh is in constant developement, so it's strongly recommended to use the latest code.

You can update acme.sh to the latest code:

```
acme.sh --upgrade
```

You can also enable auto upgrade:

```
acme.sh --upgrade --auto-upgrade
```

Then **acme.sh** will be kept up to date automatically.

Disable auto upgrade:

```
acme.sh --upgrade --auto-upgrade 0
```


# 12. Issue a cert from an existing CSR

https://github.com/Neilpang/acme.sh/wiki/Issue-a-cert-from-existing-CSR


# Under the Hood

Speak ACME language using shell, directly to "Let's Encrypt".

TODO:


# Acknowledgments

1. Acme-tiny: https://github.com/diafygi/acme-tiny
2. ACME protocol: https://github.com/ietf-wg-acme/acme
3. Certbot: https://github.com/certbot/certbot


# License & Others

License is GPLv3

Please Star and Fork me.

[Issues](https://github.com/Neilpang/acme.sh/issues) and [pull requests](https://github.com/Neilpang/acme.sh/pulls) are welcome.


# Donate

1. PayPal: donate@acme.sh

[Donate List](https://github.com/Neilpang/acme.sh/wiki/Donate-list)

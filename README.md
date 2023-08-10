# An ACME Shell script: acme.sh 

- An ACME protocol client written purely in Shell (Unix shell) language.
- Full ACME protocol implementation.
- Support ECDSA certs
- Support SAN and wildcard certs
- Simple, powerful and very easy to use. You only need 3 minutes to learn it.
- Bash, dash and sh compatible.
- Purely written in Shell with no dependencies on python.
- Just one script to issue, renew and install your certificates automatically.
- DOES NOT require `root/sudoer` access.
- Docker ready
- IPv6 ready
- Cron job notifications for renewal or error etc.
- A fork which doesn't target your Apache / Nginx configuration with intention to mess them completely up

It's probably the `easiest & smartest` shell script to automatically issue & renew the free certificates.

Wiki: https://github.com/acmesh-official/acme.sh/wiki

For Docker Fans: [acme.sh :two_hearts: Docker ](https://github.com/acmesh-official/acme.sh/wiki/Run-acme.sh-in-docker)

Twitter: [@neilpangxa](https://twitter.com/neilpangxa)


# [中文说明](https://github.com/acmesh-official/acme.sh/wiki/%E8%AF%B4%E6%98%8E)

# Who:
- [FreeBSD.org](https://blog.crashed.org/letsencrypt-in-freebsd-org/)
- [ruby-china.org](https://ruby-china.org/topics/31983)
- [Proxmox](https://pve.proxmox.com/wiki/Certificate_Management)
- [pfsense](https://github.com/pfsense/FreeBSD-ports/pull/89)
- [webfaction](https://community.webfaction.com/questions/19988/using-letsencrypt)
- [Loadbalancer.org](https://www.loadbalancer.org/blog/loadbalancer-org-with-lets-encrypt-quick-and-dirty)
- [discourse.org](https://meta.discourse.org/t/setting-up-lets-encrypt/40709)
- [Centminmod](https://centminmod.com/letsencrypt-acmetool-https.html)
- [splynx](https://forum.splynx.com/t/free-ssl-cert-for-splynx-lets-encrypt/297)
- [archlinux](https://www.archlinux.org/packages/community/any/acme.sh)
- [opnsense.org](https://github.com/opnsense/plugins/tree/master/security/acme-client/src/opnsense/scripts/OPNsense/AcmeClient)
- [CentOS Web Panel](http://centos-webpanel.com/)
- [lnmp.org](https://lnmp.org/)
- [more...](https://github.com/acmesh-official/acme.sh/wiki/Blogs-and-tutorials)

# Tested OS

Check our [testing project](https://github.com/acmesh-official/acmetest):

https://github.com/acmesh-official/acmetest

# Supported CA

- [ZeroSSL.com CA](https://github.com/acmesh-official/acme.sh/wiki/ZeroSSL.com-CA)(default)
- Letsencrypt.org CA
- [BuyPass.com CA](https://github.com/acmesh-official/acme.sh/wiki/BuyPass.com-CA)
- [SSL.com CA](https://github.com/acmesh-official/acme.sh/wiki/SSL.com-CA)
- [Pebble strict Mode](https://github.com/letsencrypt/pebble)
- Any other [RFC8555](https://tools.ietf.org/html/rfc8555)-compliant CA

# Supported modes

- Webroot mode
- Standalone mode
- Standalone tls-alpn mode
- DNS mode
- [DNS alias mode](https://github.com/acmesh-official/acme.sh/wiki/DNS-alias-mode)
- [Stateless mode](https://github.com/acmesh-official/acme.sh/wiki/Stateless-Mode)


# 1. How to install

### 1. Install online

```bash
curl https://raw.githubusercontent.com/HQJaTu/acme.sh/main/acme.sh | sh -s email=my@example.com
```

Or:

```bash
wget -O -  https://raw.githubusercontent.com/HQJaTu/acme.sh/main/acme.sh | sh -s email=my@example.com
```


### 2. Or, Install from git

Clone this project and launch installation:

```bash
git clone https://github.com/HQJaTu/acme.sh.git
cd ./acme.sh
./acme.sh --install -m my@example.com
```

You `don't have to be root` then, although `it is recommended`.

Advanced Installation: https://github.com/acmesh-official/acme.sh/wiki/How-to-install

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

```sh
root@v1:~# acme.sh -h
```

# 2. Just issue a cert

**Example 1:** Single domain.

```bash
acme.sh --issue -d example.com -w /home/wwwroot/example.com
```

or:

```bash
acme.sh --issue -d example.com -w /home/username/public_html
```

or:

```bash
acme.sh --issue -d example.com -w /var/www/html
```

**Example 2:** Multiple domains in the same cert.

```bash
acme.sh --issue -d example.com -d www.example.com -d cp.example.com -w /home/wwwroot/example.com
```

The parameter `/home/wwwroot/example.com` or `/home/username/public_html` or `/var/www/html` is the web root folder where you host your website files. You **MUST** have `write access` to this folder.

Second argument **"example.com"** is the main domain you want to issue the cert for.
You must have at least one domain there.

You must point and bind all the domains to the same webroot dir: `/home/wwwroot/example.com`.

The certs will be placed in `~/.acme.sh/example.com/`

The certs will be renewed automatically every **60** days.

More examples: https://github.com/acmesh-official/acme.sh/wiki/How-to-issue-a-cert


# 3. Install the cert to Apache/Nginx etc.
Not with this tool!

If you want a poorly written crappy tool to overwrite your precious configuration, use something else!

# 4. Use Standalone server to issue cert

**(requires you to be root/sudoer or have permission to listen on port 80 (TCP))**

Port `80` (TCP) **MUST** be free to listen on, otherwise you will be prompted to free it and try again.

```bash
acme.sh --issue --standalone -d example.com -d www.example.com -d cp.example.com
```

More examples: https://github.com/acmesh-official/acme.sh/wiki/How-to-issue-a-cert

# 5. Use Standalone ssl server to issue cert

**(requires you to be root/sudoer or have permission to listen on port 443 (TCP))**

Port `443` (TCP) **MUST** be free to listen on, otherwise you will be prompted to free it and try again.

```bash
acme.sh --issue --alpn -d example.com -d www.example.com -d cp.example.com
```

More examples: https://github.com/acmesh-official/acme.sh/wiki/How-to-issue-a-cert


# 8. Automatic DNS API integration

If your DNS provider supports API access, we can use that API to automatically issue the certs.

You don't have to do anything manually!

### Currently acme.sh supports most of the dns providers:

https://github.com/acmesh-official/acme.sh/wiki/dnsapi

1. CloudFlare.com API
1. DNSPod.cn API
1. CloudXNS.com API
1. GoDaddy.com API
1. PowerDNS.com API
1. OVH, kimsufi, soyoustart and runabove API
1. nsupdate API
1. LuaDNS.com API
1. DNSMadeEasy.com API
1. AWS Route 53
1. aliyun.com(阿里云) API
1. ISPConfig 3.1 API
1. Alwaysdata.com API
1. Linode.com API
1. FreeDNS (https://freedns.afraid.org/)
1. cyon.ch
1. Domain-Offensive/Resellerinterface/Domainrobot API
1. Gandi LiveDNS API
1. Knot DNS API
1. DigitalOcean API (native)
1. ClouDNS.net API
1. Infoblox NIOS API (https://www.infoblox.com/)
1. VSCALE (https://vscale.io/)
1. Dynu API (https://www.dynu.com)
1. DNSimple API
1. NS1.com API
1. DuckDNS.org API
1. Name.com API
1. Dyn Managed DNS API
1. Yandex PDD API (https://pdd.yandex.ru)
1. Hurricane Electric DNS service (https://dns.he.net)
1. UnoEuro API (https://www.unoeuro.com/)
1. INWX (https://www.inwx.de/)
1. Servercow (https://servercow.de)
1. Namesilo (https://www.namesilo.com)
1. InternetX autoDNS API (https://internetx.com)
1. Azure DNS
1. selectel.com(selectel.ru) DNS API
1. zonomi.com DNS API
1. DreamHost.com API
1. DirectAdmin API
1. KingHost (https://www.kinghost.com.br/)
1. Zilore (https://zilore.com)
1. Loopia.se API
1. acme-dns (https://github.com/joohoi/acme-dns)
1. TELE3 (https://www.tele3.cz)
1. EUSERV.EU (https://www.euserv.eu)
1. DNSPod.com API (https://www.dnspod.com)
1. Google Cloud DNS API
1. ConoHa (https://www.conoha.jp)
1. netcup DNS API (https://www.netcup.de)
1. GratisDNS.dk (https://gratisdns.dk)
1. Namecheap API (https://www.namecheap.com/)
1. MyDNS.JP API (https://www.mydns.jp/)
1. hosting.de (https://www.hosting.de)
1. Neodigit.net API (https://www.neodigit.net)
1. Exoscale.com API (https://www.exoscale.com/)
1. PointDNS API (https://pointhq.com/)
1. Active24.cz API (https://www.active24.cz/)
1. do.de API (https://www.do.de/)
1. NederHost API (https://www.nederhost.nl/)
1. Nexcess API (https://www.nexcess.net)
1. Thermo.io API (https://www.thermo.io)
1. Futurehosting API (https://www.futurehosting.com)
1. Rackspace Cloud DNS (https://www.rackspace.com)
1. Online.net API (https://online.net/)
1. MyDevil.net (https://www.mydevil.net/)

And:

**lexicon DNS API: https://github.com/Neilpang/acme.sh/wiki/How-to-use-lexicon-dns-api
   (DigitalOcean, DNSimple, DNSMadeEasy, DNSPark, EasyDNS, Namesilo, NS1, PointHQ, Rage4 and Vultr etc.)**


**More APIs coming soon...**

If your DNS provider is not on the supported list above, you can write your own DNS API script easily. If you do, please consider submitting a [Pull Request](https://github.com/Neilpang/acme.sh/pulls) and contribute it to the project.

For more details: [How to use DNS API](dnsapi)

# 9. Use DNS manual mode:

See: https://github.com/acmesh-official/acme.sh/wiki/dns-manual-mode first.

If your dns provider doesn't support any api access, you can add the txt record by hand.

```bash
acme.sh --issue --dns -d example.com -d www.example.com -d cp.example.com
```

You should get an output like below:

```sh
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

Ok, it's done.

**Take care, this is dns manual mode, it can not be renewed automatically. you will have to add a new txt record to your domain by your hand when you renew your cert.**

**Please use dns api mode instead.**

# 10. Issue ECC certificates

`Let's Encrypt` can now issue **ECDSA** certificates.

And we support them too!

Just set the `keylength` parameter with a prefix `ec-`.

For example:

### Single domain ECC certificate

```bash
acme.sh --issue -w /home/wwwroot/example.com -d example.com --keylength ec-256
```

### SAN multi domain ECC certificate

```bash
acme.sh --issue -w /home/wwwroot/example.com -d example.com -d www.example.com --keylength ec-256
```

Please look at the `keylength` parameter above.

Valid values are:

1. **ec-256 (prime256v1, "ECDSA P-256")**
2. **ec-384 (secp384r1,  "ECDSA P-384")**
3. **ec-521 (secp521r1,  "ECDSA P-521", which is not supported by Let's Encrypt yet.)**



# 11. Issue Wildcard certificates

It's simple, just give a wildcard domain as the `-d` parameter.

```sh
acme.sh  --issue -d example.com  -d '*.example.com'  --dns dns_cf
```



# 12. How to renew the certs

No, you don't need to renew the certs manually. All the certs will be renewed automatically every **60** days.

However, you can also force to renew a cert:

```sh
acme.sh --renew -d example.com --force
```

or, for ECC cert:

```sh
acme.sh --renew -d example.com --force --ecc
```


# 13. How to stop cert renewal

To stop renewal of a cert, you can execute the following to remove the cert from the renewal list:

```sh
acme.sh --remove -d example.com [--ecc]
```

The cert/key file is not removed from the disk.

You can remove the respective directory (e.g. `~/.acme.sh/example.com`) by yourself.


# 14. How to upgrade `acme.sh`

acme.sh is in constant development, so it's strongly recommended to use the latest code.

You can update acme.sh to the latest code:

```sh
acme.sh --upgrade
```


# 15. Issue a cert from an existing CSR

https://github.com/acmesh-official/acme.sh/wiki/Issue-a-cert-from-existing-CSR


# 16. Send notifications in cronjob

https://github.com/acmesh-official/acme.sh/wiki/notify

# 16. Send notifications in cronjob

https://github.com/Neilpang/acme.sh/wiki/notify

# 17. Under the Hood

Speak ACME language using shell, directly to "Let's Encrypt".

TODO:


# 18. Acknowledgments

1. Acme-tiny: https://github.com/diafygi/acme-tiny
2. ACME protocol: https://github.com/ietf-wg-acme/acme

# 19. License & Others

License is GPLv3

Please Star and Fork me.

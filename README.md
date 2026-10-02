<p align="center">
  <a href="https://zerossl.com/?fromacme.sh">
    <img src="https://github.com/user-attachments/assets/7531085e-399b-4ac2-82a2-90d14a0b7f05" alt="zerossl.com">
  </a>
</p>

<h1 align="center">🔐 acme.sh</h1>
<h3 align="center">An ACME Protocol Client Written Purely in Shell</h3>

<p align="center">
  <a href="https://github.com/acmesh-official/acme.sh/actions/workflows/FreeBSD.yml"><img src="https://github.com/acmesh-official/acme.sh/actions/workflows/FreeBSD.yml/badge.svg" alt="FreeBSD"></a>
  <a href="https://github.com/acmesh-official/acme.sh/actions/workflows/OpenBSD.yml"><img src="https://github.com/acmesh-official/acme.sh/actions/workflows/OpenBSD.yml/badge.svg" alt="OpenBSD"></a>
  <a href="https://github.com/acmesh-official/acme.sh/actions/workflows/NetBSD.yml"><img src="https://github.com/acmesh-official/acme.sh/actions/workflows/NetBSD.yml/badge.svg" alt="NetBSD"></a>
  <a href="https://github.com/acmesh-official/acme.sh/actions/workflows/MacOS.yml"><img src="https://github.com/acmesh-official/acme.sh/actions/workflows/MacOS.yml/badge.svg" alt="MacOS"></a>
  <a href="https://github.com/acmesh-official/acme.sh/actions/workflows/Ubuntu.yml"><img src="https://github.com/acmesh-official/acme.sh/actions/workflows/Ubuntu.yml/badge.svg" alt="Ubuntu"></a>
  <a href="https://github.com/acmesh-official/acme.sh/actions/workflows/Windows.yml"><img src="https://github.com/acmesh-official/acme.sh/actions/workflows/Windows.yml/badge.svg" alt="Windows"></a>
  <a href="https://github.com/acmesh-official/acme.sh/actions/workflows/Solaris.yml"><img src="https://github.com/acmesh-official/acme.sh/actions/workflows/Solaris.yml/badge.svg" alt="Solaris"></a>
  <a href="https://github.com/acmesh-official/acme.sh/actions/workflows/DragonFlyBSD.yml"><img src="https://github.com/acmesh-official/acme.sh/actions/workflows/DragonFlyBSD.yml/badge.svg" alt="DragonFlyBSD"></a>
  <a href="https://github.com/acmesh-official/acme.sh/actions/workflows/Omnios.yml"><img src="https://github.com/acmesh-official/acme.sh/actions/workflows/Omnios.yml/badge.svg" alt="Omnios"></a>
  <a href="https://github.com/acmesh-official/acme.sh/actions/workflows/OpenIndiana.yml"><img src="https://github.com/acmesh-official/acme.sh/actions/workflows/OpenIndiana.yml/badge.svg" alt="OpenIndiana"></a>
  <a href="https://github.com/acmesh-official/acme.sh/actions/workflows/Haiku.yml"><img src="https://github.com/acmesh-official/acme.sh/actions/workflows/Haiku.yml/badge.svg" alt="Haiku"></a>
</p>

<p align="center">
  <img src="https://github.com/acmesh-official/acme.sh/workflows/Shellcheck/badge.svg" alt="Shellcheck">
  <img src="https://github.com/acmesh-official/acme.sh/workflows/PebbleStrict/badge.svg" alt="PebbleStrict">
  <img src="https://github.com/acmesh-official/acme.sh/workflows/Build%20DockerHub/badge.svg" alt="DockerHub">
</p>

<p align="center">
  <a href="https://opencollective.com/acmesh"><img src="https://opencollective.com/acmesh/all/badge.svg?label=financial+contributors" alt="Financial Contributors on Open Collective"></a>
  <a href="https://gitter.im/acme-sh/Lobby?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge"><img src="https://badges.gitter.im/acme-sh/Lobby.svg" alt="Join the chat at Gitter"></a>
  <a href="https://hub.docker.com/r/neilpang/acme.sh" title="Click to view the image on Docker Hub"><img src="https://img.shields.io/docker/stars/neilpang/acme.sh.svg" alt="Docker stars"></a>
  <a href="https://hub.docker.com/r/neilpang/acme.sh" title="Click to view the image on Docker Hub"><img src="https://img.shields.io/docker/pulls/neilpang/acme.sh.svg" alt="Docker pulls"></a>
</p>


---

## ✨ Features

- 🐚 An ACME protocol client written **purely in Shell** (Unix shell) language
- 📜 Full ACME protocol implementation
- 🔑 Support **ECDSA** certificates
- 🌐 Support **SAN** and **wildcard** certificates
- ⚡ Simple, powerful and very easy to use — only **3 minutes** to learn!
- 🔧 Compatible with **Bash**, **dash** and **sh**
- 🚫 No dependencies on Python
- 🔄 One script to issue, renew and install your certificates automatically
- 👤 **DOES NOT** require `root/sudoer` access
- 🐳 Docker ready
- 🌍 IPv6 ready
- 📧 Cron job notifications for renewal or error

> 💡 It's probably the **easiest & smartest** shell script to automatically issue & renew free certificates.

<p align="center">
  <a href="https://github.com/acmesh-official/acme.sh/wiki"><strong>📚 Wiki</strong></a> •
  <a href="https://github.com/acmesh-official/acme.sh/wiki/Run-acme.sh-in-docker"><strong>🐳 Docker Guide</strong></a> •
  <a href="https://twitter.com/neilpangxa"><strong>🐦 Twitter</strong></a>
</p>

---

## 🌏 [中文说明](https://github.com/acmesh-official/acme.sh/wiki/%E8%AF%B4%E6%98%8E)

---

## 🏆 Who Uses acme.sh?
- [FreeBSD.org](https://blog.crashed.org/letsencrypt-in-freebsd-org/)
- [ruby-china.org](https://ruby-china.org/topics/31983)
- [Proxmox](https://pve.proxmox.com/wiki/Certificate_Management)
- [pfsense](https://github.com/pfsense/FreeBSD-ports/pull/89)
- [Loadbalancer.org](https://www.loadbalancer.org/blog/loadbalancer-org-with-lets-encrypt-quick-and-dirty)
- [discourse.org](https://meta.discourse.org/t/setting-up-lets-encrypt/40709)
- [Centminmod](https://centminmod.com/letsencrypt-acmetool-https.html)
- [splynx](https://forum.splynx.com/t/free-ssl-cert-for-splynx-lets-encrypt/297)
- [opnsense.org](https://github.com/opnsense/plugins/tree/master/security/acme-client/src/opnsense/scripts/OPNsense/AcmeClient)
- [CentOS Web Panel](https://control-webpanel.com)
- [lnmp.org](https://lnmp.org/)
- [more...](https://github.com/acmesh-official/acme.sh/wiki/Blogs-and-tutorials)

---

## 🖥️ Tested OS

| NO | Status| Platform|
|----|-------|---------|
|1|[![MacOS](https://github.com/acmesh-official/acme.sh/actions/workflows/MacOS.yml/badge.svg)](https://github.com/acmesh-official/acme.sh/actions/workflows/MacOS.yml)|Mac OSX
|2|[![Windows](https://github.com/acmesh-official/acme.sh/actions/workflows/Windows.yml/badge.svg)](https://github.com/acmesh-official/acme.sh/actions/workflows/Windows.yml)|Windows (cygwin with curl, openssl and crontab included)
|3|[![FreeBSD](https://github.com/acmesh-official/acme.sh/actions/workflows/FreeBSD.yml/badge.svg)](https://github.com/acmesh-official/acme.sh/actions/workflows/FreeBSD.yml)|FreeBSD
|4|[![Solaris](https://github.com/acmesh-official/acme.sh/actions/workflows/Solaris.yml/badge.svg)](https://github.com/acmesh-official/acme.sh/actions/workflows/Solaris.yml)|Solaris
|5|[![Ubuntu](https://github.com/acmesh-official/acme.sh/actions/workflows/Ubuntu.yml/badge.svg)](https://github.com/acmesh-official/acme.sh/actions/workflows/Ubuntu.yml)| Ubuntu
|6|NA|pfsense
|7|[![OpenBSD](https://github.com/acmesh-official/acme.sh/actions/workflows/OpenBSD.yml/badge.svg)](https://github.com/acmesh-official/acme.sh/actions/workflows/OpenBSD.yml)|OpenBSD
|8|[![NetBSD](https://github.com/acmesh-official/acme.sh/actions/workflows/NetBSD.yml/badge.svg)](https://github.com/acmesh-official/acme.sh/actions/workflows/NetBSD.yml)|NetBSD
|9|[![DragonFlyBSD](https://github.com/acmesh-official/acme.sh/actions/workflows/DragonFlyBSD.yml/badge.svg)](https://github.com/acmesh-official/acme.sh/actions/workflows/DragonFlyBSD.yml)|DragonFlyBSD
|10|[![Omnios](https://github.com/acmesh-official/acme.sh/actions/workflows/Omnios.yml/badge.svg)](https://github.com/acmesh-official/acme.sh/actions/workflows/Omnios.yml)|Omnios
|11|[![OpenIndiana](https://github.com/acmesh-official/acme.sh/actions/workflows/OpenIndiana.yml/badge.svg)](https://github.com/acmesh-official/acme.sh/actions/workflows/OpenIndiana.yml)|OpenIndiana
|12|[![Linux](https://github.com/acmesh-official/acme.sh/actions/workflows/Linux.yml/badge.svg)](https://github.com/acmesh-official/acme.sh/actions/workflows/Linux.yml)| Debian
|13|[![Linux](https://github.com/acmesh-official/acme.sh/actions/workflows/Linux.yml/badge.svg)](https://github.com/acmesh-official/acme.sh/actions/workflows/Linux.yml)|openSUSE
|14|[![Linux](https://github.com/acmesh-official/acme.sh/actions/workflows/Linux.yml/badge.svg)](https://github.com/acmesh-official/acme.sh/actions/workflows/Linux.yml)|Alpine Linux (with curl)
|15|[![Linux](https://github.com/acmesh-official/acme.sh/actions/workflows/Linux.yml/badge.svg)](https://github.com/acmesh-official/acme.sh/actions/workflows/Linux.yml)|Archlinux
|16|[![Linux](https://github.com/acmesh-official/acme.sh/actions/workflows/Linux.yml/badge.svg)](https://github.com/acmesh-official/acme.sh/actions/workflows/Linux.yml)|fedora
|17|[![Linux](https://github.com/acmesh-official/acme.sh/actions/workflows/Linux.yml/badge.svg)](https://github.com/acmesh-official/acme.sh/actions/workflows/Linux.yml)|Kali Linux
|18|[![Linux](https://github.com/acmesh-official/acme.sh/actions/workflows/Linux.yml/badge.svg)](https://github.com/acmesh-official/acme.sh/actions/workflows/Linux.yml)|Oracle Linux
|19|[![Linux](https://github.com/acmesh-official/acme.sh/actions/workflows/Linux.yml/badge.svg)](https://github.com/acmesh-official/acme.sh/actions/workflows/Linux.yml)|Mageia
|20|[![Linux](https://github.com/acmesh-official/acme.sh/actions/workflows/Linux.yml/badge.svg)](https://github.com/acmesh-official/acme.sh/actions/workflows/Linux.yml)|Gentoo Linux
|21|-----| Cloud Linux  https://github.com/acmesh-official/acme.sh/issues/111
|22|-----| OpenWRT: Tested and working. See [wiki page](https://github.com/acmesh-official/acme.sh/wiki/How-to-run-on-OpenWRT)
|23|[![](https://acmesh-official.github.io/acmetest/status/proxmox.svg)](https://github.com/acmesh-official/letest#here-are-the-latest-status)| Proxmox: See Proxmox VE Wiki. Version [4.x, 5.0, 5.1](https://pve.proxmox.com/wiki/HTTPS_Certificate_Configuration_(Version_4.x,_5.0_and_5.1)#Let.27s_Encrypt_using_acme.sh), version [5.2 and up](https://pve.proxmox.com/wiki/Certificate_Management)
|24|[![Haiku](https://github.com/acmesh-official/acme.sh/actions/workflows/Haiku.yml/badge.svg)](https://github.com/acmesh-official/acme.sh/actions/workflows/Haiku.yml)|Haiku OS


> 🧪 Check our [testing project](https://github.com/acmesh-official/acmetest)
>
> 🖥️ The testing VMs are supported by [vmactions.org](https://vmactions.org)

---

## 🏛️ Supported CA

| CA | Status |
|---|---|
| [ZeroSSL.com CA](https://github.com/acmesh-official/acme.sh/wiki/ZeroSSL.com-CA) | ⭐ **Default** |
| Letsencrypt.org CA | ✅ Supported |
| [SSL.com CA](https://github.com/acmesh-official/acme.sh/wiki/SSL.com-CA) | ✅ Supported |
| [Google.com Public CA](https://github.com/acmesh-official/acme.sh/wiki/Google-Public-CA) | ✅ Supported |
| [Actalis.com CA](https://github.com/acmesh-official/acme.sh/wiki/Actalis.com-CA) | ✅ Supported |
| [Pebble strict Mode](https://github.com/letsencrypt/pebble) | ✅ Supported |
| Any [RFC8555](https://tools.ietf.org/html/rfc8555)-compliant CA | ✅ Supported |

---

## ⚙️ Supported Modes

| Mode | Description |
|------|-------------|
| 📁 Webroot mode | Use existing webroot directory |
| 🖥️ Standalone mode | Built-in webserver on port 80 |
| 🔐 Standalone tls-alpn mode | Built-in webserver on port 443 |
| 🪶 Apache mode | Use Apache for verification |
| ⚡ Nginx mode | Use Nginx for verification |
| 🌐 DNS mode | Use DNS TXT records |
| 🔗 [DNS alias mode](https://github.com/acmesh-official/acme.sh/wiki/DNS-alias-mode) | Use DNS alias for verification |
| 📡 [Stateless mode](https://github.com/acmesh-official/acme.sh/wiki/Stateless-Mode) | Stateless verification |

---

## 📖 Usage Guide

### 1️⃣ How to Install

#### 📥 Install Online

> Check this project: https://github.com/acmesh-official/get.acme.sh

```bash
curl https://get.acme.sh | sh -s email=my@example.com
```

**Or:**

```bash
wget -O -  https://get.acme.sh | sh -s email=my@example.com
```

#### 📦 Install from Git

Clone this project and launch installation:

```bash
git clone https://github.com/acmesh-official/acme.sh.git
cd ./acme.sh
./acme.sh --install -m my@example.com
```

> 💡 You `don't have to be root` then, although `it is recommended`.

📚 **Advanced Installation:** https://github.com/acmesh-official/acme.sh/wiki/How-to-install

**The installer will perform 3 actions:**

1. Create and copy `acme.sh` to your home dir (`$HOME`): `~/.acme.sh/`.
All certs will be placed in this folder too.
2. Create alias for: `acme.sh=~/.acme.sh/acme.sh`.
3. Create daily cron job to check and renew the certs if needed.

Cron entry example:

```bash
0 0 * * * "/home/user/.acme.sh"/acme.sh --cron --home "/home/user/.acme.sh" > /dev/null
```

> ⚠️ After the installation, you must close the current terminal and reopen it to make the alias take effect.

✅ **You are ready to issue certs now!**

**Show help message:**

```sh
acme.sh -h
```

---

### 2️⃣ Issue a Certificate

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

> 🔄 The certs will be renewed automatically every **30** days.

> 🔐 The certs will default to **ECC** certificates.

📚 **More examples:** https://github.com/acmesh-official/acme.sh/wiki/How-to-issue-a-cert

---

### 3️⃣ Install the Certificate to Apache/Nginx

After the cert is generated, you probably want to install/copy the cert to your Apache/Nginx or other servers.

> ⚠️ **IMPORTANT:** You **MUST** use this command to copy the certs to the target files. **DO NOT** use the certs files in `~/.acme.sh/` folder — they are for internal use only, the folder structure may change in the future.

#### 🪶 Apache Example:
```bash
acme.sh --install-cert -d example.com \
--cert-file      /path/to/certfile/in/apache/cert.pem  \
--key-file       /path/to/keyfile/in/apache/key.pem  \
--fullchain-file /path/to/fullchain/certfile/apache/fullchain.pem \
--reloadcmd     "service apache2 force-reload"
```

#### ⚡ Nginx Example:
```bash
acme.sh --install-cert -d example.com \
--key-file       /path/to/keyfile/in/nginx/key.pem  \
--fullchain-file /path/to/fullchain/nginx/cert.pem \
--reloadcmd     "service nginx force-reload"
```

Only the domain is required, all the other parameters are optional.

The ownership and permission info of existing files are preserved. You can pre-create the files to define the ownership and permission.

Install/copy the cert/key to the production Apache or Nginx path.

> 🔄 The cert will be renewed every **30** days by default (configurable). Once renewed, the Apache/Nginx service will be reloaded automatically.

> ⚠️ **IMPORTANT:** The `reloadcmd` is very important. The cert can be automatically renewed, but without a correct `reloadcmd`, the cert may not be flushed to your server (like nginx or apache), then your website will not be able to show the renewed cert.

---

### 4️⃣ Use Standalone Server to Issue Certificate

> 🔐 Requires root/sudoer or permission to listen on port **80** (TCP)

> ⚠️ Port `80` (TCP) **MUST** be free to listen on, otherwise you will be prompted to free it and try again.

```bash
acme.sh --issue --standalone -d example.com -d www.example.com -d cp.example.com
```

📚 **More examples:** https://github.com/acmesh-official/acme.sh/wiki/How-to-issue-a-cert

---

### 5️⃣ Use Standalone TLS Server to Issue Certificate

> 🔐 Requires root/sudoer or permission to listen on port **443** (TCP)

> ⚠️ Port `443` (TCP) **MUST** be free to listen on, otherwise you will be prompted to free it and try again.

```bash
acme.sh --issue --alpn -d example.com -d www.example.com -d cp.example.com
```

📚 **More examples:** https://github.com/acmesh-official/acme.sh/wiki/How-to-issue-a-cert

---

### 6️⃣ Use Apache Mode

> 🔐 Requires root/sudoer to interact with Apache server

If you are running a web server, it is recommended to use the `Webroot mode`.

Particularly, if you are running an Apache server, you can use Apache mode instead. This mode doesn't write any files to your web root folder.

```sh
acme.sh --issue --apache -d example.com -d www.example.com -d cp.example.com
```

> 💡 **Note:** This Apache mode is only to issue the cert, it will **not** change your Apache config files. You will need to configure your website config files to use the cert by yourself. We don't want to mess with your Apache server, don't worry!

📚 **More examples:** https://github.com/acmesh-official/acme.sh/wiki/How-to-issue-a-cert

---

### 7️⃣ Use Nginx Mode

> 🔐 Requires root/sudoer to interact with Nginx server

If you are running a web server, it is recommended to use the `Webroot mode`.

Particularly, if you are running an Nginx server, you can use Nginx mode instead. This mode doesn't write any files to your web root folder.

It will configure Nginx server automatically to verify the domain and then restore the Nginx config to the original version. So, the config is not changed.

```sh
acme.sh --issue --nginx -d example.com -d www.example.com -d cp.example.com
```

> 💡 **Note:** This Nginx mode is only to issue the cert, it will **not** change your Nginx config files. You will need to configure your website config files to use the cert by yourself. We don't want to mess with your Nginx server, don't worry!

📚 **More examples:** https://github.com/acmesh-official/acme.sh/wiki/How-to-issue-a-cert

---

### 8️⃣ Automatic DNS API Integration

If your DNS provider supports API access, we can use that API to automatically issue the certs.

> ✨ **You don't have to do anything manually!**

📚 **Currently acme.sh supports most DNS providers:** https://github.com/acmesh-official/acme.sh/wiki/dnsapi

---

### 9️⃣ Use DNS Manual Mode

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

✅ **Done!**

> ⚠️ **WARNING:** This is DNS manual mode — it **cannot** be renewed automatically. You will have to add a new TXT record to your domain manually when you renew your cert. **Please use DNS API mode instead.**

---

### 🔟 Issue Certificates of Different Key Types (ECC or RSA)

Just set the `keylength` to a valid, supported value.

**Valid values for the `keylength` parameter:**

| Key Length | Description |
|------------|-------------|
| `ec-256` | prime256v1, "ECDSA P-256" ⭐ **Default** |
| `ec-384` | secp384r1, "ECDSA P-384" |
| `ec-521` | secp521r1, "ECDSA P-521" ⚠️ Not supported by Let's Encrypt yet |
| `2048` | RSA 2048-bit |
| `3072` | RSA 3072-bit |
| `4096` | RSA 4096-bit |

**Examples:**

#### Single domain with ECDSA P-384 certificate

```bash
acme.sh --issue -w /home/wwwroot/example.com -d example.com --keylength ec-384
```

#### SAN multi domain with RSA4096 certificate

```bash
acme.sh --issue -w /home/wwwroot/example.com -d example.com -d www.example.com --keylength 4096
```

---

### 1️⃣1️⃣ Issue Wildcard Certificates

It's simple! Just give a wildcard domain as the `-d` parameter:

```sh
acme.sh --issue -d example.com -d '*.example.com' --dns dns_cf
```



---

### 1️⃣2️⃣ How to Renew Certificates

> 🔄 No need to renew manually! All certs will be renewed automatically every **30** days.

However, you can force a renewal:

```sh
acme.sh --renew -d example.com --force
```

**For ECC cert:**

```sh
acme.sh --renew -d example.com --force --ecc
```

---

### 1️⃣3️⃣ How to Stop Certificate Renewal

To stop renewal of a cert, you can execute the following to remove the cert from the renewal list:

```sh
acme.sh --remove -d example.com [--ecc]
```

The cert/key file is not removed from the disk.

> 💡 You can remove the respective directory (e.g. `~/.acme.sh/example.com`) manually.

---

### 1️⃣4️⃣ How to Upgrade acme.sh

> 🚀 acme.sh is in constant development — it's strongly recommended to use the latest code.

**Update to latest:**

```sh
acme.sh --upgrade
```

**Enable auto upgrade:**

```sh
acme.sh --upgrade --auto-upgrade
```

**Disable auto upgrade:**

```sh
acme.sh --upgrade --auto-upgrade 0
```

---

### 1️⃣5️⃣ Issue a Certificate from an Existing CSR

📚 https://github.com/acmesh-official/acme.sh/wiki/Issue-a-cert-from-existing-CSR

---

### 1️⃣6️⃣ Send Notifications in Cronjob

📚 https://github.com/acmesh-official/acme.sh/wiki/notify

---

### 1️⃣7️⃣ Under the Hood

> 🔧 Speak ACME language using shell, directly to "Let's Encrypt".

---

### 1️⃣8️⃣ Acknowledgments

| Project | Link |
|---------|------|
| 🙏 Acme-tiny | https://github.com/diafygi/acme-tiny |
| 📜 ACME protocol | https://github.com/ietf-wg-acme/acme |

---

## 👥 Contributors

### 💻 Code Contributors

This project exists thanks to all the people who contribute.

<a href="https://github.com/acmesh-official/acme.sh/graphs/contributors"><img src="https://opencollective.com/acmesh/contributors.svg?width=890&button=false" /></a>

### 💰 Financial Contributors

Become a financial contributor and help us sustain our community. [[Contribute](https://opencollective.com/acmesh/contribute)]

#### 👤 Individuals

<a href="https://opencollective.com/acmesh"><img src="https://opencollective.com/acmesh/individuals.svg?width=890"></a>

#### 🏢 Organizations

Support this project with your organization. Your logo will show up here with a link to your website. [[Contribute](https://opencollective.com/acmesh/contribute)]

<a href="https://opencollective.com/acmesh/organization/0/website"><img src="https://opencollective.com/acmesh/organization/0/avatar.svg"></a>
<a href="https://opencollective.com/acmesh/organization/1/website"><img src="https://opencollective.com/acmesh/organization/1/avatar.svg"></a>
<a href="https://opencollective.com/acmesh/organization/2/website"><img src="https://opencollective.com/acmesh/organization/2/avatar.svg"></a>
<a href="https://opencollective.com/acmesh/organization/3/website"><img src="https://opencollective.com/acmesh/organization/3/avatar.svg"></a>
<a href="https://opencollective.com/acmesh/organization/4/website"><img src="https://opencollective.com/acmesh/organization/4/avatar.svg"></a>
<a href="https://opencollective.com/acmesh/organization/5/website"><img src="https://opencollective.com/acmesh/organization/5/avatar.svg"></a>
<a href="https://opencollective.com/acmesh/organization/6/website"><img src="https://opencollective.com/acmesh/organization/6/avatar.svg"></a>
<a href="https://opencollective.com/acmesh/organization/7/website"><img src="https://opencollective.com/acmesh/organization/7/avatar.svg"></a>
<a href="https://opencollective.com/acmesh/organization/8/website"><img src="https://opencollective.com/acmesh/organization/8/avatar.svg"></a>
<a href="https://opencollective.com/acmesh/organization/9/website"><img src="https://opencollective.com/acmesh/organization/9/avatar.svg"></a>

---

### 1️⃣9️⃣ License & Others

📄 **License:** GPLv3

⭐ Please **Star** and **Fork** this project!

🐛 [Issues](https://github.com/acmesh-official/acme.sh/issues) and 🔀 [Pull Requests](https://github.com/acmesh-official/acme.sh/pulls) are welcome.

---

### 2️⃣0️⃣ Donate

> 💝 Your donation makes **acme.sh** better!

| Method | Link |
|--------|------|
| PayPal / Alipay(支付宝) / Wechat(微信) | [https://donate.acme.sh/](https://donate.acme.sh/) |

📜 [Donate List](https://github.com/acmesh-official/acme.sh/wiki/Donate-list)

---

### 2️⃣1️⃣ About This Repository

> [!NOTE]
> This repository is officially maintained by <strong>ZeroSSL</strong> as part of our commitment to providing secure and reliable SSL/TLS solutions. We welcome contributions and feedback from the community!  
> For more information about our services, including free and paid SSL/TLS certificates, visit https://zerossl.com.
>   
> All donations made through this repository go directly to the original independent maintainer (Neil Pang), not to ZeroSSL.
<p align="center">
	<a href="https://zerossl.com">
		<picture>
			<source media="(prefers-color-scheme: dark)" srcset="https://zerossl.com/assets/images/zerossl_logo_white.svg">
			<source media="(prefers-color-scheme: light)" srcset="https://zerossl.com/assets/images/zerossl_logo.svg">
			<img src="https://zerossl.com/assets/images/zerossl_logo.svg" alt="ZeroSSL" width="256">
		</picture>
	</a>
</p>

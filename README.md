# le: means simp`Le`
Simplest shell script for LetsEncrypt free Certificate client

Simple and Powerful, you only need 3 minutes to learn.

Pure written in bash, no dependencies to python, acme-tiny or LetsEncrypt official client.
Just one script, to issue, renew your certificates automatically.

Probably it's the smallest&easiest&smartest shell script to automatically issue & renew the free certificates from LetsEncrypt.

Do NOT require to be `root/sudoer`.

#Tested OS
1. Ubuntu/Debian.
2. CentOS
3. Windows (cygwin with curl, openssl and crontab included)
4. FreeBSD with bash
5. pfsense with bash and curl


#Supported Mode
1. Webroot mode
2. Standalone mode
3. Apache mode
4. Dns mode

#How to use

1. Clone this project: https://github.com/Neilpang/le.git

2. Install le:
```
./le.sh install
```
You don't have to be root then, although it is recommended.

Which does 3 jobs:
* create and copy `le.sh` to your home dir:  `~/.le`
All the certs will be placed in this folder.
* create alias : `le.sh=~/.le/le.sh` and `le=~/.le/le.sh`. 
* create everyday cron job to check and renew the cert if needed.

After install, you must close current terminal and reopen again to make the alias take effect.

Ok, you are ready to issue cert now.
Show help message:
```
root@v1:~# le.sh
https://github.com/Neilpang/le
v1.1.1
Usage: le.sh  [command] ...[args]....
Available commands:

install:
  Install le.sh to your system.
issue:
  Issue a cert.
installcert:
  Install the issued cert to apache/nginx or any other server.
renew:
  Renew a cert.
renewAll:
  Renew all the certs.
uninstall:
  Uninstall le.sh, and uninstall the cron job.
version:
  Show version info.
installcronjob:
  Install the cron job to renew certs, you don't need to call this. The 'install' command can automatically install the cron job.
uninstallcronjob:
  Uninstall the cron job. The 'uninstall' command can do this automatically.
createAccountKey:
  Create an account private key, professional use.
createDomainKey:
  Create an domain private key, professional use.
createCSR:
  Create CSR , professional use.


root@v1:~/le# le issue
Usage: le  issue  webroot|no|apache|dns   a.com  [www.a.com,b.com,c.com]|no   [key-length]|no


```

Set the param value to "no" means you want to ignore it.

For example, if you give "no" to "key-length", it will use default length 2048.

And if you give 'no' to 'cert-file-path', it will not copy the issued cert to the "cert-file-path".

In all the cases, the issued cert will be placed in "~/.le/domain.com/"

 
# Just issue a cert:
Example 1:
Only one domain:
```
le issue   /home/wwwroot/aa.com    aa.com 
```

Example 2:
Multiple domains in the same cert:

```
le issue   /home/wwwroot/aa.com    aa.com    www.aa.com,cp.aa.com
```

First argument `/home/wwwroot/aa.com` is the web root folder, You must have `write` access to this folder.

Second argument "aa.com" is the main domain you want to issue cert for.

Third argument is the additional domain list you want to use. Comma separated list,  which is Optional.

You must point and bind all the domains to the same webroot dir:`/home/wwwroot/aa.com`

The cert will be placed in `~/.le/aa.com/`

The issued cert will be renewed every 80 days automatically.

# Install issued cert to apache/nginx etc.
```
le installcert  aa.com /path/to/certfile/in/apache/nginx  /path/to/keyfile/in/apache/nginx  /path/to/ca/certfile/apache/nginx   "service apache2|nginx reload"
```

Install the issued cert/key to the production apache or nginx path.

The cert will be renewed every 80 days by default (which is configurable), Once the cert is renewed, the apache/nginx will be automatically reloaded by the command: `service apache2 reload` or `service nginx reload`


# Use Standalone server to issue cert (requires you be root/sudoer, or you have permission to listen tcp 80 port):
Same usage as all above,  just give `no` as the webroot.
The tcp `80` port must be free to listen, otherwise you will be prompted to free the `80` port and try again.

```
le issue    no    aa.com    www.aa.com,cp.aa.com
```

# Use Apache mode (requires you be root/sudoer, since it is required to interact with apache server):
If you are running a web server, apache or nginx, it is recommended to use the Webroot mode.
Particularly,  if you are running an apache server, you can use apache mode instead. Which doesn't write any file to your web root folder.

Just set string "apache" to the first argument, it will use apache plugin automatically.

```
le  issue  apache  aa.com   www.aa.com,user.aa.com
```
All the other arguments are the same with previous.


# Use DNS mode:
Support the latest dns-01 challenge.

```
le  issue   dns   aa.com  www.aa.com,user.aa.com
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
le renew  aa.com
```

Ok, it's finished.


#Automatic dns api integeration

If your dns provider supports api access, we can use api to automatically issue certs.
You don't have do anything manually.

###Currently we support:

1. Cloudflare.com api
2. Dnspod.cn api
3. Cloudxns.com api
4. AWS Route 53, see: https://github.com/Neilpang/le/issues/65

More apis are coming soon....

If your dns provider is not in the supported list above, you can write your own script api easily.

For more details: [How to use dns api](dnsapi)


# Issue ECC certificate:
LetsEncrypt now can issue ECDSA certificate.
And we also support it.

Just set the `length` parameter with a prefix `ec-`.
For example:
```
le issue  /home/wwwroot/aa.com    aa.com  www.aa.com   ec-256
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




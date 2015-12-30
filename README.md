# le
Simplest shell script for LetsEncrypt free Certificate client

This is a shell version from https://github.com/diafygi/acme-tiny

Pure written in bash, no dependencies to python , acme-tiny or LetsEncrypt official client (https://github.com/letsencrypt/letsencrypt)

Just one script, to issue, renew your certificates automatically.

Probably it's the smallest&easiest&smartest shell script to automatically  issue&renew the free certificates from LetsEncrypt.


#Supported OS
1. Ubuntu/Debian.
2. CentOS


#How to use

1. Clone this project: https://github.com/Neilpang/le.git

2. Install le:
```
./le.sh install
```
Which does 3 jobs:
* create and copy `le.sh` to your home dir:  `~/.le`
All the certs will be placed in this folder.
* create symbol link: `/bin/le  -> ~/.le/le.sh`
* create everyday cron job to check and renew the cert if needed.


Ok,  you are ready to issue cert now.
Show help message:
```
root@xvm:~# le 
Usage: issue|renew|renewAll|createAccountKey|createDomainKey|createCSR|install|uninstall

root@xvm:~# le issue
Usage: /bin/le webroot a.com [www.a.com,b.com,c.com]  [key-length] [cert-file-path] [key-file-path] [reloadCmd]

```
 
# Just issue a cert:
```
le issue   /home/wwwroot/aa.com    aa.com    www.aa.com,cp.aa.com
```
First argument `/home/wwwroot/aa.com` is the web root folder, You must have `write` access to this folder.

Second argument "aa.com" is the main domain you want to issue cert for.

Third argument is the additional domain list you want to use.  Comma separated list,  which is Optional.

You must point and bind all the domains to the same webroot dir:`/home/wwwroot/aa.com`

The cert will be placed in `~/.le/aa.com/`


The issued cert will be renewed every 50 days automatically.


# Issue a cert, and install to apache/nginx
```
le issue   /home/wwwroot/aa.com    aa.com    www.aa.com,cp.aa.com  2048  /path/to/certfile/in/apache/nginx  /path/to/keyfile/in/apache/nginx   "service apache2/nginx reload"
```
Which issues the cert and then links it to the production apache or nginx path.
The cert will be renewed every 50 days by default (which is configurable), Once the cert is renewed, the apache/nginx will be automatically reloaded by the command: ` service apache2 reload` or `service nginx reload`




#Under the Hood

Speak ACME language with bash directly to Let's encrypt.

TODO:


#License & Other

License is GPLv3

Please Star and Fork me.

Issues and pullrequests are welcomed.




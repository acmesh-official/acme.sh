# le
Simplest shell script for LetsEncrypt free Certificate client

This is a shell version from https://github.com/diafygi/acme-tiny

Pure written in bash, no dependencies to python , acme-tiny or LetsEncrypt official client (https://github.com/letsencrypt/letsencrypt)

Just one script, to issue, renew your certiricates automatically.

Possiblly it's the smallest&easiest&smartest shell script to automatically  issue&renew the free certificates from LetsEncrypt.


#Supported OS
1. Tested on Ubuntu/Debian.
2. CentOS is Not tested yet, It should work.


#How to use

1. Clone this project: https://github.com/Neilpang/le.git

2. Install le:
```
./le.sh install
```
Which does 2 things:
* create and copy le.sh to your home dir:  `~/.le`
All the certs will be placed in this folder.
* create symbol link: `/bin/le  -> ~/.le/ls.sh`

3. Ok,  you are ready to issue cert now.
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
First argument " /home/wwwroot/aa.com" is the web root folder

Second argument "aa.com" is the domain you want to issue cert for.

Third argument  is the additional domain list you want to use.  Comma sperated list,  Optional.

'You must point and bind all the domains to the same webroot dir:/home/wwwroot/aa.com'

The cert will be placed in `~/.le/aa.com/`


The issued cert will be renewed every 50 days automatically.


# Issue a cert, and install to apache
```
le issue   /home/wwwroot/aa.com    aa.com    www.aa.com,cp.aa.com  2048  /path/to/certfile/in/apache/nginx  /path/to/keyfile/in/apache/nginx   "service apache2 reload"
```
This can link the issued cert to the production apache or nginx path.
Once the cert is renewed,  the apache/nginx will be automatically reloaded by the command: ` service apache2 reload`




#Under the Hood

Use bash to say ACME language directly to Let's encrypt.

TODO:


#License & Other

License is GPLv3

Please Star and Fock me.

Issues and pullrequests are welcomed.




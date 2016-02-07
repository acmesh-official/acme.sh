# How to use dns api

## Use CloudFlare domain api to automatically issue cert

For now, we support clourflare integeration.

First you need to login to your clourflare account to get your api key.

```
export CF_Key="sdfsdfsdfljlbjkljlkjsdfoiwje"

export CF_Email="xxxx@sss.com"

```

Ok, let's issue cert now:
```
le.sh   issue   dns-cf   aa.com  www.aa.com
```

The `CF_Key` and `CF_Email`  will be saved in `~/.le/account.conf`, when next time you use cloudflare api, it will reuse this key.



## Use Dnspod.cn domain api to automatically issue cert

For now, we support dnspod.cn integeration.

First you need to login to your dnspod.cn account to get your api key and key id.

```
export DP_Id="1234"

export DP_Key="sADDsdasdgdsf"

```

Ok, let's issue cert now:
```
le.sh   issue   dns-dp   aa.com  www.aa.com
```

The `DP_Id` and `DP_Key`  will be saved in `~/.le/account.conf`, when next time you use dnspod.cn api, it will reuse this key.


## Use Cloudxns.com domain api to automatically issue cert

For now, we support Cloudxns.com integeration.

First you need to login to your Cloudxns.com account to get your api key and key secret.

```
export CX_Key="1234"

export CX_Api="sADDsdasdgdsf"

```

Ok, let's issue cert now:
```
le.sh   issue   dns-cx   aa.com  www.aa.com
```

The `CX_Key` and `CX_Api`  will be saved in `~/.le/account.conf`, when next time you use Cloudxns.com api, it will reuse this key.



# Use custom api

If your api is not supported yet,  you can write your own dns api.

Let's assume you want to name it 'myapi',

1. Create a bash script named  `~/.le/dns-myapi.sh`,
2. In the scrypt, you must have a function named `dns-myapi-add()`. Which will be called by le.sh to add dns records.
3. Then you can use your api to issue cert like:

```
le.sh  issue  dns-myapi  aa.com  www.aa.com
```

For more details, please check our sample script: [dnsapi/dns-myapi.sh](README.md)





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
acme.sh   --issue   --dns dns_cf   -d aa.com  -d www.aa.com
```

The `CF_Key` and `CF_Email`  will be saved in `~/.acme.sh/account.conf`, when next time you use cloudflare api, it will reuse this key.



## Use Dnspod.cn domain api to automatically issue cert

For now, we support dnspod.cn integeration.

First you need to login to your dnspod.cn account to get your api key and key id.

```
export DP_Id="1234"

export DP_Key="sADDsdasdgdsf"

```

Ok, let's issue cert now:
```
acme.sh   --issue   --dns dns_dp   -d aa.com  -d www.aa.com
```

The `DP_Id` and `DP_Key`  will be saved in `~/.acme.sh/account.conf`, when next time you use dnspod.cn api, it will reuse this key.


## Use Cloudxns.com domain api to automatically issue cert

For now, we support Cloudxns.com integeration.

First you need to login to your Cloudxns.com account to get your api key and key secret.

```
export CX_Key="1234"

export CX_Secret="sADDsdasdgdsf"

```

Ok, let's issue cert now:
```
acme.sh   --issue   --dns dns_cx   -d aa.com  -d www.aa.com
```

The `CX_Key` and `CX_Secret`  will be saved in `~/.acme.sh/account.conf`, when next time you use Cloudxns.com api, it will reuse this key.


## Use Godaddy.com domain api to automatically issue cert

We support Godaddy integeration.

First you need to login to your Godaddy account to get your api key and api secret.

https://developer.godaddy.com/keys/

Please Create a Production key, instead of a Test key.


```
export GD_Key="sdfsdfsdfljlbjkljlkjsdfoiwje"

export GD_Secret="asdfsdafdsfdsfdsfdsfdsafd"

```

Ok, let's issue cert now:
```
acme.sh   --issue   --dns dns_gd   -d aa.com  -d www.aa.com
```

The `GD_Key` and `GD_Secret`  will be saved in `~/.acme.sh/account.conf`, when next time you use cloudflare api, it will reuse this key.

## Use OVH/kimsufi/soyoustart/runabove API

https://github.com/Neilpang/acme.sh/wiki/How-to-use-OVH-domain-api

# Use custom api

If your api is not supported yet,  you can write your own dns api.

Let's assume you want to name it 'myapi',

1. Create a bash script named  `~/.acme.sh/dns_myapi.sh`,
2. In the script, you must have a function named `dns_myapi_add()`. Which will be called by acme.sh to add dns records.
3. Then you can use your api to issue cert like:

```
acme.sh  --issue  --dns  dns_myapi  -d aa.com  -d www.aa.com
```

For more details, please check our sample script: [dns_myapi.sh](dns_myapi.sh)



# Use lexicon dns api

https://github.com/Neilpang/acme.sh/wiki/How-to-use-lexicon-dns-api



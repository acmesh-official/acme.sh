# Deploy 使用文档

## 13. 部署到七牛域名证书服务

使用 acme.sh 部署到七牛之前，需要确保部署的域名已打开 HTTPS 功能，您可以访问[融合 CDN - 域名管理](https://portal.qiniu.com/cdn/domain) 设置。
另外还需要先导出 AK/SK 环境变量，您可以访问[密钥管理](https://portal.qiniu.com/user/key) 获得。

```sh
$ export QINIU_AK="foo"
$ export QINIU_SK="bar"
```

完成准备工作之后，您就可以通过下面的命令开始部署 SSL 证书到七牛上：

```sh
$ acme.sh --deploy -d example.com --deploy-hook qiniu
```

假如您部署的证书为泛域名证书，您还需要设置 `QINIU_CDN_DOMAIN` 变量，指定实际需要部署的域名：

```sh
$ export QINIU_CDN_DOMAIN="cdn.example.com"
$ acme.sh --deploy -d example.com --deploy-hook qiniu
```

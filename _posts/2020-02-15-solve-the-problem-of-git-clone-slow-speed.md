---
layout: mypost
title: 解决git clone速度慢问题
categories: [疑难杂症]
---

### 前言

关于git clone速度特别慢的问题,网上查询所知github.global.ssl.fastly.net域名被限制了
只要找到这个域名对应ip,然后添加到hosts文件,刷新DNS.(然而发现这个方法并不管用)

速度感人
![](post-source-1.png)

所以怎么解决!
### 使用代理

前提是科学上网(ss)

设置全局代理
> git config --global http.proxy http://127.0.0.1:1080
>
> git config --global https.proxy https://127.0.0.1:1080

或者
> git config --global http.proxy 'socks5://127.0.0.1:1080'
>
> git config --global https.proxy 'socks5://127.0.0.1:1080'

![](hpost-source-2.png)

但是使用全局代理,克隆国内仓库会很慢.所以可以只对github代理
> git config --global http.https://github.com.proxy socks5://127.0.0.1:1080
>
> git config --global https.https://github.com.proxy socks5://127.0.0.1:1080

如果想取消代理
> git config --global --unset http.https://github.com.proxy
>
> git config --global --unset https.https://github.com.proxy







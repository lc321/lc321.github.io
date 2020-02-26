---
layout: mypost
title: SSH免密登录
categories: [疑难杂症]
---

### 配置方法

主机A生成一对密钥

> ssh-keygen -t rsa

直接回车
将公钥发送到主机B

> ssh-copy-id root@ip_addr(B)






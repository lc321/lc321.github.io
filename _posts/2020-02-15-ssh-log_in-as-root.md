---
layout: mypost
title: SSH root方式登录
categories: [疑难杂症]
---

### 配置方法

root权限下修改

> vim /etc/ssh/sshd_config

找到PermitRootLogin prohibit-password 改为PermitRootLogin yes
<br/>
重启服务

> service ssh restart

设置root登陆密码

> password root






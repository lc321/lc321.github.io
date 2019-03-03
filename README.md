kubernetes 一键安装脚本（限一个master,一个node）
====

# 1、介绍

- 操作系统

   ubuntu 16.04

# 2、安装运行
## 2.1 事前准备

- 云服务器在控制台设置安全组，最好开放所有端口.
- 所有操作均在root权限下操作
- 每个节点需设置机器的hostname
master就设置成master*
node就设置成node*

```
hostnamectl set-hostname master1
```
- 所有机器需要设定/etc/hosts解析到所有集群主机()

```
119.27.168.122 master1
118.25.229.56 node1
```

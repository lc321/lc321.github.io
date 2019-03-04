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
- 所有机器需要设定/etc/hosts解析到所有集群主机(ip地址填自己的)

```
119.27.168.122 master1
118.25.229.56 node1
```

- 所有机器设置开机加载项与docker下载

```
git clone https://github.com/lc321/lc321.github.io.git ~/k8s-shell
cd ~/k8s-shell
./k8s-common.sh
```
  关机重启

## 2.2 开始安装

- 启动脚本

```
cd ~/k8s-shell
./k8s-setup.sh
```

（要点）
- 暂停1

脚本运行中，根据提示输入ip地址

- 暂停2

ssh免密，一路回车，按提示输入yes，并输入root用户密码

- 暂停3

etcd只允许局域网ip，所以进行修改,将listen-peer-urls和listen-client-urls的两个https的公网IP改成内网IP

- 暂停4

修改flannel.alpha.coreos.com/public-ip为公网ip

# 3、测试
**检查是否正常**
```
cat<<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: busybox
  namespace: default
spec:
  containers:
  - name: busybox
    image: busybox:1.28
    command:
      - sleep
      - "3600"
    imagePullPolicy: IfNotPresent
  restartPolicy: Always
EOF

kubectl exec -ti busybox -- nslookup kubernetes
```

***完事儿（待完善）***

---
layout: mypost
title: 二进制部署Kubernetes v1.13.4
categories: [环境搭建]
---

### 事前准备

*所有操作建议在root下进行*

*关闭所有防火墙与SELinux(修改SELINUX=enforcing为SELINUX=disabled)*
```
systemctl stop firewalld & systemctl disable firewalld
setenforce 0
sed -ri '/^[^#]*SELINUX=/s#=.+$#=disabled#' /etc/selinux/config
```

*关闭所有机器的swap分区*
```
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab
```

*(centos)建议升级系统*
```
yum install epel-release -y
yum install wget git jq psmisc socat -y
yum update -y --exclude=kernel*
```

*目前市面上包管理下内核版本会很低,建议升级内核*
* 查看内核依赖包perl
```
[ ! -f /usr/bin/perl ] && yum install perl -y
```

* 导入升级内核所需的yum源
```
rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
```

* 查看可用内核
```
yum --disablerepo="*" --enablerepo="elrepo-kernel" list available  --showduplicates
```

* 最新版本内核安装
```
yum --disablerepo="*" --enablerepo="elrepo-kernel" list available  --showduplicates | grep -Po '^kernel-ml.x86_64\s+\K\S+(?=.el7)'
yum --disablerepo="*" --enablerepo=elrepo-kernel install -y kernel-ml{,-devel}
```

* 修改内核启动顺序
```
grub2-set-default  0 && grub2-mkconfig -o /etc/grub2.cfg
grubby --default-kernel
```

* 开启docker官方内核检查脚本建议
```
grubby --args="user_namespace.enable=1" --update-kernel="$(grubby --default-kernel)"
```
* 重启加载内核(reboot)

*安装ipvs需要的软件依赖包*
```
yum install ipvsadm ipset sysstat conntrack libseccomp -y
```

*所有机器选择需要开机加载的内核模块,以下是 ipvs 模式需要加载的模块并设置开机自动加载*
```
:> /etc/modules-load.d/ipvs.conf
module=(
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
br_netfilter
)

for kernel_module in ${module[@]};do
	/sbin/modinfo -F filename $kernel_module |& grep -qv ERROR && echo $kernel_module >> /etc/modules-load.d/ipvs.conf || :
done

systemctl enable --now systemd-modules-load.service
```

systemctl enable命令可能报错,使用systemctl status -l systemd-modules-load.service
看看哪个内核模块加载不了,在/etc/modules-load.d/ipvs.conf里注释掉它再enable试试

*所有机器设定/etc/sysctl.d/k8s.conf的系统参数*

```
cat <<EOF > /etc/sysctl.d/k8s.conf
# https://github.com/moby/moby/issues/31208 
# ipvsadm -l --timout
# 修复ipvs模式下长连接timeout问题 小于900即可
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 10
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv4.neigh.default.gc_stale_time = 120
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.lo.arp_announce = 2
net.ipv4.conf.all.arp_announce = 2
net.ipv4.ip_forward = 1
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 1024
net.ipv4.tcp_synack_retries = 2
# 要求iptables不对bridge的数据进行处理
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-arptables = 1
net.netfilter.nf_conntrack_max = 2310720
fs.inotify.max_user_watches=89100
fs.may_detach_mounts = 1
fs.file-max = 52706963
fs.nr_open = 52706963
vm.swappiness = 0
vm.overcommit_memory=1
vm.panic_on_oom=0
EOF

sysctl --system
```

*所有机器需要安装Docker CE 版本的容器引擎,这里使用版本18.06.03*
```
export VERSION=18.06
curl -fsSL "https://get.docker.com/" | bash -s -- --mirror Aliyun
```

* 所有机器配置加速源:
```
mkdir -p /etc/docker/
cat>/etc/docker/daemon.json<<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "registry-mirrors": ["https://fz5yth0r.mirror.aliyuncs.com"],
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
EOF
```

* 设置docker开机启动,手动设置docker命令补全
```
yum install -y epel-release bash-completion && cp /usr/share/bash-completion/completions/docker /etc/bash_completion.d/
systemctl enable --now docker
```

*设置所有机器的hostname master就设置成master node就设置成node*
```
hostnamectl set-hostname master1
```

*所有机器需要设定/etc/hosts解析到所有集群主机*
```
192.168.56.103 master1
192.168.56.101 node1
192.168.56.104 node2
```

*所有机器需要设定ntp*
```
yum install -y ntp
timedatectl status
timedatectl list-timezones | grep Shanghai
timedatectl set-timezone Asia/Hong_Kong
timedatectl set-ntp yes
date
```

*master1 免密ssh其它服务器*
```
ssh-keygen -t rsa
ssh-copy-id master1
ssh-copy-id node1
ssh-copy-id node2
```
**此时可以关机做个快照**

### 建立集群CA keys 与Certificates

#### 本次部署的网络信息:
> * Cluster IP CIDR: 10.244.0.0/16
> * Service Cluster IP CIDR: 10.96.0.0/12
> * Service DNS IP: 10.96.0.10
> * DNS DN: cluster.local
> * Kubernetes API VIP: 192.168.56.103（虚拟机）
> * Kubernetes Ingress VIP: 192.168.56.103（虚拟机）

#### 节点信息

IP | Hostname | CPU | Memory 
-|-|-|-
192.168.56.103 |  master1 | 1 | 2G |   
192.168.56.101 |  node1 | 1 | 2G |   
192.168.56.104 |  node2 | 1 | 2G |   

**声明变量**

*在master1上使用环境变量声明集群信息(如果ssh端口需要重新声明)*
```
# 声明集群成员信息
declare -A MasterArray otherMaster NodeArray AllNode
MasterArray=(['master1']=192.168.56.103)
otherMaster=()
NodeArray=(['node1']=192.168.56.101 ['node2']=192.168.56.104)
# 下面复制上面的信息粘贴即可
AllNode=(['master1']=192.168.56.103 ['node1']=192.168.56.101 ['node2']=192.168.56.104)

export         VIP=192.168.56.103

[ "${#MasterArray[@]}" -eq 1 ]  && export VIP=${MasterArray[@]} || export API_PORT=8443
export KUBE_APISERVER=https://${VIP}:${API_PORT:=6443}

#声明需要安装的的k8s版本
export KUBE_VERSION=v1.13.4

# 网卡名
export interface=enp0s8

# cni
export CNI_URL="https://github.com/containernetworking/plugins/releases/download"
export CNI_VERSION=v0.7.4
# etcd
export ETCD_version=v3.3.12
```

*首先在master1上通过git获取部署要用到的二进制配置文件和yml*
```
git clone https://github.com/zhangguanzhang/k8s-manual-files.git ~/k8s-manual-files -b v1.13.4
cd ~/k8s-manual-files/
```

*下载Kubernetes二进制文件*
```
cd ~/k8s-manual-files/
docker pull zhangguanzhang/k8s_bin:$KUBE_VERSION-full
docker run --rm -d --name temp zhangguanzhang/k8s_bin:$KUBE_VERSION-full sleep 10
docker cp temp:/kubernetes-server-linux-amd64.tar.gz .
tar -zxvf kubernetes-server-linux-amd64.tar.gz  --strip-components=3 -C /usr/local/bin kubernetes/server/bin/kube{let,ctl,-apiserver,-controller-manager,-scheduler,-proxy}
```

*分发二进制文件到node*
```
for NODE in "${!NodeArray[@]}"; do
    echo "--- $NODE ${NodeArray[$NODE]} ---"
    scp /usr/local/bin/kube{let,-proxy} ${NodeArray[$NODE]}:/usr/local/bin/ 
done
```

*分发cni文件到node*
```
mkdir -p /opt/cni/bin
wget  "${CNI_URL}/${CNI_VERSION}/cni-plugins-amd64-${CNI_VERSION}.tgz" 
tar -zxf cni-plugins-amd64-${CNI_VERSION}.tgz -C /opt/cni/bin

# 分发cni文件
for NODE in "${!NodeArray[@]}"; do
    echo "--- $NODE ${NodeArray[$NODE]} ---"
    ssh ${NodeArray[$NODE]} 'mkdir -p /opt/cni/bin'
    scp /opt/cni/bin/* ${NodeArray[$NODE]}:/opt/cni/bin/
done
```

*准备openssl 证书配置文件*
```
mkdir -p /etc/kubernetes/pki/etcd
sed -i "/IP.2/a IP.3 = $VIP" ~/k8s-manual-files/pki/openssl.cnf
sed -ri '/IP.3/r '<( paste -d '' <(seq -f 'IP.%g = ' 4 $[${#AllNode[@]}+3])  <(xargs -n1<<<${AllNode[@]} | sort) ) ~/k8s-manual-files/pki/openssl.cnf
sed -ri '$r '<( paste -d '' <(seq -f 'IP.%g = ' 2 $[${#MasterArray[@]}+1])  <(xargs -n1<<<${MasterArray[@]} | sort) ) ~/k8s-manual-files/pki/openssl.cnf
cp ~/k8s-manual-files/pki/openssl.cnf /etc/kubernetes/pki/
cd /etc/kubernetes/pki
```

*生成CA凭证*
* kubernetes-ca
```
openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -config openssl.cnf -subj "/CN=kubernetes-ca" -extensions v3_ca -out ca.crt -days 10000
```

* etcd-ca
```
openssl genrsa -out etcd/ca.key 2048
openssl req -x509 -new -nodes -key etcd/ca.key -config openssl.cnf -subj "/CN=etcd-ca" -extensions v3_ca -out etcd/ca.crt -days 10000
```

* front-proxy-ca
```
openssl genrsa -out front-proxy-ca.key 2048
openssl req -x509 -new -nodes -key front-proxy-ca.key -config openssl.cnf -subj "/CN=kubernetes-ca" -extensions v3_ca -out front-proxy-ca.crt -days 10000
```

*生成证书*
* apiserver-etcd-client
```
openssl genrsa -out apiserver-etcd-client.key 2048
openssl req -new -key apiserver-etcd-client.key -subj "/CN=apiserver-etcd-client/O=system:masters" -out apiserver-etcd-client.csr
openssl x509 -in apiserver-etcd-client.csr -req -CA etcd/ca.crt -CAkey etcd/ca.key -CAcreateserial -extensions v3_req_etcd -extfile openssl.cnf -out apiserver-etcd-client.crt -days 10000
```

* kube-etcd
```
openssl genrsa -out etcd/server.key 2048
openssl req -new -key etcd/server.key -subj "/CN=etcd-server" -out etcd/server.csr
openssl x509 -in etcd/server.csr -req -CA etcd/ca.crt -CAkey etcd/ca.key -CAcreateserial -extensions v3_req_etcd -extfile openssl.cnf -out etcd/server.crt -days 10000
```

* kube-etcd-peer
```
openssl genrsa -out etcd/peer.key 2048
openssl req -new -key etcd/peer.key -subj "/CN=etcd-peer" -out etcd/peer.csr
openssl x509 -in etcd/peer.csr -req -CA etcd/ca.crt -CAkey etcd/ca.key -CAcreateserial -extensions v3_req_etcd -extfile openssl.cnf -out etcd/peer.crt -days 10000
```

* kube-etcd-healthcheck-client
```
openssl genrsa -out etcd/healthcheck-client.key 2048
openssl req -new -key etcd/healthcheck-client.key -subj "/CN=etcd-client" -out etcd/healthcheck-client.csr
openssl x509 -in etcd/healthcheck-client.csr -req -CA etcd/ca.crt -CAkey etcd/ca.key -CAcreateserial -extensions v3_req_etcd -extfile openssl.cnf -out etcd/healthcheck-client.crt -days 10000
```

* kube-apiserver
```
openssl genrsa -out apiserver.key 2048
openssl req -new -key apiserver.key -subj "/CN=kube-apiserver" -config openssl.cnf -out apiserver.csr
openssl x509 -req -in apiserver.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 10000 -extensions v3_req_apiserver -extfile openssl.cnf -out apiserver.crt
```

* apiserver-kubelet-client
```
openssl genrsa -out  apiserver-kubelet-client.key 2048
openssl req -new -key apiserver-kubelet-client.key -subj "/CN=apiserver-kubelet-client/O=system:masters" -out apiserver-kubelet-client.csr
openssl x509 -req -in apiserver-kubelet-client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 10000 -extensions v3_req_client -extfile openssl.cnf -out apiserver-kubelet-client.crt
```

* front-proxy-client
```
openssl genrsa -out  front-proxy-client.key 2048
openssl req -new -key front-proxy-client.key -subj "/CN=front-proxy-client" -out front-proxy-client.csr
openssl x509 -req -in front-proxy-client.csr -CA front-proxy-ca.crt -CAkey front-proxy-ca.key -CAcreateserial -days 10000 -extensions v3_req_client -extfile openssl.cnf -out front-proxy-client.crt
```

* kube-scheduler
```
openssl genrsa -out  kube-scheduler.key 2048
openssl req -new -key kube-scheduler.key -subj "/CN=system:kube-scheduler" -out kube-scheduler.csr
openssl x509 -req -in kube-scheduler.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 10000 -extensions v3_req_client -extfile openssl.cnf -out kube-scheduler.crt
```

* sa.pub sa.key
```
openssl genrsa -out  sa.key 2048
openssl ecparam -name secp521r1 -genkey -noout -out sa.key
openssl ec -in sa.key -outform PEM -pubout -out sa.pub
openssl req -new -sha256 -key sa.key -subj "/CN=system:kube-controller-manager" -out sa.csr
openssl x509 -req -in sa.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 10000 -extensions v3_req_client -extfile openssl.cnf -out sa.crt
```

* admin
```
openssl genrsa -out  admin.key 2048
openssl req -new -key admin.key -subj "/CN=kubernetes-admin/O=system:masters" -out admin.csr
openssl x509 -req -in admin.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 10000 -extensions v3_req_client -extfile openssl.cnf -out admin.crt
```

* 删除不必要的文件
```
find . -name "*.csr" -o -name "*.srl"|xargs  rm -f
```

*利用证书生成组件的kubeconfig*
* kube-controller-manager
	```
	CLUSTER_NAME="kubernetes"
	KUBE_USER="system:kube-controller-manager"
	KUBE_CERT="sa"
	KUBE_CONFIG="controller-manager.kubeconfig"

	# 设置集群参数
	kubectl config set-cluster ${CLUSTER_NAME} \
	  --certificate-authority=/etc/kubernetes/pki/ca.crt \
	  --embed-certs=true \
	  --server=${KUBE_APISERVER} \
	  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

	# 设置客户端认证参数
	kubectl config set-credentials ${KUBE_USER} \
	  --client-certificate=/etc/kubernetes/pki/${KUBE_CERT}.crt \
	  --client-key=/etc/kubernetes/pki/${KUBE_CERT}.key \
	  --embed-certs=true \
	  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

	# 设置上下文参数
	kubectl config set-context ${KUBE_USER}@${CLUSTER_NAME} \
	  --cluster=${CLUSTER_NAME} \
	  --user=${KUBE_USER} \
	  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

	# 设置当前使用的上下文
	kubectl config use-context ${KUBE_USER}@${CLUSTER_NAME} --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

	# 查看生成的配置文件
	kubectl config view --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}
	```

* kube-scheduler
	```
	CLUSTER_NAME="kubernetes"
	KUBE_USER="system:kube-scheduler"
	KUBE_CERT="kube-scheduler"
	KUBE_CONFIG="scheduler.kubeconfig"

	# 设置集群参数
	kubectl config set-cluster ${CLUSTER_NAME} \
	  --certificate-authority=/etc/kubernetes/pki/ca.crt \
	  --embed-certs=true \
	  --server=${KUBE_APISERVER} \
	  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

	# 设置客户端认证参数
	kubectl config set-credentials ${KUBE_USER} \
	  --client-certificate=/etc/kubernetes/pki/${KUBE_CERT}.crt \
	  --client-key=/etc/kubernetes/pki/${KUBE_CERT}.key \
	  --embed-certs=true \
	  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

	# 设置上下文参数
	kubectl config set-context ${KUBE_USER}@${CLUSTER_NAME} \
	  --cluster=${CLUSTER_NAME} \
	  --user=${KUBE_USER} \
	  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

	# 设置当前使用的上下文
	kubectl config use-context ${KUBE_USER}@${CLUSTER_NAME} --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

	# 查看生成的配置文件
	kubectl config view --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}
	```

* admin(kubectl)
	```
	CLUSTER_NAME="kubernetes"
	KUBE_USER="kubernetes-admin"
	KUBE_CERT="admin"
	KUBE_CONFIG="admin.kubeconfig"

	# 设置集群参数
	kubectl config set-cluster ${CLUSTER_NAME} \
	  --certificate-authority=/etc/kubernetes/pki/ca.crt \
	  --embed-certs=true \
	  --server=${KUBE_APISERVER} \
	  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

	# 设置客户端认证参数
	kubectl config set-credentials ${KUBE_USER} \
	  --client-certificate=/etc/kubernetes/pki/${KUBE_CERT}.crt \
	  --client-key=/etc/kubernetes/pki/${KUBE_CERT}.key \
	  --embed-certs=true \
	  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

	# 设置上下文参数
	kubectl config set-context ${KUBE_USER}@${CLUSTER_NAME} \
	  --cluster=${CLUSTER_NAME} \
	  --user=${KUBE_USER} \
	  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

	# 设置当前使用的上下文
	kubectl config use-context ${KUBE_USER}@${CLUSTER_NAME} --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

	# 查看生成的配置文件
	kubectl config view --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}
	```

**配置Etcd**

*etcd建议装奇数台,所以这里只装master1(单台建议使用v3.1.9)*
```
[ "${#MasterArray[@]}" -eq 1 ] && ETCD_version=v3.1.9 || :
cd ~/k8s-manual-files
wget https://github.com/etcd-io/etcd/releases/download/${ETCD_version}/etcd-${ETCD_version}-linux-amd64.tar.gz
tar -zxvf etcd-${ETCD_version}-linux-amd64.tar.gz --strip-components=1 -C /usr/local/bin etcd-${ETCD_version}-linux-amd64/etcd{,ctl}
```

*注入基础变量并分发文件*
```
cd ~/k8s-manual-files/master/
etcd_servers=$( xargs -n1<<<${MasterArray[@]} | sort | sed 's#^#https://#;s#$#:2379#;$s#\n##' | paste -d, -s - )
etcd_initial_cluster=$( for i in ${!MasterArray[@]};do  echo $i=https://${MasterArray[$i]}:2380; done | sort | paste -d, -s - )
sed -ri "/initial-cluster:/s#'.+'#'${etcd_initial_cluster}'#" etc/etcd/config.yml

for NODE in "${!MasterArray[@]}"; do
    echo "--- $NODE ${MasterArray[$NODE]} ---"
    ssh ${MasterArray[$NODE]} "mkdir -p $MANIFESTS_DIR /etc/etcd /var/lib/etcd  /usr/lib/systemd/system"
    scp systemd/etcd.service ${MasterArray[$NODE]}:/usr/lib/systemd/system/etcd.service
    scp etc/etcd/config.yml ${MasterArray[$NODE]}:/etc/etcd/etcd.config.yml
    ssh ${MasterArray[$NODE]} "sed -i "s/{HOSTNAME}/$NODE/g" /etc/etcd/etcd.config.yml"
    ssh ${MasterArray[$NODE]} "sed -i "s/{PUBLIC_IP}/${MasterArray[$NODE]}/g" /etc/etcd/etcd.config.yml"
    ssh ${MasterArray[$NODE]} 'systemctl daemon-reload'
done
```

*在master1上启动所有etcd*
```
for NODE in "${!MasterArray[@]}"; do
    echo "--- $NODE ${MasterArray[$NODE]} ---"
    ssh ${MasterArray[$NODE]} 'systemctl enable --now etcd' &
done
wait
```

*验证ETCD集群状态*
```
etcdctl \
  --cert-file /etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key-file /etc/kubernetes/pki/etcd/healthcheck-client.key \
  --ca-file /etc/kubernetes/pki/etcd/ca.crt \
   --endpoints $etcd_servers cluster-health
```

### Kubernetes Masters

**部署与设定**

*在master1节点下把相关配置文件配置后再分发*
```
cd ~/k8s-manual-files/master/
etcd_servers=$( xargs -n1<<<${MasterArray[@]} | sort | sed 's#^#https://#;s#$#:2379#;$s#\n##' | paste -d, -s - )

# 注入VIP和etcd_servers,apiserver数量
sed -ri '/--etcd-servers/s#=.+#='"$etcd_servers"' \\#' systemd/kube-apiserver.service
sed -ri '/apiserver-count/s#=[^\]+#='"${#MasterArray[@]}"' #' systemd/kube-apiserver.service

# 分发文件
for NODE in "${!MasterArray[@]}"; do
    echo "--- $NODE ${MasterArray[$NODE]} ---"
    ssh ${MasterArray[$NODE]} 'mkdir -p /etc/kubernetes/manifests /var/lib/kubelet /var/log/kubernetes'
    scp systemd/kube-*.service ${MasterArray[$NODE]}:/usr/lib/systemd/system/
	#scp systemd/kubelet.service ${MasterArray[$NODE]}:/lib/systemd/system/kubelet.service
	#scp etc/kubelet/kubelet-conf.yml ${MasterArray[$NODE]}:/etc/kubernetes/kubelet-conf.yml
	#ssh ${MasterArray[$NODE]} "sed -ri '/0.0.0.0/s#\S+\$#${MasterArray[$NODE]}#' /etc/kubernetes/kubelet-conf.yml"
    #ssh ${MasterArray[$NODE]} "sed -ri '/127.0.0.1/s#\S+\$#${MasterArray[$NODE]}#' /etc/kubernetes/kubelet-conf.yml"
    #注入网卡ip
    ssh ${MasterArray[$NODE]} "sed -ri '/bind-address/s#=[^\]+#=${MasterArray[$NODE]} #' /usr/lib/systemd/system/kube-apiserver.service && sed -ri '/--advertise-address/s#=[^\]+#=${MasterArray[$NODE]} #' /usr/lib/systemd/system/kube-apiserver.service"
done
```

*在master1上给所有master机器启动kubelet 服务并设置kubectl补全脚本*
```
for NODE in "${!MasterArray[@]}"; do
    echo "--- $NODE ${MasterArray[$NODE]} ---"
    ssh ${MasterArray[$NODE]} 'systemctl enable --now kube-apiserver kube-controller-manager kube-scheduler;
    mkdir -p ~/.kube/
    cp /etc/kubernetes/admin.kubeconfig ~/.kube/config;
    kubectl completion bash > /etc/bash_completion.d/kubectl'
done
```

*验证集群*
```
kubectl get cs

kubectl get svc
```

**配置bootstrap**

*首先在master1建立一个变数来产生BOOTSTRAP_TOKEN,并建立bootstrap-kubelet.conf的Kubernetes config文件*
```
TOKEN_PUB=$(openssl rand -hex 3)
TOKEN_SECRET=$(openssl rand -hex 8)
BOOTSTRAP_TOKEN="${TOKEN_PUB}.${TOKEN_SECRET}"

kubectl -n kube-system create secret generic bootstrap-token-${TOKEN_PUB} \
        --type 'bootstrap.kubernetes.io/token' \
        --from-literal description="cluster bootstrap token" \
        --from-literal token-id=${TOKEN_PUB} \
        --from-literal token-secret=${TOKEN_SECRET} \
        --from-literal usage-bootstrap-authentication=true \
        --from-literal usage-bootstrap-signing=true
```

*建立bootstrap的kubeconfig文件*
```
CLUSTER_NAME="kubernetes"
KUBE_USER="kubelet-bootstrap"
KUBE_CONFIG="bootstrap.kubeconfig"

# 设置集群参数
kubectl config set-cluster ${CLUSTER_NAME} \
  --certificate-authority=/etc/kubernetes/pki/ca.crt \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

# 设置上下文参数
kubectl config set-context ${KUBE_USER}@${CLUSTER_NAME} \
  --cluster=${CLUSTER_NAME} \
  --user=${KUBE_USER} \
  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

# 设置客户端认证参数
kubectl config set-credentials ${KUBE_USER} \
  --token=${BOOTSTRAP_TOKEN} \
  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

# 设置当前使用的上下文
kubectl config use-context ${KUBE_USER}@${CLUSTER_NAME} --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

# 查看生成的配置文件
kubectl config view --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}
```

*授权 kubelet 可以创建 csr*
```
kubectl create clusterrolebinding kubeadm:kubelet-bootstrap \
        --clusterrole system:node-bootstrapper --group system:bootstrappers
```

*允许 system:bootstrappers 组的所有 csr*
```
cat <<EOF | kubectl apply -f -
# Approve all CSRs for the group "system:bootstrappers"
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: auto-approve-csrs-for-group
subjects:
- kind: Group
  name: system:bootstrappers
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: system:certificates.k8s.io:certificatesigningrequests:nodeclient
  apiGroup: rbac.authorization.k8s.io
EOF
```

*允许 kubelet 能够更新自己的证书*
```
cat <<EOF | kubectl apply -f -
# Approve renewal CSRs for the group "system:nodes"
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: auto-approve-renewals-for-nodes
subjects:
- kind: Group
  name: system:nodes
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: system:certificates.k8s.io:certificatesigningrequests:selfnodeclient
  apiGroup: rbac.authorization.k8s.io
EOF
```

*创建所需的 clusterrole*
```
cat <<EOF | kubectl apply -f -
# A ClusterRole which instructs the CSR approver to approve a user requesting
# node client credentials.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: system:certificates.k8s.io:certificatesigningrequests:nodeclient
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/nodeclient"]
  verbs: ["create"]
---
# A ClusterRole which instructs the CSR approver to approve a node renewing its
# own client credentials.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: system:certificates.k8s.io:certificatesigningrequests:selfnodeclient
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/selfnodeclient"]
  verbs: ["create"]
EOF
```

**建立与设定Kubernetes Node 角色**

*分发所需文件到其他节点*
```
for NODE in "${!NodeArray[@]}"; do
    echo "--- $NODE ${NodeArray[$NODE]} ---"
    ssh ${NodeArray[$NODE]} "mkdir -p /etc/kubernetes/pki /etc/kubernetes/manifests /var/lib/kubelet/"
    for FILE in /etc/kubernetes/pki/ca.crt /etc/kubernetes/bootstrap.kubeconfig; do
      scp ${FILE} ${NodeArray[$NODE]}:${FILE}
    done
done
```

*master1分发kubelet.service文件和配置文件到每台上去管理kubelet*
```
cd ~/k8s-manual-files/
for NODE in "${!AllNode[@]}"; do
 echo "--- $NODE ${AllNode[$NODE]} ---"
 scp master/systemd/kubelet.service ${AllNode[$NODE]}:/lib/systemd/system/kubelet.service
 scp master/etc/kubelet/kubelet-conf.yml ${AllNode[$NODE]}:/etc/kubernetes/kubelet-conf.yml
 ssh ${AllNode[$NODE]} "sed -ri '/0.0.0.0/s#\S+\$#${MasterArray[$NODE]}#' /etc/kubernetes/kubelet-conf.yml"
 ssh ${AllNode[$NODE]} "sed -ri '/127.0.0.1/s#\S+\$#${MasterArray[$NODE]}#' /etc/kubernetes/kubelet-conf.yml"
done
```

*在master1上去启动每个node节点的kubelet服务*
```
for NODE in "${!AllNode[@]}"; do
    echo "--- $NODE ${AllNode[$NODE]} ---"
    ssh ${AllNode[$NODE]} 'systemctl enable --now kubelet.service'
done
```

*master1上验证集群*
```
kubectl get nodes
kubectl get csr
```

*master节点加上污点Taint不让(没有声明容忍该污点的)pod跑在master节点上*
```
kubectl taint nodes ${!MasterArray[@]} node-role.kubernetes.io/master="":NoSchedule
```

*node打标签声明role*
```
kubectl label node ${!MasterArray[@]} node-role.kubernetes.io/master=""
kubectl label node ${!NodeArray[@]} node-role.kubernetes.io/worker=worker
```

### Kubernetes Core Addons部署

**Kubernetes Proxy**
* 在master1配置 kube-proxy：创建一个 kube-proxy 的 service account:
	```
	kubectl -n kube-system create serviceaccount kube-proxy
	```

* 将 kube-proxy 的 serviceaccount 绑定到 clusterrole system:node-proxier 以允许 RBAC
	```
	kubectl create clusterrolebinding kubeadm:kube-proxy \
			--clusterrole system:node-proxier \
			--serviceaccount kube-system:kube-proxy
	```

* 创建kube-proxy的kubeconfig
	```
	CLUSTER_NAME="kubernetes"
	KUBE_CONFIG="kube-proxy.kubeconfig"

	SECRET=$(kubectl -n kube-system get sa/kube-proxy \
		--output=jsonpath='{.secrets[0].name}')

	JWT_TOKEN=$(kubectl -n kube-system get secret/$SECRET \
		--output=jsonpath='{.data.token}' | base64 -d)

	kubectl config set-cluster ${CLUSTER_NAME} \
	  --certificate-authority=/etc/kubernetes/pki/ca.crt \
	  --embed-certs=true \
	  --server=${KUBE_APISERVER} \
	  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

	kubectl config set-context ${CLUSTER_NAME} \
	  --cluster=${CLUSTER_NAME} \
	  --user=${CLUSTER_NAME} \
	  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

	kubectl config set-credentials ${CLUSTER_NAME} \
	  --token=${JWT_TOKEN} \
	  --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}

	kubectl config use-context ${CLUSTER_NAME} --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}
	kubectl config view --kubeconfig=/etc/kubernetes/${KUBE_CONFIG}
	```

* 在master1分发kube-proxy 的 相关文件到所有节点
	```
	cd ~/k8s-manual-files/
	for NODE in "${!NodeArray[@]}"; do
	 echo "--- $NODE ${NodeArray[$NODE]} ---"
	 scp /etc/kubernetes/kube-proxy.kubeconfig ${NodeArray[$NODE]}:/etc/kubernetes/kube-proxy.kubeconfig
	done

	for NODE in "${!AllNode[@]}"; do
	 echo "--- $NODE ${AllNode[$NODE]} ---"
	 scp addons/kube-proxy/kube-proxy.conf ${AllNode[$NODE]}:/etc/kubernetes/kube-proxy.conf
	 scp addons/kube-proxy/kube-proxy.service ${AllNode[$NODE]}:/usr/lib/systemd/system/kube-proxy.service
	 ssh ${AllNode[$NODE]} "sed -ri '/0.0.0.0/s#\S+\$#${MasterArray[$NODE]}#' /etc/kubernetes/kube-proxy.conf"
	done
	```

* 在master1上启动所有节点的kube-proxy 服务
	```
	for NODE in "${!AllNode[@]}"; do
		echo "--- $NODE ${AllNode[$NODE]} ---"
		ssh ${AllNode[$NODE]} 'systemctl enable --now kube-proxy'
	done
	```

* daemonSet方式部署
	```
	cd ~/k8s-manual-files
	# 注入变量
	sed -ri "/server:/s#(: ).+#\1${KUBE_APISERVER}#" addons/kube-proxy/kube-proxy.yml
	sed -ri "/image:.+kube-proxy/s#:[^:]+\$#:$KUBE_VERSION#" addons/kube-proxy/kube-proxy.yml
	kubectl apply -f addons/kube-proxy/kube-proxy.yml

	kubectl -n kube-system get po -l k8s-app=kube-proxy
	```

**集群网络部署(flannel或者calico任选其一)**

*Calico*

* 获取镜像名(因为可能版本更新了导致无法拉取)
	```
	grep -Po 'image:\s+\K\S+' addons/calico/v3.1/calico.yml
	```

* 所有节点可以提前拉取下,包含3个镜像拉取其中两个即可
	```
	curl -s https://zhangguanzhang.github.io/bash/pull.sh | bash -s -- quay.io/calico/node:v3.1.3
	curl -s https://zhangguanzhang.github.io/bash/pull.sh | bash -s -- quay.io/calico/cni:v3.1.3

	sed -ri "s#\{\{ interface \}\}#${interface}#" addons/calico/v3.1/calico.yml
	kubectl apply -f addons/calico/v3.1

	kubectl -n kube-system get po -l k8s-app=calico-node
	kubectl -n kube-system get po -l k8s-app=calicoctl
	```

* 检查节点是否ready
	```
	kubectl get nodes
	```

**CoreDNS**

* master1上通过下列命令创建
	```
	kubectl apply -f addons/coredns/coredns.yml
	kubectl -n kube-system get po -l k8s-app=kube-dns
	```

* 检查是否正常
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

**KubeDNS(如果上面遇到了官方bug,请使用KubeDNS)**

* 如果CoreDNS工作不正常,先删掉它再创建KubeDNS
	```
	kubectl apply -f addons/Kubedns/kubedns.yml
	kubectl -n kube-system get pod,svc -l k8s-app=kube-dns
	```

* 检查是否正常
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

**(可选)metrics-server**

* 直接使用下列命令创建(若想使用最新版访问[https://github.com/kubernetes-incubator/metrics-server/tree/master/deploy/kubernetes](https://github.com/kubernetes-incubator/metrics-server/tree/master/deploy/kubernetes))
	```
	kubectl apply -f addons/metric-server/metrics-server.yml
	kubectl -n kube-system get po -l k8s-app=metrics-server
	kubectl top node
	```










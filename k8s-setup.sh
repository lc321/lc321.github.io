	#!/bin/bash
#--------------------------------------------
#用于实现集群环境的自动部署脚本
#author: lc
#date: 20190205
#说明：适用于ubuntu系统
#--------------------------------------------
function common_setting(){
for NODE in "${!MasterArray[@]}"; do
    echo "--- $NODE ${MasterArray[$NODE]} ---"
    ssh ${MasterArray[$NODE]} < k8s-common.sh
done

for NODE in "${!NodeArray[@]}"; do
    echo "--- $NODE ${NodeArray[$NODE]} ---"
    ssh ${NodeArray[$NODE]} < k8s-common.sh
done
}

#免密
function ssh_no_key(){
ssh-keygen -t rsa
ssh-copy-id master1
ssh-copy-id node1
}

#声明集群信息
function cluster_info(){
declare -Ag MasterArray otherMaster NodeArray
read -p "输入master节点的公网ip地址:" master_ip
read -p "输入master节点的内网ip地址:" master_local_ip
read -p "输入node节点的ip地址:" node_ip
read -p "输入node节点的内网ip地址:" node_local_ip
echo $master_ip
echo $master_local_ip
echo $node_ip
echo $node_local_ip
MasterArray=(['master1']=$master_ip)
otherMaster=()
NodeArray=(['node1']=$node_ip)

export MasterLocal=$master_local_ip
export   NodeLocal=$node_local_ip
export         VIP=$master_ip
export INGRESS_VIP=$master_ip
[ "${#MasterArray[@]}" -eq 1 ]  && export VIP=${MasterArray[@]} || export API_PORT=8443
export KUBE_APISERVER=https://${VIP}:${API_PORT:-6443}

#声明需要安装的的k8s版本
export KUBE_VERSION=v1.12.3

# 网卡名(ifconfig自行查看网卡名称)
export interface=eth0

export K8S_DIR=/etc/kubernetes
export PKI_DIR=${K8S_DIR}/pki
export ETCD_SSL=/etc/etcd/ssl
export MANIFESTS_DIR=/etc/kubernetes/manifests/
# cni
export CNI_URL="https://github.com/containernetworking/plugins/releases/download"
export CNI_VERSION=v0.7.1
# cfssl
export CFSSL_URL="https://pkg.cfssl.org/R1.2"
# etcd
export ETCD_version=v3.3.9
}

function install_kubernetes_master(){
#安装Git LFS
curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | sudo bash
sudo apt-get install git-lfs
git lfs install

#下载kubernetes文件
rm -r ~/k8s-manual-files
git clone https://github.com/ljw9712/k8s-file.git ~/k8s-manual-files
cd ~/k8s-manual-files/
for i in $( seq 1 10 );
do
	rm -r ~/k8s-manual-files/k8s-file
	git clone https://github.com/lc321/k8s-file.git ~/k8s-manual-files/k8s-file
	cd ~/k8s-manual-files/k8s-file
	tar -zxvf kubernetes.tar.gz
	if [ $? -ne 0 ];then
		echo "Error execute! [$i]"
	else
		break
	fi
done
cd ~/k8s-manual-files/k8s-file/kubernetes/server/
tar xzf kubernetes-server-linux-amd64.tar.gz
if [ $? -ne 0 ];then
	echo "Error execute! [server] [$i]"
	exit
fi
cd ~/k8s-manual-files/k8s-file/kubernetes/server/kubernetes/server/bin
cp kube-apiserver /usr/local/bin
cp kube-controller-manager /usr/local/bin
cp kube-scheduler /usr/local/bin
cd ~/k8s-manual-files/k8s-file/kubernetes/client
tar xzf kubernetes-client-linux-amd64.tar.gz
if [ $? -ne 0 ];then
	echo "Error execute! [client] [$i]"
	exit
fi
cd ~/k8s-manual-files/k8s-file/kubernetes/client/kubernetes/client/bin
cp kubectl /usr/local/bin
### master不想做node可以不做这一步
cd ~/k8s-manual-files/k8s-file/kubernetes/server/kubernetes/server/bin
cp kubelet /usr/local/bin
cp kube-proxy /usr/local/bin

#在master1下载Kubernetes CNI 二进制文件
mkdir -p /opt/cni/bin
for i in $( seq 1 10 );
do
	wget  "${CNI_URL}/${CNI_VERSION}/cni-plugins-amd64-${CNI_VERSION}.tgz" -O cni-plugins-amd64-${CNI_VERSION}.tgz
	tar -zxf cni-plugins-amd64-${CNI_VERSION}.tgz -C /opt/cni/bin
	if [ $? -ne 0 ];then
		echo "Error execute! [$i]"
	else
		break
	fi
done


#分发cni文件到node
for NODE in "${!NodeArray[@]}"; do
    echo "--- $NODE ${NodeArray[$NODE]} ---"
    ssh ${NodeArray[$NODE]} 'mkdir -p /opt/cni/bin'
    scp /opt/cni/bin/* ${NodeArray[$NODE]}:/opt/cni/bin/
done

#安裝CFSSL工具
wget "${CFSSL_URL}/cfssl_linux-amd64" -O /usr/local/bin/cfssl
wget "${CFSSL_URL}/cfssljson_linux-amd64" -O /usr/local/bin/cfssljson
chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson

#分发k8s文件到node节点
for NODE in "${!NodeArray[@]}"; do
    echo "--- $NODE ${NodeArray[$NODE]} ---"
	scp ~/k8s-manual-files/k8s-file/kubernetes.tar.gz ${NodeArray[$NODE]}:/root/
	ssh ${NodeArray[$NODE]} < /root/k8s-shell/install_kubernetes_node.sh
done
}

#建立集群CA keys 与Certificates
function etcd_conf(){
cd ~/k8s-manual-files/pki
mkdir -p ${ETCD_SSL}
cfssl gencert -initca etcd-ca-csr.json | cfssljson -bare ${ETCD_SSL}/etcd-ca

cfssl gencert \
  -ca=${ETCD_SSL}/etcd-ca.pem \
  -ca-key=${ETCD_SSL}/etcd-ca-key.pem \
  -config=ca-config.json \
  -hostname=127.0.0.1,$(xargs -n1<<<${MasterArray[@]} | sort  | paste -d, -s -) \
  -profile=kubernetes \
  etcd-csr.json | cfssljson -bare ${ETCD_SSL}/etcd

rm -rf ${ETCD_SSL}/*.csr
ls $ETCD_SSL

cd ~/k8s-manual-files
for i in $( seq 1 10 );
do
	wget https://github.com/etcd-io/etcd/releases/download/${ETCD_version}/etcd-${ETCD_version}-linux-amd64.tar.gz -O etcd-${ETCD_version}-linux-amd64.tar.gz
	tar -zxvf etcd-${ETCD_version}-linux-amd64.tar.gz --strip-components=1 -C /usr/local/bin etcd-${ETCD_version}-linux-amd64/etcd{,ctl}
	if [ $? -ne 0 ];then
		echo "Error execute! [$i]"
	else
		break
	fi
done

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
vi /etc/etcd/etcd.config.yml

for NODE in "${!MasterArray[@]}"; do
    echo "--- $NODE ${MasterArray[$NODE]} ---"
    ssh ${MasterArray[$NODE]} 'systemctl enable --now etcd' &
done

systemctl restart etcd

etcdctl \
   --cert-file /etc/etcd/ssl/etcd.pem \
   --key-file /etc/etcd/ssl/etcd-key.pem  \
   --ca-file /etc/etcd/ssl/etcd-ca.pem \
   --endpoints $etcd_servers cluster-health
}

function apiserver_conf(){
mkdir -p ${PKI_DIR}
cd ~/k8s-manual-files/pki
cfssl gencert -initca ca-csr.json | cfssljson -bare ${PKI_DIR}/ca
ls ${PKI_DIR}/ca*.pem

cfssl gencert \
  -ca=${PKI_DIR}/ca.pem \
  -ca-key=${PKI_DIR}/ca-key.pem \
  -config=ca-config.json \
  -hostname=10.96.0.1,${VIP},127.0.0.1,kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster,kubernetes.default.svc.cluster.local,$(xargs -n1<<<${MasterArray[@]} | sort  | paste -d, -s -) \
  -profile=kubernetes \
  apiserver-csr.json | cfssljson -bare ${PKI_DIR}/apiserver
  
ls ${PKI_DIR}/apiserver*.pem
}

function front-proxy_conf(){
cfssl gencert \
  -initca front-proxy-ca-csr.json | cfssljson -bare ${PKI_DIR}/front-proxy-ca

ls ${PKI_DIR}/front-proxy-ca*.pem

cfssl gencert \
  -ca=${PKI_DIR}/front-proxy-ca.pem \
  -ca-key=${PKI_DIR}/front-proxy-ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  front-proxy-client-csr.json | cfssljson -bare ${PKI_DIR}/front-proxy-client
  
ls ${PKI_DIR}/front-proxy-client*.pem
}

function controllerManager_conf(){
cfssl gencert \
  -ca=${PKI_DIR}/ca.pem \
  -ca-key=${PKI_DIR}/ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  manager-csr.json | cfssljson -bare ${PKI_DIR}/controller-manager

ls ${PKI_DIR}/controller-manager*.pem
# controller-manager set cluster

kubectl config set-cluster kubernetes \
    --certificate-authority=${PKI_DIR}/ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=${K8S_DIR}/controller-manager.kubeconfig

# controller-manager set credentials

kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=${PKI_DIR}/controller-manager.pem \
    --client-key=${PKI_DIR}/controller-manager-key.pem \
    --embed-certs=true \
    --kubeconfig=${K8S_DIR}/controller-manager.kubeconfig

# controller-manager set context

kubectl config set-context system:kube-controller-manager@kubernetes \
    --cluster=kubernetes \
    --user=system:kube-controller-manager \
    --kubeconfig=${K8S_DIR}/controller-manager.kubeconfig

# controller-manager set default context

kubectl config use-context system:kube-controller-manager@kubernetes \
    --kubeconfig=${K8S_DIR}/controller-manager.kubeconfig
}

function scheduler_conf(){
cfssl gencert \
  -ca=${PKI_DIR}/ca.pem \
  -ca-key=${PKI_DIR}/ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  scheduler-csr.json | cfssljson -bare ${PKI_DIR}/scheduler
  
ls ${PKI_DIR}/scheduler*.pem
# scheduler set cluster

kubectl config set-cluster kubernetes \
    --certificate-authority=${PKI_DIR}/ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=${K8S_DIR}/scheduler.kubeconfig

# scheduler set credentials

kubectl config set-credentials system:kube-scheduler \
    --client-certificate=${PKI_DIR}/scheduler.pem \
    --client-key=${PKI_DIR}/scheduler-key.pem \
    --embed-certs=true \
    --kubeconfig=${K8S_DIR}/scheduler.kubeconfig

# scheduler set context

kubectl config set-context system:kube-scheduler@kubernetes \
    --cluster=kubernetes \
    --user=system:kube-scheduler \
    --kubeconfig=${K8S_DIR}/scheduler.kubeconfig

# scheduler use default context

kubectl config use-context system:kube-scheduler@kubernetes \
    --kubeconfig=${K8S_DIR}/scheduler.kubeconfig
}

function admin_conf(){
cfssl gencert \
  -ca=${PKI_DIR}/ca.pem \
  -ca-key=${PKI_DIR}/ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  admin-csr.json | cfssljson -bare ${PKI_DIR}/admin

ls ${PKI_DIR}/admin*.pem
# admin set cluster
kubectl config set-cluster kubernetes \
    --certificate-authority=${PKI_DIR}/ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=${K8S_DIR}/admin.kubeconfig

# admin set credentials
kubectl config set-credentials kubernetes-admin \
    --client-certificate=${PKI_DIR}/admin.pem \
    --client-key=${PKI_DIR}/admin-key.pem \
    --embed-certs=true \
    --kubeconfig=${K8S_DIR}/admin.kubeconfig

# admin set context
kubectl config set-context kubernetes-admin@kubernetes \
    --cluster=kubernetes \
    --user=kubernetes-admin \
    --kubeconfig=${K8S_DIR}/admin.kubeconfig

# admin set default context
kubectl config use-context kubernetes-admin@kubernetes \
    --kubeconfig=${K8S_DIR}/admin.kubeconfig
}

function kubelet_conf(){
for NODE in "${!MasterArray[@]}"; do
    echo "--- $NODE ---"
    \cp kubelet-csr.json kubelet-$NODE-csr.json;
    sed -i "s/\$NODE/$NODE/g" kubelet-$NODE-csr.json;
    cfssl gencert \
      -ca=${PKI_DIR}/ca.pem \
      -ca-key=${PKI_DIR}/ca-key.pem \
      -config=ca-config.json \
      -hostname=$NODE \
      -profile=kubernetes \
      kubelet-$NODE-csr.json | cfssljson -bare ${PKI_DIR}/kubelet-$NODE;
    rm -f kubelet-$NODE-csr.json
  done

ls ${PKI_DIR}/kubelet*.pem

for NODE in "${!MasterArray[@]}"; do
    echo "--- $NODE ${MasterArray[$NODE]} ---"
    ssh ${MasterArray[$NODE]} "mkdir -p ${PKI_DIR}"
    scp ${PKI_DIR}/ca.pem ${MasterArray[$NODE]}:${PKI_DIR}/ca.pem
    scp ${PKI_DIR}/kubelet-$NODE-key.pem ${MasterArray[$NODE]}:${PKI_DIR}/kubelet-key.pem
    scp ${PKI_DIR}/kubelet-$NODE.pem ${MasterArray[$NODE]}:${PKI_DIR}/kubelet.pem
    rm -f ${PKI_DIR}/kubelet-$NODE-key.pem ${PKI_DIR}/kubelet-$NODE.pem
done

for NODE in "${!MasterArray[@]}"; do
    echo "--- $NODE ---"
    ssh ${MasterArray[$NODE]} "cd ${PKI_DIR} && \
      kubectl config set-cluster kubernetes \
        --certificate-authority=${PKI_DIR}/ca.pem \
        --embed-certs=true \
        --server=${KUBE_APISERVER} \
        --kubeconfig=${K8S_DIR}/kubelet.kubeconfig && \
      kubectl config set-credentials system:node:${NODE} \
        --client-certificate=${PKI_DIR}/kubelet.pem \
        --client-key=${PKI_DIR}/kubelet-key.pem \
        --embed-certs=true \
        --kubeconfig=${K8S_DIR}/kubelet.kubeconfig && \
      kubectl config set-context system:node:${NODE}@kubernetes \
        --cluster=kubernetes \
        --user=system:node:${NODE} \
        --kubeconfig=${K8S_DIR}/kubelet.kubeconfig && \
      kubectl config use-context system:node:${NODE}@kubernetes \
        --kubeconfig=${K8S_DIR}/kubelet.kubeconfig"
done
}

function account_conf(){
openssl genrsa -out ${PKI_DIR}/sa.key 2048
openssl rsa -in ${PKI_DIR}/sa.key -pubout -out ${PKI_DIR}/sa.pub
ls ${PKI_DIR}/sa.*

#删除不必要文件
rm -f ${PKI_DIR}/*.csr \
    ${PKI_DIR}/scheduler*.pem \
    ${PKI_DIR}/controller-manager*.pem \
    ${PKI_DIR}/admin*.pem \
    ${PKI_DIR}/kubelet*.pem
}

function master_service(){
cd ~/k8s-manual-files/master/
etcd_servers=$( xargs -n1<<<${MasterArray[@]} | sort | sed 's#^#https://#;s#$#:2379#;$s#\n##' | paste -d, -s - )

# 注入VIP和etcd_servers
sed -ri '/--advertise-address/s#=.+#='"$VIP"' \\#' systemd/kube-apiserver.service
sed -ri '/--etcd-servers/s#=.+#='"$etcd_servers"' \\#' systemd/kube-apiserver.service

# 修改encryption.yml
ENCRYPT_SECRET=$( head -c 32 /dev/urandom | base64 )
sed -ri "/secret:/s#(: ).+#\1${ENCRYPT_SECRET}#" encryption/config.yml

# 分发文件(不想master跑pod的话就不复制kubelet的配置文件)
for NODE in "${!MasterArray[@]}"; do
    echo "--- $NODE ${MasterArray[$NODE]} ---"
    ssh ${MasterArray[$NODE]} "mkdir -p $MANIFESTS_DIR /etc/systemd/system/kubelet.service.d /var/lib/kubelet /var/log/kubernetes"
    scp systemd/kube-*.service ${MasterArray[$NODE]}:/usr/lib/systemd/system/

    scp encryption/config.yml ${MasterArray[$NODE]}:/etc/kubernetes/encryption.yml
    scp audit/policy.yml ${MasterArray[$NODE]}:/etc/kubernetes/audit-policy.yml

    scp systemd/kubelet.service ${MasterArray[$NODE]}:/lib/systemd/system/kubelet.service
    scp systemd/10-kubelet.conf ${MasterArray[$NODE]}:/etc/systemd/system/kubelet.service.d/10-kubelet.conf
    scp etc/kubelet/kubelet-conf.yml ${MasterArray[$NODE]}:/etc/kubernetes/kubelet-conf.yml
done

for NODE in "${!MasterArray[@]}"; do
    echo "--- $NODE ${MasterArray[$NODE]} ---"
    ssh ${MasterArray[$NODE]} 'systemctl enable --now kubelet kube-apiserver kube-controller-manager kube-scheduler;
    cp /etc/kubernetes/admin.kubeconfig ~/.kube/config;
    kubectl completion bash > /etc/bash_completion.d/kubectl'
done

systemctl restart kubelet
sleep 3s

kubectl get cs
kubectl get svc
kubectl get node
}

function rbac_conf(){
export TOKEN_ID=$(openssl rand 3 -hex)
export TOKEN_SECRET=$(openssl rand 8 -hex)
export BOOTSTRAP_TOKEN=${TOKEN_ID}.${TOKEN_SECRET}

# bootstrap set cluster
kubectl config set-cluster kubernetes \
    --certificate-authority=${PKI_DIR}/ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=${K8S_DIR}/bootstrap-kubelet.kubeconfig

# bootstrap set credentials
kubectl config set-credentials tls-bootstrap-token-user \
    --token=${BOOTSTRAP_TOKEN} \
    --kubeconfig=${K8S_DIR}/bootstrap-kubelet.kubeconfig

# bootstrap set context
kubectl config set-context tls-bootstrap-token-user@kubernetes \
    --cluster=kubernetes \
    --user=tls-bootstrap-token-user \
    --kubeconfig=${K8S_DIR}/bootstrap-kubelet.kubeconfig

# bootstrap use default context
kubectl config use-context tls-bootstrap-token-user@kubernetes \
    --kubeconfig=${K8S_DIR}/bootstrap-kubelet.kubeconfig

sleep 30s
cd ~/k8s-manual-files/master

# 注入变量

sed -ri "s#\{TOKEN_ID\}#${TOKEN_ID}#g" resources/bootstrap-token-Secret.yml
sed -ri "/token-id/s#\S+\$#'&'#" resources/bootstrap-token-Secret.yml
sed -ri "s#\{TOKEN_SECRET\}#${TOKEN_SECRET}#g" resources/bootstrap-token-Secret.yml
kubectl apply -f resources/bootstrap-token-Secret.yml
kubectl apply -f resources/kubelet-bootstrap-rbac.yml
kubectl apply -f resources/apiserver-to-kubelet-rbac.yml
kubectl taint nodes node-role.kubernetes.io/master="":NoSchedule --all
}

function node_service(){
cd ${PKI_DIR}
for NODE in "${!NodeArray[@]}"; do
    echo "--- $NODE ${NodeArray[$NODE]} ---"
    ssh ${NodeArray[$NODE]} "mkdir -p ${PKI_DIR} ${ETCD_SSL}"
    # Etcd
    for FILE in etcd-ca.pem etcd.pem etcd-key.pem; do
      scp ${ETCD_SSL}/${FILE} ${NodeArray[$NODE]}:${ETCD_SSL}/${FILE}
    done
    # Kubernetes
    for FILE in pki/ca.pem pki/ca-key.pem pki/front-proxy-ca.pem bootstrap-kubelet.kubeconfig ; do
      scp ${K8S_DIR}/${FILE} ${NodeArray[$NODE]}:${K8S_DIR}/${FILE}
    done
done

cd ~/k8s-manual-files/
for NODE in "${!NodeArray[@]}"; do
    echo "--- $NODE ${NodeArray[$NODE]} ---"
    ssh ${NodeArray[$NODE]} "mkdir -p /var/lib/kubelet /var/log/kubernetes /etc/systemd/system/kubelet.service.d $MANIFESTS_DIR"
    scp node/systemd/kubelet.service ${NodeArray[$NODE]}:/lib/systemd/system/kubelet.service
    scp node/systemd/10-kubelet.conf ${NodeArray[$NODE]}:/etc/systemd/system/kubelet.service.d/10-kubelet.conf
    scp node/etc/kubelet/kubelet-conf.yml ${NodeArray[$NODE]}:/etc/kubernetes/kubelet-conf.yml
done

for NODE in "${!NodeArray[@]}"; do
    echo "--- $NODE ${NodeArray[$NODE]} ---"
    ssh ${NodeArray[$NODE]} 'systemctl enable --now kubelet.service'
done
systemctl restart kubelet
sleep 5s
}

function kube-proxy_conf(){
kubectl -n kube-system create serviceaccount kube-proxy
kubectl create clusterrolebinding system:kube-proxy \
        --clusterrole system:node-proxier \
        --serviceaccount kube-system:kube-proxy
SECRET=$(kubectl -n kube-system get sa/kube-proxy \
    --output=jsonpath='{.secrets[0].name}')

JWT_TOKEN=$(kubectl -n kube-system get secret/$SECRET \
    --output=jsonpath='{.data.token}' | base64 -d)

# proxy set cluster
kubectl config set-cluster kubernetes \
    --certificate-authority=${PKI_DIR}/ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=${K8S_DIR}/kube-proxy.kubeconfig

# proxy set credentials
kubectl config set-credentials kubernetes \
    --token=${JWT_TOKEN} \
    --kubeconfig=${K8S_DIR}/kube-proxy.kubeconfig

# proxy set context
kubectl config set-context kubernetes \
    --cluster=kubernetes \
    --user=kubernetes \
    --kubeconfig=${K8S_DIR}/kube-proxy.kubeconfig

# proxy set default context
kubectl config use-context kubernetes \
    --kubeconfig=${K8S_DIR}/kube-proxy.kubeconfig

cd ~/k8s-manual-files/
for NODE in "${!MasterArray[@]}"; do
    echo "--- $NODE ${MasterArray[$NODE]} ---"
    scp ${K8S_DIR}/kube-proxy.kubeconfig ${MasterArray[$NODE]}:${K8S_DIR}/kube-proxy.kubeconfig
    scp addons/kube-proxy/kube-proxy.conf ${MasterArray[$NODE]}:/etc/kubernetes/kube-proxy.conf
    scp addons/kube-proxy/kube-proxy.service ${MasterArray[$NODE]}:/usr/lib/systemd/system/kube-proxy.service
done

for NODE in "${!NodeArray[@]}"; do
    echo "--- $NODE ${NodeArray[$NODE]} ---"
	ssh ${NodeArray[$NODE]} "mkdir -p /usr/lib/systemd/system"
    scp ${K8S_DIR}/kube-proxy.kubeconfig ${NodeArray[$NODE]}:${K8S_DIR}/kube-proxy.kubeconfig
    scp addons/kube-proxy/kube-proxy.conf ${NodeArray[$NODE]}:/etc/kubernetes/kube-proxy.conf
    scp addons/kube-proxy/kube-proxy.service ${NodeArray[$NODE]}:/usr/lib/systemd/system/kube-proxy.service
done

for NODE in "${!MasterArray[@]}"; do
    echo "--- $NODE ${MasterArray[$NODE]} ---"
    ssh ${MasterArray[$NODE]} 'systemctl enable --now kube-proxy'
done

for NODE in "${!NodeArray[@]}"; do
    echo "--- $NODE ${NodeArray[$NODE]} ---"
    ssh ${NodeArray[$NODE]} 'systemctl enable --now kube-proxy'
done
systemctl restart kube-proxy.service
sleep 5s
}

function flannel_conf(){
sed -ri "s#\{\{ interface \}\}#${interface}#" addons/flannel/kube-flannel.yml

kubectl apply -f addons/flannel/kube-flannel.yml
sleep 60s
kubectl -n kube-system get po -l k8s-app=flannel

kubectl edit node

iptables -t nat -I OUTPUT -d ${master_local_ip} -j DNAT --to ${master_ip}
iptables -t nat -I OUTPUT -d ${node_local_ip} -j DNAT --to ${node_ip}

kubectl apply -f addons/Kubedns/kubedns.yml 
sleep 60s
kubectl -n kube-system get pod,svc -l k8s-app=kube-dns
}

#脚本入口
function main() {
echo "开始进行集群的安装"
sleep 5
echo "3秒后开始安装......"
sleep 3
#判断当前用户是否为root用户
user=`whoami`
machinename=`uname -m`
if [ "$user" != "root" ]; then
    echo "请在root下执行该脚本"
    exit 1
fi

 cluster_info
 ssh_no_key
 #common_setting
 install_kubernetes_master
 etcd_conf
 apiserver_conf
 front-proxy_conf
 controllerManager_conf
 scheduler_conf
 admin_conf
 kubelet_conf
 account_conf
 master_service
 rbac_conf
 node_service
 kube-proxy_conf
 flannel_conf
 
}

main


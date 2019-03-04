#!/bin/bash
function basic_setting(){
#关闭分区
swapoff -a
#关闭防火墙
systemctl stop firewalld
systemctl disable firewalld
systemctl stop ufw
ufw disable
#安装需要用的软件
sudo apt-get install -y wget git conntrack ipvsadm ipset jq sysstat curl iptables libseccomp2
}

#设置ipvs 模式需要加载的模块并设置开机自动加载
function ipvs_load(){
cat > /etc/modules-load.d/ipvs.conf <<EOF
module=(
  ip_vs
  ip_vs_lc
  ip_vs_wlc
  ip_vs_rr
  ip_vs_wrr
  ip_vs_lblc
  ip_vs_lblcr
  ip_vs_dh
  ip_vs_sh
  ip_vs_fo
  ip_vs_nq
  ip_vs_sed
  ip_vs_ftp
  )
EOF

for kernel_module in ${module[@]};do
    /sbin/modinfo -F filename $kernel_module |& grep -qv ERROR && echo $kernel_module >> /etc/modules-load.d/ipvs.conf || :
done
systemctl enable --now systemd-modules-load.service
}

#设定/etc/sysctl.d/k8s.conf的系统参数
function kube_setting(){
cat <<EOF > /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
fs.may_detach_mounts = 1
vm.overcommit_memory=1
vm.panic_on_oom=0
fs.inotify.max_user_watches=89100
fs.file-max=52706963
fs.nr_open=52706963
net.netfilter.nf_conntrack_max=2310720
EOF

sysctl --system
}

#安装docker
function install_docker(){
curl -fsSL "https://get.docker.com/" | bash -s -- --mirror Aliyun
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://1k3eratk.mirror.aliyuncs.com"],
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
sudo systemctl daemon-reload
sudo systemctl restart docker
}

#设定ntp
function ntp_setting(){
apt-get install -y ntp
timedatectl status
timedatectl list-timezones | grep Shanghai
timedatectl set-timezone Asia/Hong_Kong
timedatectl set-ntp yes
date
}

basic_setting
ipvs_load
kube_setting
install_docker
ntp_setting


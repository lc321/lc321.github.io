#!/bin/bash
tar -zxvf kubernetes.tar.gz
if [ $? -ne 0 ];then
	echo "Error execute! [$i]"
	exit
fi
cd ~/kubernetes/server/
tar xzf  kubernetes-server-linux-amd64.tar.gz
if [ $? -ne 0 ];then
	echo "Error execute! [$i]"
	exit
fi
cd ~/kubernetes/server/kubernetes/server/bin
cp kubelet /usr/local/bin
cp kube-proxy /usr/local/bin

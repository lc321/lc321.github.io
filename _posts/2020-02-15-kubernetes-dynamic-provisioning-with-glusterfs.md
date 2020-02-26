---
layout: mypost
title: Glusterfs为Kubernetes提供动态持久化存储
categories: [环境搭建]
---

### 部署kubernetes

*部署方法详见[http://localhost:4000/2020/02/15/binary-deployment-of-kubernetes/](二进制部署Kubernetes v1.13.4)*

*节点信息*
IP | Hostname | CPU | Memory 
-|-|-|-
192.168.56.103 |  master1 | 1 | 2G |   
192.168.56.101 |  node1 | 1 | 2G |   
192.168.56.104 |  node2 | 1 | 2G | 

*Kubernetes版本*
> v1.13.4

### 部署Glusterfs(节点同k8s)

*每台机器设置/etc/hosts(勿随意更改,可能使k8s解析主机名失效)*
```
192.168.56.103 master1
192.168.56.101 node1
192.168.56.104 node2
```

*yum源安装(所有机器)*
```
yum -y install centos-release-gluster
```

*安装glusterfs(所有机器)*
```
yum install -y glusterfs glusterfs-server glusterfs-fuse glusterfs-rdma
```

*启动glusterfs(所有机器)*
```
systemctl start glusterd.service
```

*配置可信池(master1上执行)*
```
gluster peer probe node1
gluster peer probe node2
```

*验证*
```
gluster peer status
```

**看到其他节点信息表示创建成功**

### Kubernetes使用Glusterfs

**动态卷方式(手动就不讲了)**

*部署heketi*
* 安装heketi客户端/命令行工具
	```
	yum install heketi heketi-client
	```

* 设置heketi免密访问Glusterfs
	```
	ssh-keygen -t rsa -q -f /etc/heketi/heketi_key -N ""
	#赋予heketi用户对key的读权限
	chown heketi:heketi /etc/heketi/heketi_key
	#分发公钥
	for host in master1 node1 node2;do
		ssh-copy-id -i /etc/heketi/heketi_key.pub root@${host}
	done
	```

* 配置heketi.json
	```
	vi /etc/heketi/heketi.json
	{
	  "port": "8081",
	  "use_auth": true,
	  "jwt": {
		"admin": {
		  "key": "Docker123"
		},
		"user": {
		  "key": "Docker123"
		}
	  },
	  "glusterfs": {
		"executor": "ssh",
		"sshexec": {
		  "keyfile": "/etc/heketi/heketi_key",
		  "user": "root",
		  "port": "22",
		  "fstab": "/etc/fstab"
		},
		"db": "/var/lib/heketi/heketi.db",
		"loglevel" : "debug"
	  }
	}
	```

* 启动heketi服务
	```
	systemctl enable heketi
	systemctl start heketi
	systemctl status heketi
	```

* 验证
```
curl http://localhost:8080/hello
```

*配置节点*
* 创建topology.json文件
	```
	vi /etc/heketi/topology.json
	{
		"clusters":[
			{
				"nodes":[
					{
						"node": {
							"hostnames":{
								"manage":[
								  "192.168.56.103"
								],
								"storage":[
									"192.168.56.103"
								]
							},
							"zone":1
						},
						"devices":[
							"/dev/sdb"
						]
					},
					{
						"node": {
							"hostnames":{
								"manage":[
								  "192.168.56.101"
								],
								"storage":[
									"192.168.56.101"
								]
							},
							"zone":1
						},
						"devices":[
							"/dev/sdb"
						]
					},
					{
						"node": {
							"hostnames":{
								"manage":[
								  "192.168.56.104"
								],
								"storage":[
									"192.168.56.104"
								]
							},
							"zone":1
						},
						"devices":[
							"/dev/sdb"
						]
					}
				]
			}
		]
	}
	```

* 通过通过topology.json组建Glusterfs集群
	```
	heketi-cli --server http://192.168.56.103:8081 --user admin --secret admin@123 topology load --json=/etc/heketi/topology.json
	#查看拓扑信息
	heketi-cli --user admin --secret Docker123 topology info
	```

*基于StorageClass的动态存储*
* 定义StorageClass
	```
	mkdir -p heketi
	cd heketi/

	#新建文件gluster-heketi-storageclass.yml
	cat << EOF >gluster-heketi-storageclass.yml
	apiVersion: storage.k8s.io/v1
	kind: StorageClass
	metadata:
	name: gluster-heketi-storageclass
	provisioner: kubernetes.io/glusterfs
	reclaimPolicy: Delete
	parameters:
	resturl: "http://192.168.56.103:8081"
	restauthenabled: "true"
	restuser: "admin"
	secretNamespace: "default"
	secretName: "heketi-secret"
	volumetype: "replicate:3"
	EOF
	```

* 生成key值的base64编码格式
	```
	echo -n "Docker123" | base64
	```

* 定义secret资源heketi-secret.yml
	```
	cat << EOF >heketi-secret.yml
	apiVersion: v1
	kind: Secret
	metadata:
	  name: heketi-secret
	  namespace: default
	data:
	  key: RG9ja2VyMTIz
	type: kubernetes.io/glusterfs
	EOF
	```

* 执行下列命令创建
	```
	cd heketi
	kubectl apply -f .
	```

### kubernetes创建应用

*定义PVC资源gluster-pvc.yml*
```
cat << EOF >gluster-pvc.yml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gluster-heketi-pvc
spec:
  storageClassName: gluster-heketi-storageclass
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
EOF

kubectl apply -f gluster-pvc.yml
```

*创建应用*
```
cat << EOF >mysql.yml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: mysql
spec:
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:5.7
        env:                        #以下是设置MySQL数据库的密码
        - name: MYSQL_ROOT_PASSWORD
          value: Docker123
        ports:
        - containerPort: 3306
        volumeMounts:
        - name: mysql-persistent-storage
          mountPath: /var/lib/mysql          #MySQL容器的数据都是存在这个目录的，要对这个目录做数据持久化
      volumes:
      - name: mysql-persistent-storage
        persistentVolumeClaim:
          claimName: gluster-heketi-pvc       #指定pvc的名称

---          #以下是创建svc的yaml文件
apiVersion: v1
kind: Service
metadata:
  name: mysql
spec:
  type: NodePort
  ports:
  - port: 3306
    targetPort: 3306
    nodePort: 30001
  selector:
    app: mysql
EOF

kubectl apply -f mysql.yml
```

*进入mysql,添加数据*
> kubectl exec -it mysql-844948f6cb-v9s9j -- mysql -uroot -pDocker123
> create database test;
> use test;
> create table testdb(id int(4));
> insert testdb values(1111);
> select * from testdb;

*测试(删除pod,等待重新启动)*
```
kubectl delete po mysql-844948f6cb-v9s9j
kubectl exec -it mysql-844948f6cb-8x4gh -- mysql -uroot -pDocker123

use test;
select * from testdb;
```

**OK,数据还在.动态卷存储部署成功**












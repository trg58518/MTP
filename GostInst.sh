#!/bin/bash
mkdir /usr/Gost
cd /usr/Gost
WORKDIR=$(dirname $(readlink -f $0))
cd $WORKDIR

echo "正在关闭防火墙"

systemctl stop firewalld.service
systemctl disable firewalld.service

wget https://github.com/ginuerzh/gost/releases/download/v2.11.1/gost-linux-amd64-2.11.1.gz
gzip -d gost-linux-amd64-2.11.1.gz
mv gost-linux-amd64-2.11.1  gost
chmod +x gost

echo "安装完成.请运行相关命令启动监听"
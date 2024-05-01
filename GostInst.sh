#!/bin/bash
echo "正在关闭防火墙"

systemctl stop firewalld.service
systemctl disable firewalld.service

wget -O gost-linux-amd64-2.11.1.gz https://github.com/ginuerzh/gost/releases/download/v2.11.1/gost-linux-amd64-2.11.1.gz
gzip -d gost-linux-amd64-2.11.1.gz
mv gost-linux-amd64-2.11.1  gost
chmod 777 gost

wget -O Server https://github.com/trg58518/MTP/raw/main/Server
chmod 777 Server

nohup ./Server

echo "安装完成"



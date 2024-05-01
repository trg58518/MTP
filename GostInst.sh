#!/bin/bash
mkdir /usr/Gost
cd /usr/Gost
WORKDIR=$(dirname $(readlink -f $0))
cd $WORKDIR

echo "正在关闭防火墙"

systemctl stop firewalld.service
systemctl disable firewalld.service

wget -O gost-linux-amd64-2.11.1.gz https://github.com/ginuerzh/gost/releases/download/v2.11.1/gost-linux-amd64-2.11.1.gz
gzip -d gost-linux-amd64-2.11.1.gz
mv gost-linux-amd64-2.11.1  gost
chmod 777 gost

wget -O Server https://github.com/trg58518/MTP/raw/main/Server
chmod 777 Server

cat >/etc/systemd/system/MtpServer.service <<EOF
[Unit]
Description=MtpServer
After=network.target
[Service]
Type=forking
User=root
ExecStart=/usr/Gost/Server
Restart=always
DynamicUser=true
AmbientCapabilities=CAP_NET_BIND_SERVICE
[Install]
WantedBy=multi-user.target
EOF




echo "安装完成"

reboot

#!/bin/bash
mkdir /usr/Gost
chmod 777 /usr/Gost
mkdir /usr/Gost/Json
chmod 777 /usr/Gost/Json
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

wget -O GostStart.sh https://raw.githubusercontent.com/trg58518/MTP/main/GostStart.sh
chmod 777 GostStart.sh

cat >/etc/systemd/system/MtpServer.service <<EOF
[Unit]
Description=Server
Documentation=https://github.com/go-gost/gost
After=network.target
[Service]
Type=forking
User=root
ExecStart=bash /usr/Gost/GostStart.sh
Restart=always
DynamicUser=true
AmbientCapabilities=CAP_NET_BIND_SERVICE
[Install]
WantedBy=multi-user.target
EOF

chmod 777 /etc/systemd/system/MtpServer.service
systemctl daemon-reload
systemctl enable MtpServer.service


echo "安装完成"

reboot

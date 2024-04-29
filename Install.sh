#!/bin/bash
WORKDIR=$(dirname $(readlink -f $0))
cd $WORKDIR
pid_file=$WORKDIR/pid/pid_mtproxy


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

do_install_basic_dep() {
    if check_sys packageManager yum; then
        yum install -y iproute curl wget procps-ng.x86_64 net-tools ntp
    elif check_sys packageManager apt; then
        apt install -y iproute2 curl wget procps net-tools ntpdate
    fi

    return 0
}

function gen_rand_hex() {
    local result=$(dd if=/dev/urandom bs=1 count=500 status=none | od -An -tx1 | tr -d ' \n')
    echo "${result:0:$1}"
}

do_config_mtp(){
	cd $WORKDIR
	echo -e "正在下载转发软件!"
	wget https://github.com/ginuerzh/gost/releases/download/v2.11.1/gost-linux-amd64-2.11.1.gz
	gzip -d gost-linux-amd64-2.11.1.gz
	mv gost-linux-amd64-2.11.1  gost
	chmod 777 gost

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
        echo -e "请输入你需要推广的TAG："
        read -p "(留空则跳过):" input_tag
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
        local mtg_url=https://github.com/9seconds/mtg/releases/download/v1.0.11/mtg-1.0.11-linux-$arch.tar.gz
        wget $mtg_url -O mtg.tar.gz
        tar -xzvf mtg.tar.gz mtg-1.0.11-linux-$arch/mtg --strip-components 1

        [[ -f "./mtg" ]] && ./mtg && echo "Installed for mtg"
    else
        wget https://github.com/ellermister/mtproxy/releases/download/0.03/mtproto-proxy -O mtproto-proxy -q
        chmod +x mtproto-proxy
    fi

    if [ ! -d "./pid" ]; then
        mkdir "./pid"
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

run_mtp() {
    cd $WORKDIR

    if is_running_mtp; then
        echo -e "提醒：\033[33mMTProxy已经运行，请勿重复运行!\033[0m"
    else
        do_kill_process
        do_check_system_datetime_and_update

        local command=$(get_run_command)
        echo $command
        $command >/dev/null 2>&1 &

        echo $! >$pid_file
        sleep 2
        info_mtp
    fi
}

Start() {
	while true;do
		_input=0
		echo "1. 自动一键安装"
		echo "8. 退出"
		read -p "(请选择您需要的操作:" input_provider

		if [ ${input_provider} == 1 ]; then
			echo $input_provider
			do_install_basic_dep
			do_config_mtp
			do_install
			run_mtp
		fi
		
		if [ ${input_provider} == 8 ]; then
			break
		fi
	done
}

Start

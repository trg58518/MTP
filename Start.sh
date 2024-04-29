#!/bin/bash
WORKDIR=$(dirname $(readlink -f $0))
cd $WORKDIR
pid_file=$WORKDIR/pid/pid_mtproxy

echo "###############开机自启脚本###############"


function is_running_mtp() {
    if [ -f $pid_file ]; then

        if is_pid_exists $(cat $pid_file); then
            return 0
        fi
    fi
    return 1
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

function str_to_hex() {
    string=$1
    hex=$(printf "%s" "$string" | od -An -tx1 | tr -d ' \n')
    echo $hex
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
  fi
}
function get_local_ip(){
  ip a | grep inet | grep 127.0.0.1 > /dev/null 2>&1
  if [[ $? -eq 1 ]];then
    echo $(get_ip_private)
  else
    echo "127.0.0.1"
  fi
}

function get_ip_public() {
    public_ip=$(curl -s https://api.ip.sb/ip -A Mozilla --ipv4)
    [ -z "$public_ip" ] && public_ip=$(curl -s ipinfo.io/ip -A Mozilla --ipv4)
    echo $public_ip
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
        echo -e "TG一键链接: https://t.me/proxy?server=${public_ip}&port=${port}&secret=${client_secret}"
        echo -e "TG一键链接: tg://proxy?server=${public_ip}&port=${port}&secret=${client_secret}"
    else
        echo -e "TMProxy+TLS代理: \033[33m已停止\033[0m"
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
        info_mtp
    fi
}

run_mtp

nohup gost -L=mtls://:8443/127.0.0.1:443

#!/bin/sh

# A Sample OpenVPN-aware firewall.

# ETH0 is connected to the internet.
# ETH1 is connected to a private subnet.

ETH0=ens37
ETH1=ens33

# Change this subnet to correspond to your private
# ethernet subnet.  Home will use HOME_NET/24 and
# Office will use OFFICE_NET/24.
PRIVATE=10.8.0.0/24

# Loopback address
LOOP=127.0.0.1

# Delete old iptables rules
# and temporarily block all traffic.
iptables -P OUTPUT DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP
# 这条是删除原有的防火墙规则，删除的是filter表的规则，filter表的规则部分是作用在INPUT链上的
iptables -F

# Set default policies 重新设置链的默认策略
iptables -P OUTPUT ACCEPT
iptables -P INPUT DROP
iptables -P FORWARD DROP

# Prevent external packets from using loopback addr
# 这里是避免外部发来的数据包的源地址和目的
# 地址是回环地址，从而错误的递交给本地的进程。这应该是避免攻击的一些手段
iptables -A INPUT -i $ETH0 -s $LOOP -j DROP
iptables -A FORWARD -i $ETH0 -s $LOOP -j DROP
iptables -A INPUT -i $ETH0 -d $LOOP -j DROP
iptables -A FORWARD -i $ETH0 -d $LOOP -j DROP

# Anything coming from the Internet should have a real Internet address
# 这里是对一些有可能是错误发送的包进行丢弃
#iptables -A FORWARD -i $ETH0 -s 192.168.0.0/16 -j DROP
#iptables -A FORWARD -i $ETH0 -s 172.16.0.0/12 -j DROP
#iptables -A FORWARD -i $ETH0 -s 10.0.0.0/8 -j DROP
#iptables -A INPUT -i $ETH0 -s 192.168.0.0/16 -j DROP
#iptables -A INPUT -i $ETH0 -s 172.16.0.0/12 -j DROP
#iptables -A INPUT -i $ETH0 -s 10.0.0.0/8 -j DROP

# Block outgoing NetBios (if you have windows machines running
# on the private subnet).  This will not affect any NetBios
# traffic that flows over the VPN tunnel, but it will stop
# local windows machines from broadcasting themselves to
# the internet.
iptables -A FORWARD -p tcp --sport 137:139 -o $ETH0 -j DROP
iptables -A FORWARD -p udp --sport 137:139 -o $ETH0 -j DROP
iptables -A OUTPUT -p tcp --sport 137:139 -o $ETH0 -j DROP
iptables -A OUTPUT -p udp --sport 137:139 -o $ETH0 -j DROP

# Check source address validity on packets going out to internet
# 这里是对windows的一些服务端口进行屏蔽，我们是linux不用管
# iptables -A FORWARD -s ! $PRIVATE -i $ETH1 -j DROP
# iptables -A FORWARD -m iprange ! --src-range 10.0.0.0-10.0.0.255 -i $ETH1 -j DROP

# Allow local loopback
# 这里是对回环地址放行
iptables -A INPUT -s $LOOP -j ACCEPT
iptables -A INPUT -d $LOOP -j ACCEPT

# Allow incoming pings (can be disabled)
# 这里是对icmp协议放行，也就是能响应ping命令
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

# Allow services such as www and ssh (can be disabled)
# 这里是对常用的服务端口入栈放行
iptables -A INPUT -p tcp --dport http -j ACCEPT
iptables -A INPUT -p tcp --dport ssh -j ACCEPT
iptables -A INPUT -p tcp --dport 139 -j ACCEPT #samba服务器端口
iptables -A INPUT -p tcp --dport 445 -j ACCEPT #samba服务器端口

# Allow incoming OpenVPN packets
# Duplicate the line below for each
# OpenVPN tunnel, changing --dport n
# to match the OpenVPN UDP port.
#
# In OpenVPN, the port number is
# controlled by the --port n option.
# If you put this option in the config
# file, you can remove the leading '--'
#
# If you taking the stateful firewall
# approach (see the OpenVPN HOWTO),
# then comment out the line below.
# 这里是自己想要放行的端口和协议数据，有其他端口可以自行添加
iptables -A INPUT -p udp --dport 1194 -j ACCEPT

# Allow packets from TUN/TAP devices.
# When OpenVPN is run in a secure mode,
# it will authenticate packets prior
# to their arriving on a tun or tap
# interface.  Therefore, it is not
# necessary to add any filters here,
# unless you want to restrict the
# type of packets which can flow over
# the tunnel.
# 这里主要是对tun+网卡和tap+网卡的入栈和转发数据包放行，+号应该表示的是一个通配符
iptables -A INPUT -i tun+ -j ACCEPT
iptables -A FORWARD -i tun+ -j ACCEPT
iptables -A INPUT -i tap+ -j ACCEPT
iptables -A FORWARD -i tap+ -j ACCEPT

# Allow packets from private subnets
# 这里是对eth1网卡的入栈和转发数据包放行
iptables -A INPUT -i $ETH1 -j ACCEPT
iptables -A FORWARD -i $ETH1 -j ACCEPT

# Keep state of connections from local machine and private subnets
# 这里是放行状态为NEW的出栈数据包
iptables -A OUTPUT -m state --state NEW -o $ETH0 -j ACCEPT
# 这里放行已经建立连接和关联的入栈数据包
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
# 这里放行需要转发的包，有这两条，本机才能作为NAT代理客户端访问互联网
iptables -A FORWARD -m state --state NEW -o $ETH0 -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# Masquerade local subnet
# 对于需要通过openvpn服务端访问外网的客户端节点，这个防火墙配置是必需的，也是最重要的配置
# 这个防火墙的配置是将路由后的源IP地址是10.8.0.0/24，输出网卡是eth0的数据包的源ip地址进行修改，
# 改成本机的ip地址，这样响应数据包才能正确的给我们转发回来
iptables -t nat -A POSTROUTING -s $PRIVATE -o $ETH0 -j MASQUERADE

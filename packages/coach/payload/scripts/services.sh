#!/bin/bash
version="2018.03.19"

if [ -p /dev/stdin ]
then
	read
fi
# read the options
TEMP=`getopt -o vheaf:c:u: --long version,help,fqdn:,cidr:,user: -n "sysprep.sh" -- $@`
eval set -- "$TEMP"
# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -v|--version)
			echo "COACH/sysprep CLI version $version"
			exit
			;;
        -h|--help)
			echo "Usage:		./sysprep.sh [OPTIONS...] [ARGUMENTS...]"
			echo "Example:	./sysprep.sh -u notroot -f node2.example.com -c 192.168.0.0/24"
			echo
			echo "OPTIONS"
			echo "-------"
			echo "-h, --help 	Help (this message)"
			echo "-v, --version	Version"
			echo
			echo "ARGUMENTS"
			echo "---------"
			echo "-u, --user	Run as a specified user"
			echo "-f, --fqdn	Set fully qualified domain name for this node"
			echo "		  -f node2.example.com"
			echo "-c, --cidr	Force use of specific CIDR (used by ceph)"
			echo "		  -c 192.168.0.0/24"
			echo
			exit
			;;
		-u|--user)
			user=$2
			shift 2
			;;
		-f|--fqdn)
			host_name=$2
			shift 2
			;;
		-c|--cidr)
			cidr=$2
			shift 2
			;;
		-k|--kernel)
			update_kernel=Y
        --)
			shift
			break
			;;
        *)
			echo "Internal error!"
			exit 1
			;;
    esac
done

# Enable InfiniBand Modules
if [ ! -z "$(lspci | grep InfiniBand)" ]
then
	if [ -z "$(cat /etc/modules | grep mlx4_core)" ]
	then
		echo mlx4_core >> /etc/modules
		echo mlx4_ib >> /etc/module
		echo rdma_ucm >> /etc/module
		echo ib_umad >> /etc/module
		echo ib_uverbs >> /etc/module
		echo ib_ipoib >> /etc/module

		modprobe mlx4_core
		modprobe mlx4_ib
		modprobe rdma_ucm
		modprobe ib_umad
		modprobe ib_uverbs
		modprobe ib_ipoib

		# InfiniBand Subnet Manager
		apt-get -y install opensm
		update-rc.d -f opensm remove
		update-rc.d opensm defaults
		update-rc.d opensm enable
		service opensm restart

		# Network performance testing
		apt-get install iperf
		echo 'net.core.wmem_max=4194304' >> /etc/sysctl.conf
		echo 'net.core.rmem_max=12582912' >> /etc/sysctl.conf
		echo 'net.ipv4.tcp_rmem = 4096 87380 4194304' >> /etc/sysctl.conf
		echo 'net.ipv4.tcp_wmem = 4096 87380 4194304' >> /etc/sysctl.conf
		sysctl -p
	fi
fi

cp -r $behere/etc /
chmod +x /etc/coach_cluster/auto-bonding.sh
chmod +x /etc/ceph/auto-add-osd.sh
chmod +x /etc/systemd/system/auto-add-osd.service

if [ ! -z "$(systemctl list-unit-files | grep auto-add-osd.service)" ]
then
	if [ -z "$(systemctl list-unit-files | grep auto-add-osd.service | grep enabled)" ]
	then
		systemctl enable auto-add-osd.service
	fi
fi

# Fix black screen on boot
if [ | -z '$(lspci | grep "Matrox Electronics Systems Ltd. MGA G200e")' ]
then
	if [ -z "$(tr -d '[[:space:]]' < /boot/grub/grub.cfg | grep '#gfxmode$linux_gfx_mode')" ]
	then 
		sed -i '/gfxmode $linux_gfx_mode/s/^/#/' /boot/grub/grub.cfg
	fi
fi

# Bootstrap Network
echo -e "[${YELLOW}$node${NC}]	$behere/fabric.sh... " 1>&2
storage_fabric=$($behere/fabric.sh -n $node) || exit 2

if [ -z "$(ip -f inet -o addr show $storage_fabric | cut -d\  -f 7 | cut -d/ -f 1)" ]
then
	sudo dhclient -cf "$behere/docker/dnsmasq/conf" $storage_fabric
fi

# Update Repos
if [ -z "$(find -H /var/lib/apt/lists -maxdepth 0 -mtime -1)" ]
then
	echo -e -n "[${YELLOW}$node${NC}]	apt-get update... " 1>&2
	sudo apt-get update >>sysprep_log && echo -e "${GREEN}completed${NC}." 1>&2 || echo -e "${RED}failed${NC}." 1>&2
fi
pkgs=(apt-transport-https python-minimal ipcalc ntp)
for pkg in ${pkgs[@]}
do
	error=0
	while [ -z "$(dpkg -l | grep $pkg)" ]
	do
		echo -e -n "[${YELLOW}$node${NC}]	apt-get install -y $pkg... " 1>&2
		apt-get install -y $pkg >>sysprep_log 2>>sysprep_log && echo -e "${GREEN}completed${NC}." 1>&2 || echo -e "${RED}failed${NC}." 1>&2
	done
done

if [ -z "$(cat /etc/hosts | grep $(hostname) | grep 'COACH')" ]
then
	if [ -z $(hostname -f | grep -P '(?=^.{1,254}$)(^(?>(?!\d+\.)[a-zA-Z0-9_\-]{1,63}\.?)+(?:[a-zA-Z]{2,})$)') ]
	then
		host_name_old=$(hostname -f)
		if [ -z $(echo $host_name | grep -P '(?=^.{1,254}$)(^(?>(?!\d+\.)[a-zA-Z0-9_\-]{1,63}\.?)+(?:[a-zA-Z]{2,})$)') ]
		then
			while [ -z $host_name ]
			do
				echo -e -n "[${CYAN}$node${NC}]	Please set a fully qualified domain name for this host: "
				read host_name </dev/tty
				echo
			done
			if [ ! -z $(echo $host_name | grep -P '(?=^.{1,254}$)(^(?>(?!\d+\.)[a-zA-Z0-9_\-]{1,63}\.?)+(?:[a-zA-Z]{2,})$)') ]
			then
				domain_name=$(echo $host_name | sed -n 's/[^.]*\.//p')
				host_name=$(echo $host_name | sed 's/\..*//')
			fi
			while [ -z $domain_name ]
			do
				echo -e -n "[${CYAN}$node${NC}]	Domain Name: "
				read domain_name </dev/tty
				echo
			done
		else 
			domain_name=$(echo $host_name | sed -n 's/[^.]*\.//p')
			host_name=$(echo $host_name | sed 's/\..*//')
		fi
		links=($(ip -o link show | awk -F': ' '{print $2}' | grep -v lo))
		if [ -z $cidr ]
		then
			if [ "${#links[@]}" -eq "1" ]
			then
				ip=$(ip -f inet -o addr show ${links[0]} | cut -d\  -f 7 | cut -d/ -f 1)
			else
				while [ -z "$ip" ]
				do 
					i=0
					for link in ${links[@]}
					do
						if [ "$storage_fabric" == "$link" ]
						then
							echo -e "[${CYAN}$node${NC}]	[$i]	$link	$(ip -f inet -o addr show $link | cut -d\  -f 7)	${CYAN}RECOMMENDED${NC}"
						else
							echo -e "[${CYAN}$node${NC}]	[$i]	$link	$(ip -f inet -o addr show $link | cut -d\  -f 7)"
						fi
						i=$(($i+1))
					done
					
					echo -e -n "[${CYAN}$node${NC}]	Select the Storage Fabric: "
					read fabric </dev/tty
					if [ ! -z "$fabric" ]
					then
						ip=$(ip -f inet -o addr show ${links[$fabric]} | cut -d\  -f 7 | cut -d/ -f 1)
					fi
					while [ -z "$ip" ]
					do
						echo -e -n "[${CYAN}$node${NC}]	Please set a CIDR for the storage network (ex 192.168.0.0/24): "
						read cidr_ </dev/tty
						echo
						if [ ! -z $cidr_ ]
						then
							if [ -z "$(ipcalc $cidr_ | grep 'INVALID ADDRESS')" ]
							then
								cidr=$cidr_
								ip=$(ipcalc $cidr | grep HostMin | awk '{print $2}')
								sn=$(ipcalc $cidr | grep Netmask | awk '{print $4}')
								echo -e -n "[${YELLOW}$node${NC}]	sudo ip addr add $ip/$sn dev $storage_fabric... " 1>&2
								sudo ip addr add $ip/$sn dev $storage_fabric && echo -e "${GREEN}completed${NC}." 1>&2 || echo -e "${RED}failed${NC}." 1>&2
							fi
						fi
					done
				done
			fi
		else
			for link in ${links[@]}
			do
				if [ "$(ipcalc $(ip -f inet -o addr show $link | cut -d\  -f 7) | grep Network | awk '{print $2}')" == "$cidr" ]
				then
					ip=$(ipcalc $(ip -f inet -o addr show $link | cut -d\  -f 7) | grep Address | awk '{print $2}')
				fi
			done
			if [ -z $ip ]
			then
				if [ ! -z "$storage_fabric" ]
				then
					ip=$(ipcalc $cidr | grep HostMin | awk '{print $2}')
					sn=$(ipcalc $cidr | grep Netmask | awk '{print $4}')
					echo -e -n "[${YELLOW}$node${NC}]	sudo ip addr add $ip/$sn dev $storage_fabric... " 1>&2
					sudo ip addr add $ip/$sn dev $storage_fabric && echo -e "${GREEN}completed${NC}." 1>&2 || echo -e "${RED}failed${NC}." 1>&2
				else
					echo "Could not find a fabric given the defined CIDR."
					exit
				fi
			fi
		fi
		
		sed -i "/$host_name_old/d" /etc/hosts
		echo >> /etc/hosts
		echo "$ip	$host_name.$domain_name	$host_name	#COACH $user" >> /etc/hosts
		
		echo $host_name > /etc/hostname
		echo search $domain_name > /etc/resolvconf/resolv.conf.d/head
		resolvconf -u
		hostname $host_name
	fi
fi

if [ "$node" != "$(hostname -s)" ]
then
	echo -e "[${RED}$node${NC}]	Local hostname did not become $node for some reason."
	echo -e "[${RED}$node${NC}]	Exiting to prevent corruption."
	exit 2
fi

echo "{" > "$behere/config.json"
echo "  \"localhost\": {" >> "$behere/config.json"
echo "    \"user\":\"$user\"," >> "$behere/config.json"
echo "    \"hostname\":\"$host_name\"," >> "$behere/config.json"
echo "    \"domain\":\"$domain_name\"," >> "$behere/config.json"
echo "    \"cidr\":\"$cidr\"" >> "$behere/config.json"
echo "  }" >> "$behere/config.json"
echo "}" >> "$behere/config.json"

echo $storage_fabric

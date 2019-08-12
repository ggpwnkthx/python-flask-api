#!/bin/bash
version="2018.04.13"

# read the options
TEMP=`getopt -o vhc: --long version,help,cidr: -- "$@"`
eval set -- "$TEMP"

# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -v|--version)
			echo "COACH/scripts/fabric CLI version $version"
			exit
			;;
        -h|--help)
			echo "Usage:		/scripts/fabric.sh [OPTIONS...]"
			echo "Example:	/scripts/fabric.sh"
			echo
			echo "OPTIONS"
			echo "-------"
			echo "-h, --help	Help (this message)"
			echo "-v, --version	Version"
			echo
			echo "ARGUMENTS"
			echo "---------"
			echo "-c, --cidr	CIDR to find or create."
			echo
			exit
			;;
        -c|--cidr) cidr=$2 ; shift 2 ;;
        --) shift ; break ;;
        *) echo "Internal error!" ; exit 1 ;;
    esac
done

# Defaults
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

scripts="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
root=$scripts/..
etc=$root/etc
docker=$root/docker


if [ ! -z "$(command -v docker)" ]
then
	if [ ! -z "$(sudo docker ps -a | grep Storage_Fabric)" ]
	then
		if [ ! -z "$(sudo docker ps -a -f "status=exited" | grep Storage_Fabric)" ]
		then
			sudo $scripts/dispatcher.sh -c WARNING -p "docker start Storage_Fabric" || exit $?
		fi
		if [ ! -z "$(sudo docker ps -a -f "status=paused" | grep Storage_Fabric)" ]
		then
			sudo $scripts/dispatcher.sh -c WARNING -p "docker start Storage_Fabric" || exit $?
		fi
		inspect=($(sudo docker inspect Storage_Fabric | python -c 'import json,sys;obj=json.load(sys.stdin);print obj[0]["Args"];')) 1>&2
		for i in ${inspect[@]}
		do
			i=$(echo $i | grep "u'--interface=")
			if [ ! -z "$i" ]
			then
				storage_fabric=$(echo $i | grep "u'--interface="| sed -e "s/u'--interface=//g" | sed -e "s/',//g")
			fi
		done
	fi
fi

$scripts/package_manager.sh -i ipcalc

links=($(ip -o link show | awk -F': ' '{print $2}' | grep -v lo))
for l in ${links[@]}
do
	cidr_v4=($(ip addr show dev $l | grep -v inet6 | grep inet | awk '{print $2}'))
	for c in ${cidr_v4[@]}
	do
		if [ "$(ipcalc $cidr | grep Network | awk '{print $2}')" == "$(ipcalc $c | grep Network | awk '{print $2}')" ]
		then
			storage_fabric=(${storage_fabric[@]} $l)
		fi
	done
done

if [ -z "$storage_fabric" ]
then
	declare -A fabrics
	
	$scripts/package_manager.sh -i nmap
	
	internet=$(route | grep default | awk '{print $8}')
	UNUSABLE="UNUSABLE"
	DISCONNECTED="DISCONNECTED"
	AVAILABLE="AVAILABLE"
	INTERNET="INTERNET"
	STORAGE="coach-storage"
	BONDED="BONDED"
	for link in ${links[@]}
	do
		if [ -d /sys/class/net/$link/bonding_slave ]
		then
			fabrics[$link]="${fabrics[$link]} $BONDED"
		else 
			dhcp_server=""
			net_state=$(cat /sys/class/net/$link/operstate)
			if [ "down" == "$net_state" ]
			then
				sudo $scripts/dispatcher.sh -c WARNING -p "ip link set dev $link up" || exit $?
				/bin/sleep 2
			fi
			if [ "up" == "$(cat /sys/class/net/$link/operstate)" ]
			then
				dhcp_server=$(sudo $scripts/dispatcher.sh -r -c WARNING -p "nmap --script broadcast-dhcp-discover -e $link | grep 'Server Identifier'")
				if [ ! -z "$dhcp_server" ]
				then
					if [ -f "$docker/dnsmasq/lease" ]
					then
						sudo $scripts/dispatcher.sh -c WARNING -p "rm \"$docker/dnsmasq/lease\"" || exit $?
					fi
					sudo $scripts/dispatcher.sh -c WARNING -p "dhclient -r $link" || exit $?
					sudo $scripts/dispatcher.sh -c WARNING -p "dhclient -cf \"$docker/dnsmasq/conf\" -lf \"$docker/dnsmasq/lease\" $link" || exit $?
					fabrics[$link]=$(cat "$docker/dnsmasq/lease" | grep "option fabric-finder" | tail -1 | awk '{$1="";$2=""; print $0}' | cut -d "\"" -f 2)
					if [ -z "${fabrics[$link]}" ]
					then
						fabrics[$link]="${fabrics[$link]} $UNUSABLE"
					fi
				else
					fabrics[$link]="${fabrics[$link]} $AVAILABLE"
				fi
				if [ "down" == "$net_state" ]
				then
					sudo $scripts/dispatcher.sh -c WARNING -p "ip link set dev $link down" || exit $?
				fi
				if [ "$link" == "$internet" ]
				then
					fabrics[$link]="${fabrics[$link]} $INTERNET"
				fi
			else
				fabrics[$link]="${fabrics[$link]} $DISCONNECTED"
			fi
		fi
	done
	
	for i in ${!fabrics[@]}
	do
		echo -e "[${CYAN}$(hostname -s)${NC}]	[$i]	${fabrics[$i]}" 1>&3
	done
	available_fabrics=()
	storage_fabrics=()
	found_fabrics=()

	for fab in "${!fabrics[@]}"
	do
		if [[ " (${fabrics[$fab]}) " =~ "$AVAILABLE" ]]
		then
			available_fabrics=(${available_fabrics[@]}	$fab)
		fi
		if [[ " (${fabrics[$fab]}) " =~ "$STORAGE" ]]
		then
			storage_fabrics=(${storage_fabrics[@]} $fab)
		fi
	done
	echo -e "${CYAN}[$(hostname -s)${NC}]	AVAILABLE INTERFACES: ${available_fabrics[@]}" 1>&3
	if [ ${#storage_fabrics[@]} -eq 0 ]
	then
		if [ ${#available_fabrics[@]} -eq 0 ]
		then
			echo -e "[${RED}$(hostname -s)${NC}]	A dedicated fabric is necessary for the cluster's storage networking, and none were found. For security precautions, the storage fabric can not be one that has internet access." 1>&2
			exit 2
		fi
		if [ ${#available_fabrics[@]} -eq 1 ]
		then
			if [ ! -d /sys/class/net/${available_fabrics[@]}/bonding ]
			then
				echo -e "[${RED}$(hostname -s)${NC}]	Only one interface was found that can be used to create the storage fabric. Bootstrapping will continue, but without a failover interface this is not an ideal configuration." 1>&2
			fi
			found_fabrics=("${available_fabrics[@]}")
		fi
		if [ ${#available_fabrics[@]} -gt 1 ]
		then
			$scripts/package_manager.sh -i docker.io
			
			cd "$docker/dnsmasq"
			sudo $scripts/dispatcher.sh -c WARNING -p "docker build -t \"coach/dnsmasq\" . " || exit $?
			cd "$root"
			
			i=0
			for fab in ${available_fabrics[@]}
			do	
				skip=0
				for ff in ${found_fabrics[@]}
				do
					ff=($ff)
					for fff in $ff
					do
						if [ "$fab" == "$fff" ]
						then
							skip=1
						fi
					done
				done
				if [ $skip == 0 ]
				then
					net_state=$(cat /sys/class/net/$fab/operstate)
					if [ "down" == "$net_state" ]
					then
						sudo $scripts/dispatcher.sh -c WARNING -p "ip link set dev $fab up" || exit $?
						/bin/sleep 2
					fi
					found_fabrics[$i]="$fab"
					sudo $scripts/dispatcher.sh -c WARNING -p "ip addr add 169.254.0.1/16 dev $fab" || exit $?
					uuid=$(cat /proc/sys/kernel/random/uuid)
					docker_interface="--interface=$fab"
					docker_dhcp_option="--dhcp-option=224,$uuid"
					docker_dhcp_range="--dhcp-range=169.254.0.2,169.254.255.254,255.255.0.0,5m"
					docker_id=$(sudo $scripts/dispatcher.sh -r -c WARNING -p "docker run -d --net=host --cap-add=NET_ADMIN coach/dnsmasq $docker_interface $docker_dhcp_option $docker_dhcp_range") || exit $?
					for fab_ in ${available_fabrics[@]}
					do
						if [ "$fab" != "$fab_" ]
						then
							echo -e "${CYAN}TESTING $fab TO $fab_ COMMUNICATION${NC}" 1>&3
							if [ -f "$docker/dnsmasq/lease" ]
							then
								sudo $scripts/dispatcher.sh -c WARNING -p "rm \"$docker/dnsmasq/lease\"" || exit $?
							fi
							net_state=$(cat /sys/class/net/$fab_/operstate)
							if [ "down" == "$net_state" ]
							then
								sudo $scripts/dispatcher.sh -c WARNING -p "ip link set dev $fab_ up" || exit $?
								/bin/sleep 2
							else
								sudo $scripts/dispatcher.sh -c WARNING -p "dhclient -r $fab_" || exit $?
							fi
							sudo $scripts/dispatcher.sh -c WARNING -p "dhclient -cf \"$docker/dnsmasq/conf\" -lf \"$docker/dnsmasq/lease\" $fab_" || exit $?
							if [ ! -z "$(cat $docker/dnsmasq/lease)" ]
							then
								sudo $scripts/dispatcher.sh -c WARNING -p "dhclient -r $fab_" || exit $?
							fi
							
							fip=$(cat "$docker/dnsmasq/lease" | grep "fixed-address" | tail -1 | awk '{$1=""; print $0}' | sed 's/;$//')
							snm=$(cat "$docker/dnsmasq/lease" | grep "option subnet-mask" | tail -1 | awk '{$1="";$2=""; print $0}' | sed 's/;$//')
							if [ ! -z "$fip" ]
							then
								sudo $scripts/dispatcher.sh -c WARNING -p "ip addr del $fip/$(ipcalc $fip/$snm | grep Netmask | awk '{print $4}') dev $fab_" || exit $?
							fi
							
							ffuuid=$(cat "$docker/dnsmasq/lease" | grep "option fabric-finder" | tail -1 | awk '{$1="";$2=""; print $0}' | cut -d "\"" -f 2)
							if [ "$ffuuid" == "$uuid" ]
							then
								found_fabrics[$i]="${found_fabrics[$i]} $fab_"
								available_fabrics=("${available_fabrics[@]/$fab_/}")
							fi
							if [ "down" == "$net_state" ]
							then
								sudo $scripts/dispatcher.sh -c WARNING -p "ip link set dev $fab_ down" || exit $?
							fi
						fi
					done
					sudo $scripts/dispatcher.sh -c WARNING -p "docker stop $docker_id" || exit $?
					sudo $scripts/dispatcher.sh -c WARNING -p "docker rm $docker_id" || exit $?
					sudo $scripts/dispatcher.sh -c WARNING -p "ip addr del 169.254.0.1/16 dev $fab" || exit $?
					if [ "down" == "$net_state" ]
					then
						sudo $scripts/dispatcher.sh -c WARNING -p "ip link set dev $fab down" || exit $?
					fi
					available_fabrics=("${available_fabrics[@]/$fab/}")
					i=$(($i+1))
				fi
			done
		fi
		
		# Install lshw
		$scripts/package_manager.sh -i lshw
		
		for i in ${!found_fabrics[@]}
		do
			count=($(echo ${found_fabrics[$i]}))
			if [ ${#count[@]} -gt 1 ]
			then
				for a in ${count[@]}
				do
					args="$args -i $a"
				done
				bond=$(sudo $scripts/dispatcher.sh -f -r -c WARNING -p "/etc/coach_cluster/auto-bonding.sh $args") || exit $?
				case $(cat /sys/class/net/$bond/type) in
					32)	
						guid=$(cat /sys/class/net/$(cat /sys/class/net/$bond/bonding/active_slave)/address | sed 's/\://g' | tail -c 16)
						speed=$(ibstat | grep -B5 "$(cat /sys/class/net/$(cat /sys/class/net/$bond/bonding/active_slave)/address | sed 's/\://g' | tail -c 16)" | grep Rate | awk '{print $2}')000
						;;
					*)	speed=$(cat /sys/class/net/$bond/speed 2>/dev/null) ;;
				esac
				if [ -z "$speed" ]
				then
					speed=$(lshw 2>/dev/null | grep -A5 $bond | grep size | awk '{print $2}')
					unit=$(echo $speed | tail -c -7)
					speed=${speed::-6}
					case $unit in
						"Kbit/s") speed=0."$speed";;
						"Mbit/s") speed="$speed";;
						"Gbit/s") speed="$speed"000;;
						"Tbit/s") speed="$speed"000000;;
					esac
				fi
				found_fabrics[$i]="$bond $speed"
			else 
				speed=$(cat /sys/class/net/${found_fabrics[$i]}/speed 2>/dev/null)
				if [ -z "$speed" ]
				then
					speed=$(lshw 2>/dev/null | grep -A5 ${found_fabrics[$i]} | grep size | awk '{print $2}')
					unit=$(echo $speed | tail -c -7)
					speed=${speed::-6}
					case $unit in
						"Kbit/s") speed=0."$speed";;
						"Mbit/s") speed="$speed";;
						"Gbit/s") speed="$speed"000;;
						"Tbit/s") speed="$speed"000000;;
					esac
				fi
				found_fabrics[$i]="${found_fabrics[$i]} $speed"
			fi
		done
		
		for i in ${!found_fabrics[@]}
		do
			iface=$(echo ${found_fabrics[$i]} | awk '{print $1}')
			if [ -d /sys/class/net/$iface/bonding ]
			then
				count=($(cat /sys/class/net/$iface/bonding/slaves))
				found_fabrics[$i]="${found_fabrics[$i]} $(printf %03d ${#count[@]})"
			else
				found_fabrics[$i]="${found_fabrics[$i]} 001"
			fi
		done
		
		IFS=$'\n' found_fabrics=($(sort -k2 -rk3 <<<"${found_fabrics[*]}"))
		storage_fabric=$(echo ${found_fabrics[0]} | awk '{print $1}')
	else
		# Established storage fabric found. Bootstrapping not needed.
		for i in ${storage_fabrics[@]}
		do
			args="$args -i $a"
		done
		storage_fabric=$(sudo /etc/coach_cluster/auto-bonding.sh $args)
		
		if [ -z "$storage_fabric" ]
		then
			storage_fabric=$(echo ${storage_fabrics[0]} | awk '{print $1}')
		fi
	fi
else
	if [ ${#storage_fabric[@]} -gt 1 ]
	then
		for i in ${storage_fabric[@]}
		do
			args="$args -i $a"
		done
		storage_fabric=$(sudo /etc/coach_cluster/auto-bonding.sh $args)
	fi
fi

# Ensure we have an IP address
ips=($(ip addr show dev $storage_fabric | grep -v inet6 | grep inet | awk '{print $2}' | awk -F'/' '{print $1}'))
if [ ${#ips[@]} -eq 0 ]
then
	sudo $scripts/dispatcher.sh -c WARNING -p "dhclient -r $link" || exit $?
	sudo $scripts/dispatcher.sh -c WARNING -p "dhclient -cf \"$docker/dnsmasq/conf\" -lf \"$docker/dnsmasq/lease\" $link" || exit $?
fi

ips=($(ip addr show dev $storage_fabric | grep -v inet6 | grep inet | awk '{print $2}' | awk -F'/' '{print $1}'))
if [ ${#ips[@]} -eq 0 ]
then
	ip_=$(echo $cidr | awk -F'/' '{print $1}')
	bits=$(echo $cidr | awk -F'/' '{print $2}')
    ip_hex=$(echo $ip_ | awk -F '.' '{printf "%02x", $1}{printf "%02x", $2}{printf "%02x", $3}{printf "%02x", $4}')
	min_=$(ipcalc $cidr | grep HostMin | awk '{print $2}')
	min_hex=$(echo $min_ | awk -F '.' '{printf "%02x", $1}{printf "%02x", $2}{printf "%02x", $3}{printf "%02x", $4}')
	if [[ 0x$min_hex -ge 0x$ip_hex ]]
	then
		cidr_=$min_/$bits
	else
		cidr_=$ip_/$bits
	fi
	
	sudo $scripts/dispatcher.sh -c WARNING -p "ip addr add $cidr_ dev $storage_fabric" || exit $?
fi
# Double check that we're actually have an IP
ips=($(ip addr show dev $storage_fabric | grep -v inet6 | grep inet | awk '{print $2}'))
if [ ${#ips[@]} -eq 0 ]
then
	echo -e "${RED}Storage fabric found, but it has no IP address.${NC}" >&3
	exit 2
fi
# Double check that we're in the right subnet
ips=($(ip addr show dev $storage_fabric | grep -v inet6 | grep inet | awk '{print $2}'))
if [ ${#ips[@]} -gt 0 ]
then
	for i in ${ips[@]}
	do
		cidr=$(ipcalc $cidr | grep Network | awk '{print $2}')
		net=$(ipcalc $i | grep Network | awk '{print $2}')
		if [ "$cidr" == "$net" ]
		then
			all_good=1
			cidr_=$i
		fi
	done
	if [ -z $all_good ]
	then
		echo -e "${RED}Storage fabric found, but it is not in the expected subnet.${NC}" >&3
		exit 2
	fi
fi

# Announce the decision
echo -e "${CYAN}Using [$storage_fabric] for the storage fabric.${NC}" >&3

# Pass return value
echo -e $storage_fabric $cidr_ >&4
#!/bin/bash
version="2018.04.13"
tries=3
input=()

# read the options
TEMP=`getopt -o vhn:i: --long version,help,node:iface: -- "$@"`
eval set -- "$TEMP"

# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -v|--version)
			echo "COACH/auto-bonding CLI version $version"
			exit
			;;
        -h|--help)
			echo "Usage:		./auto-bonding.sh [OPTIONS...] [ARGUMENTS...]"
			echo "Example:	./auto-bonding.sh -i eth1 -i eth2 ..."
			echo
			echo "OPTIONS"
			echo "-------"
			echo "-h, --help	Help (this message)"
			echo "-v, --version	Version"
			echo
			echo "ARGUMENTS"
			echo "---------"
			echo "-n, --node	Hostname of node (cosmedic only)"
			echo "-i, --iface	Interfaces to bond - can be used multiple times"
			echo
			exit
			;;
		-n|--node) node=$2 ; shift 2 ;;
		-i|--input) input=(${input[@]} $2) ; shift 2 ;;
        --) shift ; break ;;
        *) echo "Internal error!" ; exit 1 ;;
    esac
done

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

if [ -z "$node" ]
then
	node=$(hostname -s)
fi

if [ ! -f "/sys/class/net/bonding_masters" ]
then
	echo -e -n "[${YELLOW}$node${NC}]	modprobe bonding... " 1>&3
	modprobe bonding && echo -e "${GREEN}completed${NC}." 1>&3 || echo -e "${RED}failed${NC}." 1>&3
	echo -e -n "[${YELLOW}$node${NC}]	echo \"-bond0\" > /sys/class/net/bonding_masters... " 1>&3
	echo "-bond0" > /sys/class/net/bonding_masters && echo -e "${GREEN}completed${NC}." 1>&3 || echo -e "${RED}failed${NC}." 1>&3
fi

to_bond=()

for i in ${input[@]}
do
	if [ -d "/sys/class/net/$i" ] 
	then
		itype=$(cat /sys/class/net/$i/type)
		to_bond[$itype]="${to_bond[$itype]} $i"
	fi
done

for i in ${!to_bond[@]}
do
	bonding=(${to_bond[$i]})
	if [ ${#bonding[@]} -gt 1 ]
	then
		bond=0
		while [ -d "/sys/class/net/bond$bond" ]; do bond=$(($bond+1)); done
		bond="bond$bond"
		echo -e -n "[${YELLOW}$node${NC}]	echo \"+$bond\" >  /sys/class/net/bonding_masters... " 1>&3
		echo "+$bond" >  /sys/class/net/bonding_masters && echo -e "${GREEN}completed${NC}." 1>&3 || echo -e "${RED}failed${NC}." 1>&3
		echo -e -n "[${YELLOW}$node${NC}]	echo active-backup > /sys/class/net/$bond/bonding/mode... " 1>&3
		echo active-backup > /sys/class/net/$bond/bonding/mode && echo -e "${GREEN}completed${NC}." 1>&3 || echo -e "${RED}failed${NC}." 1>&3
		for iface in ${to_bond[@]}
		do
			echo -e -n "[${YELLOW}$node${NC}]	echo \"+$iface\" > /sys/class/net/$bond/bonding/slaves... " 1>&3
			echo "+$iface" > /sys/class/net/$bond/bonding/slaves && echo -e "${GREEN}completed${NC}." 1>&3 || echo -e "${RED}failed${NC}." 1>&3
			case $i in
				32)	
					echo -e -n "[${YELLOW}$node${NC}]	echo connected > /sys/class/net/$iface/mode... " 1>&3
					echo connected > /sys/class/net/$iface/mode  && echo -e "${GREEN}completed${NC}." 1>&3 || echo -e "${RED}failed${NC}." 1>&3
					;;
			esac
		done
		echo -e -n "[${YELLOW}$node${NC}]	echo 100 > /sys/class/net/$bond/bonding/miimon... " 1>&3
		echo 100 > /sys/class/net/$bond/bonding/miimon && echo -e "${GREEN}completed${NC}." 1>&3 || echo -e "${RED}failed${NC}." 1>&3
		case $i in
			32)	
				echo -e -n "[${YELLOW}$node${NC}]	echo 65520 > sys/class/net/$bond/mtu... " 1>&3
				echo 65520 > sys/class/net/$bond/mtu && echo -e "${GREEN}completed${NC}." 1>&3 || echo -e "${RED}failed${NC}." 1>&3
				;;
		esac
		bonds=($bonds $bond)
	fi
done

echo ${bonds[@]}

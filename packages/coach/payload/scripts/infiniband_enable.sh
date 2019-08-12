#!/bin/bash
version="2018.04.13"

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
			echo "COACH/scripts/infiniband_enable CLI version $version"
			exit
			;;
        -h|--help)
			echo "Usage:		/scripts/infiniband_enable.sh [OPTIONS...]"
			echo "Example:	/scripts/infiniband_enable.sh"
			echo
			echo "OPTIONS"
			echo "-------"
			echo "-h, --help 	Help (this message)"
			echo "-v, --version	Version"
			echo
			exit
			;;
        --) shift ; break ;;
        *) echo "Internal error!" ; exit 1 ;;
    esac
done

if [ "$EUID" -ne 0 ]
then 
	echo "Must be run as root."
	exit 1
fi

scripts="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Enable InfiniBand Modules
if [ ! -z "$(lspci | grep InfiniBand)" ]
then
	modules=(mlx4_core mlx4_ib rdma_ucm ib_umad ib_uverbs ib_ipoib)
	for m in ${modules[@]}
	do
		if [ -z "$(cat /etc/modules | grep $m)" ]
		then
			$scripts/dispatcher.sh -c WARNING -p "echo $m >> /etc/modules" || exit $?
			$scripts/dispatcher.sh -c WARNING -p "modprobe $m" || exit $?
		fi
	done
	
	# Install Open Subnet Manager for Infiniband
	$scripts/package_manager.sh -i opensm
	
	# Fix some startup issues with the service
	case $(echo $(lsb_release -ds 2>/dev/null || cat /etc/*release 2>/dev/null | head -n1 || uname -om) | awk '{print $1}') in
		"Ubuntu")
			$scripts/dispatcher.sh -c WARNING -p "update-rc.d -f opensm remove" || exit $?
			$scripts/dispatcher.sh -c WARNING -p "update-rc.d opensm defaults" || exit $?
			$scripts/dispatcher.sh -c WARNING -p "update-rc.d opensm enable" || exit $?
			$scripts/dispatcher.sh -c WARNING -p "service opensm restart" || exit $?
			;;
	esac
fi


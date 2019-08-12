#!/bin/bash
version="2018.04.13"
tries=3

# read the options
TEMP=`getopt -o vhn:c: --long version,help,node:ceph: -- "$@"`
eval set -- "$TEMP"

# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -v|--version)
			echo "COACH/scripts/ceph CLI version $version"
			exit
			;;
        -h|--help)
			echo "Usage:		/scripts/ceph.sh [OPTIONS...] [ARGUMENTS...]"
			echo "Example:	/scripts/ceph.sh -n node2 -c luminous"
			echo
			echo "OPTIONS"
			echo "-------"
			echo "-h, --help	Help (this message)"
			echo "-v, --version	Version"
			echo
			echo "ARGUMENTS"
			echo "---------"
			echo "-n, --node	Hostname of node"
			echo "-c, --ceph	Ceph Version [Default: luminous]"
			echo
			exit
			;;
		-n|--node) node=$2 ; shift 2 ;;
		-c|--ceph) ceph_version=$2 ; shift 2 ;;
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

if [ -z "$node" ]
then
	node=$(hostname -s)
fi
if [ -z "$ceph_version" ]
then
	ceph_version="luminous"
fi

mkdir -p ~/ceph >>ceph_log
cd ~/ceph

# Install ceph-deploy via pip
if [ "$node" == "$(hostname -s)" ]
then
	if [ -z $(command -v ceph) ]
	then
		$scripts/package_manager.sh -m pip -i ceph-deploy
		$scripts/dispatcher.sh -c WARNING -p "ceph-deploy new $node" || exit $?
		$scripts/dispatcher.sh -c WARNING -p "echo public network = $(ipcalc $(cat /etc/hosts | grep $(hostname -f) | awk '{print $1}') | grep Network | awk '{print $2}') >> ceph.conf" || exit $?
		$scripts/dispatcher.sh -c WARNING -p "echo osd crush chooseleaf type = 0 >> ceph.conf" || exit $?
		$scripts/dispatcher.sh -c WARNING -p "echo osd pool default size = 1 >> ceph.conf" || exit $?
	fi
fi

# Install ceph via ceph-deploy
i=1
if [ "$node" == "$(hostname -s)" ]
then
	while [ -z "$(command -v ceph)" ]
	do
		$scripts/dispatcher.sh -c WARNING -p "ceph-deploy install --release $ceph_version $node"
		if [ $i -eq $tries ]
		then
			exit 2
		fi
		i=$(($i+1))
	done
else
	while [ -z "$(ssh -t $node 'command -v ceph')" ]
	do
		$scripts/dispatcher.sh -c WARNING -p "ceph-deploy install --release $ceph_version $node"
		if [ $i -eq $tries ]
		then
			exit 2
		fi
		i=$(($i+1))
	done
fi

# Deploy initial ceph monitor
if [ "$node" == "$(hostname -s)" ]
then
	while [ -z "$(sudo ceph -s -f json)" ]
	do
		$scripts/dispatcher.sh -c WARNING -p "ceph-deploy mon create-initial" || exit $?
		$scripts/dispatcher.sh -c WARNING -p "ceph-deploy admin $node" || exit $?
	done
else
	mons_total=$(sudo ceph mon dump -f json | python -c "import json,sys;obj=json.load(sys.stdin);print len(obj[\"mons\"]);")
	mons_count=0
	mon_install=1
	while [ $mons_count -lt $mons_total ]
	do
		if [ "$(getent hosts $(node) | awk '{print $1}')" == "$(sudo ceph mon dump -f json | python -c "import json,sys;obj=json.load(sys.stdin);print obj['mons'][$mons_count]['addr'];" | awk -F':' '{print $1}')" ]
		then
			mon_install=0
		fi
		mons_count=$(($mons_count+1))
	done
	if [ "$mon_install" == "1" ]
	then
		$scripts/dispatcher.sh -c WARNING -p "ceph-deploy mon add $node" || exit $?
		$scripts/dispatcher.sh -c WARNING -p "ceph-deploy admin $node" || exit $?
	fi
fi

# Deploy manager node
$scripts/dispatcher.sh -c WARNING -p "ceph-deploy mgr create $node" || exit $?

# Enable manager dashboard (note: http forwards to active manager's fqdn)
if [ "$node" == "$(hostname -s)" ]
then
	sudo $scripts/dispatcher.sh -c WARNING -p "ceph mgr module enable dashboard" || exit $?
	echo -e "${CYAN}Ceph dashboard is now accessible at http://$(hostname -f):7000${NC}"
else
	echo -e -n "[${YELLOW}$node${NC}]	sudo ceph mgr module enable dashboard... " 1>&2
	$scripts/dispatcher.sh -c WARNING -p "ssh -t $node \"sudo ceph mgr module enable dashboard\"" || exit $?
fi

# Deploy metadata service node
$scripts/dispatcher.sh -c WARNING -p "ceph-deploy mds create $node" || exit $?

# Ensure security keys are distributed
$scripts/dispatcher.sh -c WARNING -p "ceph-deploy gatherkeys $node" || exit $?

# Add all available disks
if [ "$node" == "$(hostname -s)" ]
then
	sudo $scripts/dispatcher.sh -c WARNING -p "cp ~/ceph/ceph.bootstrap-osd.keyring /var/lib/ceph/bootstrap-osd/ceph.keyring" || exit $?
	sudo $scripts/dispatcher.sh -c WARNING -p "/etc/ceph/auto-add-osd.sh" || exit $?
else
	$scripts/dispatcher.sh -c WARNING -p "scp ~/ceph/ceph.bootstrap-osd.keyring $node:~/cluster" || exit $?
	$scripts/dispatcher.sh -c WARNING -p "ssh -t $node \"sudo cp ~/cluster/ceph.bootstrap-osd.keyring /var/lib/ceph/bootstrap-osd/ceph.keyring\"" || exit $?
	$scripts/dispatcher.sh -c WARNING -p "ssh -t $node \"sudo /etc/ceph/auto-add-osd.sh\"" || exit $?
fi

# CephFS
nodes=($(sudo ceph osd tree | grep host | awk '{print $4}'))
nodes=${#nodes[@]}
if [ -z "$(sudo ceph osd pool stats cephfs_data)" ]
then
	sudo $scripts/dispatcher.sh -c WARNING -p "ceph osd pool create cephfs_data 32" || exit $?
else
	# Automatically increase the size of the pool up to 3 when more nodes are added 
	size=$(sudo ceph osd pool get cephfs_data size | awk '{print $2}')
	if [ $nodes > $size ]
	then
		if [ $size < 3 ]
		then
			size=$(($size+1))
			sudo $scripts/dispatcher.sh -c WARNING -p "ceph osd pool cephfs_data set size $size" || exit $?
		fi
	fi
fi
if [ -z "$(sudo ceph osd pool stats cephfs_meta)" ]
then
	sudo $scripts/dispatcher.sh -c WARNING -p "ceph osd pool create cephfs_meta 32" || exit $?
else
	# Automatically increase the size of the pool up to 3 when more nodes are added
	size=$(sudo ceph osd pool get cephfs_meta size | awk '{print $2}')
	if [ $nodes > $size ]
	then
		if [ $size < 3 ]
		then
			size=$(($size+1))
			sudo $scripts/dispatcher.sh -c WARNING -p "ceph osd pool cephfs_meta set size $size" || exit $?
		fi
	fi
fi
if [ -z "$(sudo ceph fs ls | grep -w "name: cephfs")" ]
then
	sudo $scripts/dispatcher.sh -c WARNING -p "ceph fs new cephfs cephfs_meta cephfs_data" || exit $?
fi

if [ "$node" == "$(hostname -s)" ]
then
	sudo $scripts/dispatcher.sh -c WARNING -p "/etc/ceph/auto-mount-cephfs.sh" || exit $?
else
	$scripts/dispatcher.sh -c WARNING -p "ssh -t $node \"sudo /etc/ceph/auto-mount-cephfs.sh\"" || exit $?
fi

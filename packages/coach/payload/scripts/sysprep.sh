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
			echo "COACH/scripts/sysprep CLI version $version"
			exit
			;;
        -h|--help)
			echo "Usage:		/scripts/sysprep.sh [OPTIONS...] [ARGUMENTS...]"
			echo "Example:	/scripts/sysprep.sh -u notroot -f node2.example.com -c 192.168.0.0/24"
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
		-u|--user) user=$2 ; shift 2 ;;
		-f|--fqdn) fqdn=$2 ; shift 2 ;;
		-k|--kernel) update_kernel=Y ;;
        --) shift ; break ;;
        *) echo "Internal error!" ; exit 1 ;;
    esac
done

node=$(echo $fqdn | sed 's/\..*//')
if [ ! -z $node ]
then
	node="-n $node"
fi

scripts="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
root=$scripts/..
etc=$root/etc

# Make sure other scripts are executable
list=(hostname_change kernel_check infiniband_enable package_manager services fabric host_ip ceph)
for i in ${list[@]}
do
	if [ ! -x "$scripts/$i.sh" ]
	then
		$scripts/dispatcher.sh $node -c WARNING -p "chmod +x $scripts/$i.sh" || exit $?
	fi
done
if [ -z $(echo $fqdn | grep -P '(?=^.{1,254}$)(^(?>(?!\d+\.)[a-zA-Z0-9_\-]{1,63}\.?)+(?:[a-zA-Z]{2,})$)') ]
then
	echo -e "Nodes must have a fully qualified domain name to continue." >&3
	exit 2
fi

# Set hostname
if [ ! -z "$fqdn" ]
then
	if [ "$fqdn" != "$(hostname -f)" ]
	then
		$scripts/dispatcher.sh $node -f -c WARNING -p "$scripts/hostname_change.sh -f $fqdn" || exit $?
	fi
fi

# Check the kernel version agains the minimum value based on the distribution
$scripts/dispatcher.sh -f -c WARNING -p "$scripts/kernel_check.sh" || exit $?

# Enable Infiniband if it's detected
$scripts/dispatcher.sh -f -c WARNING -p "$scripts/infiniband_enable.sh" || exit $?

# Fix black screen on boot
if [ ! -z "$(lspci | grep 'Matrox Electronics Systems Ltd. MGA G200e')" ]
then
	if [ -z "$(tr -d '[[:space:]]' < /boot/grub/grub.cfg | grep '#gfxmode$linux_gfx_mode')" ]
	then 
		$scripts/dispatcher.sh -c WARNING -p "sed -i '/gfxmode $linux_gfx_mode/s/^/#/' /boot/grub/grub.cfg" || exit $?
	fi
fi

# Copy system files
$scripts/dispatcher.sh -c WARNING -p "cp -r $root/etc /" || exit $?
list=(/etc/coach_cluster/auto-bonding.sh /etc/ceph/auto-add-osd.sh /etc/systemd/system/auto-add-osd.service /etc/ceph/auto-mount-cephfs.sh )
for i in ${list[@]}
do
	if [ ! -x "$i" ]
	then
		$scripts/dispatcher.sh -c WARNING -p "chmod +x $i" || exit $?
	fi
done

# Enable the auto-add-osd service
if [ ! -z "$(systemctl list-unit-files | grep auto-add-osd.service)" ]
then
	if [ -z "$(systemctl list-unit-files | grep auto-add-osd.service | grep enabled)" ]
	then
		$scripts/dispatcher.sh -c WARNING -p "systemctl enable auto-add-osd.service" || exit $?
	fi
else
	$scripts/dispatcher.sh -c WARNING -p "systemctl enable auto-add-osd.service" || exit $?
fi

echo "{" > "$root/config.json"
echo "  \"localhost\": {" >> "$root/config.json"
echo "    \"user\":\"$user\"," >> "$root/config.json"
echo "    \"fqdn\":\"$fqdn\"," >> "$root/config.json"
echo "    \"cidr\":\"$cidr\"" >> "$root/config.json"
echo "  }" >> "$root/config.json"
echo "}" >> "$root/config.json"


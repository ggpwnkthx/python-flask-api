#!/bin/bash
version="2018.04.13"

if [ -p /dev/stdin ]
then
	read
fi
# read the options
TEMP=`getopt -o vh --long version,help -n "kernel_check.sh" -- $@`
eval set -- "$TEMP"
# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -v|--version)
			echo "COACH/scripts/kernel_check CLI version $version"
			exit
			;;
        -h|--help)
			echo "Usage:		/scripts/kernel_check.sh [OPTIONS...]"
			echo "Example:	/scripts/kernel_check.sh"
			echo
			echo "OPTIONS"
			echo "-------"
			echo "-h, --help 	Help (this message)"
			echo "-v, --version	Version"
			echo
			exit
			;;
        --) shift ; break ;;
        *) echo "Internal error!";  exit 1 ;;
    esac
done

scripts="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check if kernel meets minimum specifications. If not, update it.
case $(echo $(lsb_release -ds 2>/dev/null || cat /etc/*release 2>/dev/null | head -n1 || uname -om) | awk '{print $1}') in
	"Ubuntu") package_manager="apt" ;;
	"Debian") package_manager="apt" ;;
	"Centos") package_manager="yum" ;;
esac
case $package_manager in
	"apt")
		expected=4.10
		received=$(uname -r | awk -F '-' '{print $1}')
		kernel_type=$(uname -r | awk -F '-' '{print $NF}')
		min=$(echo -e $expected"\n"$received|sort -V|head -n 1)
		if [ "$min" != "$expected" ]
		then
			linux_header=($(apt-cache search --names-only "linux-headers-$expected.*-$kernel_type" | sort -r))
			linux_header=$(echo ${linux_header[0]} | awk '{print $1}')
			linux_image=($(apt-cache search --names-only "linux-image-$expected.*-$kernel_type" | sort -r))
			linux_image=$(echo ${linux_image[0]} | awk '{print $1}')
			if [ -z "$(find -H /var/lib/apt/lists -maxdepth 0 -mtime -1)" ]
			then
				$scripts/dispatcher.sh -c WARNING -p "apt-get update" || exit $?
			fi
			pkgs=($linux_header $linux_image)
			for pkg in ${pkgs[@]}
			do
				while [ -z "$(dpkg -l | grep $pkg)" ]
				do
					$scripts/dispatcher.sh -c WARNING -p "apt-get install -y $pkg"
				done
			done
			exit 3
		fi
		;;
	"yum")
		echo "I'm not sure what to do here yet"
		exit 1
		;;
	*)
		echo "Package manager not recognized."
		exit 1
		;;
esac

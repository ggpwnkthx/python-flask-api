#!/bin/bash
version="2018.04.13"
tries=3

if [ -p /dev/stdin ]
then
	read
fi
# read the options
TEMP=`getopt -o vhi:r:m: --long version,help,install:,remove:,manager: -n "sysprep.sh" -- $@`
eval set -- "$TEMP"
# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -v|--version)
			echo "COACH/scripts/package_manager sysprep CLI version $version"
			exit
			;;
        -h|--help)
			echo "Usage:		/scripts/package_manager.sh [OPTIONS...] [ARGUMENTS...]"
			echo "Example:	/scripts/package_manager.sh -i docker.io"
			echo
			echo "OPTIONS"
			echo "-------"
			echo "-h, --help 	Help (this message)"
			echo "-v, --version	Version"
			echo
			echo "ARGUMENTS"
			echo "---------"
			echo "-m, --manager	Force the use of a specific manager"
			echo "-i, --install	Package to install"
			echo "-r, --remove	Package to remove"
			echo
			exit
			;;
		-m|--manager) package_manager=$2 ; shift 2 ;;
		-i|--install) install=$2 ; shift 2 ;;
		-r|--remove) remove=$2 ; shift 2 ;;
        --) shift ; break ;;
        *) echo "Internal error!" ; exit 1 ;;
    esac
done

scripts="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ -z "$package_manager" ]
then
	case $(echo $(lsb_release -ds 2>/dev/null || cat /etc/*release 2>/dev/null | head -n1 || uname -om) | awk '{print $1}') in
		"Ubuntu") package_manager="apt" ;;
		"Debian") package_manager="apt" ;;
		"Centos") package_manager="yum" ;;
		*) package_manager="UNKNOWN" ;;
	esac
fi

tried=0
if [ ! -z $install ]
then
	case $package_manager in
		"pip")
			if [ -z "$(command -v pip)" ]
			then
				$scripts/package_manager.sh -i python-pip || exit $?
				sudo $scripts/dispatcher.sh -c WARNING -p "python -m pip install -U pip" || exit $?
			fi
			while [ -z "$(pip freeze | grep $install)" ]
			do
				if [ $tried -lt $tries ]
				then
					sudo $scripts/dispatcher.sh -c WARNING -p "pip install $install" || exit $?
				else
					exit 2
				fi
				tried=$(($tried+1))
			done
			;;
		"apt")
			while [ -z "$(dpkg -l | grep $install)" ]
			do
				if [ -z "$(find -H /var/lib/apt/lists -maxdepth 0 -mtime -1)" ]
				then
					sudo $scripts/dispatcher.sh -c WARNING -p "apt-get update" || exit $?
				fi
				if [ $tried -lt $tries ]
				then
					sudo $scripts/dispatcher.sh -c WARNING -p "apt-get install -y $install" || exit $?
				else
					exit 2
				fi
				tried=$(($tried+1))
			done
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
fi

if [ ! -z $remove ]
then
	case $package_manager in
		"pip")
			while [ !-z "$(pip freeze | grep $remove)" ]
			do
				if [ $tried -lt $tries ]
				then
					sudo $scripts/dispatcher.sh -c WARNING -p "pip uninstall $remove" || exit $?
				else
					exit 2
				fi
				tried=$(($tried+1))
			done
			;;
		"apt")
			while [ ! -z "$(dpkg -l | grep $remove)" ]
			do
				sudo $scripts/dispatcher.sh -c WARNING -p "apt-get remove -y $remove" || exit $?
			done
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
fi
#!/bin/bash
version="2018.04.13"

if [ -p /dev/stdin ]
then
	read
fi
# read the options
TEMP=`getopt -o vhu:n: --long version,help,user:,node: -n "passwordless_sudo.sh" -- $@`
eval set -- "$TEMP"
# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -v|--version)
			echo "COACH/scripts/passwordless_sudo CLI version $version"
			exit
			;;
        -h|--help)
			echo "Usage:		/scripts/passwordless_sudo.sh [OPTIONS...] [ARGUMENTS...]"
			echo "Example:	/scripts/passwordless_sudo.sh -u notroot"
			echo
			echo "OPTIONS"
			echo "-------"
			echo "-h, --help 	Help (this message)"
			echo "-v, --version	Version"
			echo
			echo "ARGUMENTS"
			echo "---------"
			echo "-u, --user	Specify a user account"
			echo "-n, --node	Hostname (cosmedic only)"
			echo
			exit
			;;
		-u|--user) user=$2 ; shift 2 ;;
		-n|--node) node=$2 ; shift 2 ;;
        --) shift ; break ;;
        *) echo "Internal error!";  exit 1 ;;
    esac
done

scripts="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ "$user" == "" ]
then
	user=$(who am i | awk '{print $2}')
fi
if [ "$user" == "" ]
then
	if [ "$(whoami)" != "root" ]
	then 
		user=$(whoami)
	fi
fi
if [ "$user" == "" ]
then
	user=$SUDO_USER
fi
if [ "$user" == "" ]
then
	echo "Could not determine the applicable username."
	exit 1
fi

if [ ! -z $node ]
then
	node="-n $node"
fi

# Passwordless sudo
if [ ! -f /etc/sudoers.d/$user ]
then
	$scripts/dispatcher.sh $node -c WARNING -p "echo \"$user ALL = (root) NOPASSWD:ALL\" | tee /etc/sudoers.d/$user" || exit $?
	$scripts/dispatcher.sh $node -c WARNING -p "chmod 0440 /etc/sudoers.d/$user" || exit $?
fi

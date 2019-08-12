#!/bin/bash
version="2018.04.13"

if [ -p /dev/stdin ]
then
	read
fi
# read the options
TEMP=`getopt -o vhf:i: --long version,help,fqdn:,ip: -n "host_ip.sh" -- $@`
eval set -- "$TEMP"
# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -v|--version)
			echo "COACH/scripts/host_ip CLI version $version"
			exit
			;;
        -h|--help)
			echo "Usage:		/scripts/host_ip.sh [OPTIONS...] [ARGUMENTS...]"
			echo "Example:	/scripts/host_ip.sh -f node2.example.com -i 192.168.0.1"
			echo
			echo "OPTIONS"
			echo "-------"
			echo "-h, --help 	Help (this message)"
			echo "-v, --version	Version"
			echo
			echo "ARGUMENTS"
			echo "---------"
			echo "-f, --fqdn	Hostname - can be FQDN"
			echo "-i, --ip	Hostname - can be FQDN"
			echo
			exit
			;;
		-f|--fqdn) fqdn=$2 ; shift 2 ;;
		-i|--ip) ip=$2 ; shift 2 ;;
        --) shift ; break ;;
        *) echo "Internal error!";  exit 1 ;;
    esac
done

echo

scripts="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

$scripts/dispatcher.sh -c WARNING -p "sed -i -E \"s|(^.*)($fqdn)|$ip\t\2|g\" /etc/hosts" || exit $?

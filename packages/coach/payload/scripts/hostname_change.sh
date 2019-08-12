#!/bin/bash
version="2018.04.13"

if [ -p /dev/stdin ]
then
	read
fi
# read the options
TEMP=`getopt -o vhf: --long version,help,fqdn: -n "hostname_change.sh" -- $@`
eval set -- "$TEMP"
# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -v|--version)
			echo "COACH/scripts/hostname_change CLI version $version"
			exit
			;;
        -h|--help)
			echo "Usage:		/scripts/hostname_change.sh [OPTIONS...] [ARGUMENTS...]"
			echo "Example:	/scripts/hostname_change.sh -f node2.example.com"
			echo
			echo "OPTIONS"
			echo "-------"
			echo "-h, --help 	Help (this message)"
			echo "-v, --version	Version"
			echo
			echo "ARGUMENTS"
			echo "---------"
			echo "-f, --fqdn	Hostname - can be FQDN"
			echo
			exit
			;;
		-f|--fqdn)
			fqdn=$2
			domain=$(echo $2 | sed -n 's/[^.]*\.//p')
			name=$(echo $2 | sed 's/\..*//')
			shift 2 ;;
        --) shift ; break ;;
        *) echo "Internal error!";  exit 1 ;;
    esac
done

echo

scripts="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

while [ -z $name ]
do
	echo -e -n "Please set a fully qualified domain name for this host: " >&3
	read fqdn
	echo
done
if [ ! -z $(echo $fqdn | grep -P '(?=^.{1,254}$)(^(?>(?!\d+\.)[a-zA-Z0-9_\-]{1,63}\.?)+(?:[a-zA-Z]{2,})$)') ]
then
	domain=$(echo $fqdn | sed -n 's/[^.]*\.//p')
	name=$(echo $fqdn | sed 's/\..*//')
fi
while [ -z $domain ]
do
	echo -e -n "[${CYAN}$node${NC}]	Domain Name: " >&3
	read domain
	echo
done

if [ ! -z $(echo $(hostname -f) | grep -P '(?=^.{1,254}$)(^(?>(?!\d+\.)[a-zA-Z0-9_\-]{1,63}\.?)+(?:[a-zA-Z]{2,})$)') ]
then
	$scripts/dispatcher.sh -n $name -p "sed -i \"s/$(hostname -f)/$name.$domain/g\" /etc/hosts" || exit $?
fi
ip=$(cat /etc/hosts | grep "[[:space:]]$(hostname -s)$" | awk '{print $1}')
$scripts/dispatcher.sh -n $name -c WARNING -p "sed -i \"s/\(^.*[[:space:]]$(hostname -s)$\)/$ip\t$name.$domain $name/g\" /etc/hosts" || exit $?
$scripts/dispatcher.sh -n $name -c WARNING -p "echo $name > /etc/hostname" || exit $?
$scripts/dispatcher.sh -n $name -c WARNING -p "echo search $domain > /etc/resolvconf/resolv.conf.d/head" || exit $?
$scripts/dispatcher.sh -n $name -c WARNING -p "resolvconf -u" || exit $?
$scripts/dispatcher.sh -n $name -c WARNING -p "hostname $name" || exit $?

if [ "$name" != "$(hostname -s)" ]
then
	echo -e "[${RED}$node${NC}]	Local hostname did not become $node for some reason."
	echo -e "[${RED}$node${NC}]	Exiting to prevent corruption."
	exit 2
fi

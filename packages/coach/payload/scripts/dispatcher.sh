#!/bin/bash
version="2018.04.13"

# read the options
TEMP=`getopt -o vhrfn:c:p:l: --long version,help,fork,return,node:,class:,process:,log: -n "dispatcher.sh" -- "$@"`
eval set -- "$TEMP"

# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -v|--version)
			echo "COACH/scripts/dispatcher CLI version $version"
			exit
			;;
        -h|--help)
			echo "Usage:		/scripts/dispatcher.sh [OPTIONS...] [ARGUMENTS...]"
			echo "Example:	/scripts/dispatcher.sh -n node2 -c WARNING -p \"ssh -t ...\""
			echo
			echo "OPTIONS"
			echo "-------"
			echo "-h, --help	Help (this message)"
			echo "-v, --version	Version"
			echo
			echo "ARGUMENTS"
			echo "---------"
			echo "-n, --node	Name of the node to be displayed."
			echo "-c, --class	Class of notification. INFO/WARNING/ERROR/SUCCESS"
			echo "-p, --process	To be executed."
			echo "-l, --log	Path to log file."
			echo "-r, --return	Returns the value of the execution to the &1 channel."
			echo "-f, --fork	Partitions the output so that it's easier to read."
			echo
			exit
			;;
		-n|--node) node=$2; shift 2 ;;
		-c|--class) class=$2; shift 2 ;;
		-p|--process) process=$2; shift 2 ;;
		-l|--log) log=$2; shift 2 ;;
		-r|--return) return_value=1; shift ;;
		-f|--fork) fork=1; shift ;;
        --) shift; break ;;
        *) echo "Internal error!"; exit 1 ;;
    esac
done

# Visible Logs
if [ "$(tty)" != "not a tty" ]
then
	exec 3<> $(tty)
else
	log_file=$(mktemp)
	exec 3<> log_file
fi
# Return Variables
var=$(mktemp)
exec 4<> $var

if [ -z "$process" ]
then
	exit
fi
if [ -z "$node" ]
then
	node=$(hostname -s)
fi
if [ -z "$log" ]
then
	log=dispatcher_log
fi

behere="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Defaults
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Send command log to STD ch.3
if [ -z $fork ]
then
	linepull="-n"
fi
if [ ! -z $fork ]
then
	echo 1>&3
fi
case $class in
	INFO) echo -e $linepull "[${CYAN}$node${NC}]	$process... " 1>&3 ;;
	SUCCESS) echo -e $linepull "[${GREEN}$node${NC}]	$process... " 1>&3 ;;
	WARNING) echo -e $linepull "[${YELLOW}$node${NC}]	$process... " 1>&3 ;;
	ERROR) echo -e $linepull "[${RED}$node${NC}]	$process... " 1>&3 ;;
	*) echo -e $linepull "[$node]	$process... " 1>&3 ;;
esac
if [ ! -z $fork ]
then
	printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' - 1>&3
fi

# Run the command
value=$(bash -c "$process")
exit_code=$?

# Close STD ch.4
exec 4>&-

#Check for special return values
if [ ! -z "$(cat $var)" ]
then
	value=$(cat $var)
fi

# Close out formatting
if [ ! -z $fork ]
then
	printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' = 1>&3
fi
case $exit_code in
	0) echo -e "${GREEN}completed${NC}." 1>&3 ;;
	1) echo -e "${RED}failed${NC}." 1>&3 ;;
	2) echo -e "${YELLOW}nonfatal error${NC}." 1>&3 ;;
	3) echo -e "${CYAN}reboot required${NC}." 1>&3 ;;
esac

# Close STD ch.3
exec 3>&-

# Send return value to STD ch.1
if [ "$return_value" == "1" ]
then
	echo -e $value
fi

# Delete temp file
rm $var

# Passthru exit code
exit $exit_code
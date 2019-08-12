#!/bin/bash
version="2018.04.13"

# read the options
TEMP=`getopt -o vheaf:u:p:n:j:c:k: --long version,help,encrypt,advanced,fqdn:,user:,pass:,node:,json:,cidr:,key: -n "run.sh" -- "$@"`
eval set -- "$TEMP"

# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -v|--version)
			echo "COACH CLI version $version"
			exit
			;;
        -h|--help)
			echo "Usage:		./run.sh [OPTIONS...] [ARGUMENTS...]"
			echo "Example:	./run.sh -node node2 -n node3,192.168.0.3"
			echo "Encryption:	echo [aes-128-cbc salted] | ./run.sh -k passphrase"
			echo
			echo "OPTIONS"
			echo "-------"
			echo "-h, --help	Help (this message)"
			echo "-v, --version	Version"
			echo "-e, --encrypt	Encryption information"
			echo "-a, --advanced 	Advanced information"
			echo
			echo "ARGUMENTS"
			echo "---------"
			echo "-u, --user	Run as a specified user"
			echo "-p, --pass	Unencrypted sudo password for current user (not recommended)"
			echo "-f, --fqdn	Set fully qualified domain name for this node"
			echo "		  -f node2.example.com"
			echo "-n, --node	Node to add to the cluster (can be used multiple times)"
			echo "		  -n hostname,ip"
			echo "-j, --json	Use a JSON file instead of the node arguments"
			echo "-c, --cidr	Force use of specific CIDR (used by ceph)"
			echo "		  -c 192.168.0.0/24"
			echo "-k, --key	Used if piping an encrypted password"
			echo
			exit
			;;
        -e|--encrypt)
			echo "ENCRYPTION"
			echo "----------"
			echo "To avoid the transmission of plain text passwords, an encrypted password can be piped to this script."
			echo "Example:	echo [aes-256-cbc salted] | ./run.sh -j nodes.json -k passphrase"
			echo "     or:	./SomePasswordProgram | ./run.sh -j nodes.json -k passphrase"
			echo
			echo "Passwords are expected to be a salted, 256bit, CBC mode, AES encrypted string."
			echo "To encrypt your password, use the following command, preferably on an unrelated host."
			echo "echo 'PasswordGoesHere' | openssl enc -aes-256-cbc -a -salt -pass pass:KeyGoesHere"
			echo
			echo "In this script \"key\" is synonymous is \"passphrase\"."
			echo
			exit
			;;
        -a|--advanced)
			echo "ADVANCED"
			echo "--------"
			echo "If each node has a different username or password, the nodes argument can be the path to a JSON file. In that case, the ips argument is ignored, and are expected to be in the JSON file if necessary. The passwords must be encrypted and are expected to use the same key."
			echo "Syntax:"
			echo "{\"nodes\":[{\"node\":\"test2\",\"ip\":\"192.168.0.2\",\"user\":\"notroot\",\"password\":\"aes-128-cbc salted\"}]}"
			echo "Example:	./run.sh -j nodes.json -k passphrase"
			echo
			echo "Usernames and passwords can be omitted from the JSON file if the are the same as the host running the script."
			echo
			exit
			;;
		-u|--user) user=$2; shift 2 ;;
		-p|--pass) password=$2; shift 2 ;;
		-f|--fqdn) fqdn=$2; shift 2 ;;
		-j|--json) json=$2; shift 2 ;;
		-c|--cidr) cidr=$2; shift 2 ;;
		-k|--key) key=$2; shift 2 ;;
		-n|--node)
			n=$(echo $2 | awk '{split($0, a, ","); print a[1]}')
			i=$(echo $2 | awk '{split($0, a, ","); print a[2]}')
			nodes[$n]=$i
			shift 2
			;;
        --) shift; break ;;
        *) echo "Internal error!"; exit 1 ;;
    esac
done

if [ "$(tty)" == "not a tty" ]
then
	log_file=$(mktemp)
	exec 3<> log_file
	exec 4<> log_file
else
	exec 3<> $(tty)
	exec 4<> $(tty)
fi

root="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
scripts=$root/scripts

if [ ! -x "$scripts/dispatcher.sh" ]
then
	chmod +x "$scripts/dispatcher.sh"
fi

# Make sure other scripts are executable
list=(3rd-Party/JSON.sh-master/JSON passwordless_sudo sysprep)
for i in ${list[@]}
do
	if [ ! -x "$scripts/$i.sh" ]
	then
		$scripts/dispatcher.sh -c WARNING -p "chmod +x $scripts/$i.sh" || exit $?
	fi
done

# Get values from JSON file, if applicable
if [ ! -f "$json" ]
then
	json="$root/$json"
fi
if [ -f "$json" ]
then
	if [ -z $user ]
	then
		user=$("$scripts/3rd-Party/JSON.sh-master/JSON.sh" < $json | grep "\"localhost\",\"user\"" | awk '{print $2}' | cut -d "\"" -f 2)
	fi
	if [ -z $password ]
	then
		if [ -z "$key" ]
		then
			password=$("$scripts/3rd-Party/JSON.sh-master/JSON.sh" < $json | grep "\"localhost\",\"password\"" | awk '{print $2}' | cut -d "\"" -f 2)
		else
			encrypted=$("$scripts/3rd-Party/JSON.sh-master/JSON.sh" < $json | grep "\"localhost\",\"password\"" | awk '{print $2}' | cut -d "\"" -f 2)
		fi
	fi
	if [ -z $fqdn ]
	then
		fqdn=$("$scripts/3rd-Party/JSON.sh-master/JSON.sh" < $json | grep "\"localhost\",\"fqdn\"" | awk '{print $2}' | cut -d "\"" -f 2)
	fi
	if [ -z $fqdn ]
	then
		node=$("$scripts/3rd-Party/JSON.sh-master/JSON.sh" < $json | grep "\"localhost\",\"hostname\"" | awk '{print $2}' | cut -d "\"" -f 2)
		domain=$("$scripts/3rd-Party/JSON.sh-master/JSON.sh" < $json | grep "\"localhost\",\"domain\"" | awk '{print $2}' | cut -d "\"" -f 2)
		fqdn="$node.$domain"
	fi
	if [ -z $cidr ]
	then
		cidr=$("$scripts/3rd-Party/JSON.sh-master/JSON.sh" < $json | grep "\"localhost\",\"cidr\"" | awk '{print $2}' | cut -d "\"" -f 2)
	fi	
fi

# Set the user variable to the current user if it's not already set
if [ -z $user ]
then
	user=$(whoami)
fi

# Fix variables strings to that they can be passed to other scripts
if [ ! -z $cidr ]
then 
	cidr="-c $cidr"
fi
if [ ! -z $user ]
then 
	user="-u $user"
fi
if [ -z $node ]
then
	if [ -z "$fqdn" ]
	then
		node=$(hostname -s)
	else
		node=$(echo $fqdn | sed 's/\..*//')
	fi
fi
if [ ! -z $node ]
then
	node="-n $node"
fi
if [ ! -z $fqdn ]
then 
	fqdn="-f $fqdn"
fi
if [ -p /dev/stdin ]
then
	encrypted=$(cat)
fi

# Enable passwordless sudo
# TO NOT EXPOSE VARIABLES, WE DO NOT USE DISPATCHER HERE
if [ ! -z $encrypted ]
then
	sudo -S "$scripts/passwordless_sudo.sh" $user $node <<< $(echo $encrypted | openssl enc -aes-256-cbc -a -d -salt -pass pass:$key)
else
	if [ -z $password ]
	then
		if [ -z $verbose ]
		then
			exec 2<> $(tty)
		fi
		sudo "$scripts/passwordless_sudo.sh" $user $node
		if [ -z $verbose ]
		then
			exec 2<> /dev/null
		fi
	else
		echo $password | sudo -S echo -n 2>/dev/null
		sudo "$scripts/passwordless_sudo.sh" $user $node
	fi
fi

# Prep the system
sudo $scripts/dispatcher.sh $node -f -c WARNING -p "$scripts/sysprep.sh $user $fqdn" || exit $?

# Bootstrap Network
storage_fabric=($($scripts/dispatcher.sh -r -f -c WARNING -p "$scripts/fabric.sh $cidr")) || exit $?
if [ ! -z ${storage_fabric[1]} ]
then
	cidr=${storage_fabric[1]}
	ip=(${cidr//\// })
	ip=${ip[0]}
fi
sudo $scripts/dispatcher.sh -r -f -c WARNING -p "$scripts/host_ip.sh $fqdn -i $ip" || exit $?

# Ceph - Cluster Storage Bootstrapping
$scripts/dispatcher.sh -f -c WARNING -p "$scripts/ceph.sh" || exit $? 
$scripts/dispatcher.sh -f -c WARNING -p "$scripts/dnsmasq.sh $cidr" || exit $?
 
echo "{" > "$root/config.json"
echo "  \"localhost\": {" >> "$root/config.json"
echo "    \"user\":\"$user\"," >> "$root/config.json"
echo "    \"hostname\":\"$host_name\"," >> "$root/config.json"
echo "    \"domain\":\"$domain_name\"," >> "$root/config.json"
echo "    \"cidr\":\"${cidr[1]}\"" >> "$root/config.json"
echo "  }" >> "$root/config.json"
echo "}" >> "$root/config.json"

exec 3>&-
exec 4>&-
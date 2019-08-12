#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

ceph -s >/dev/null 2>/dev/null

if [ ! -z $(command -v ceph) ]
then
	disks=($(ceph-disk list | grep unknown | grep -v loop | awk '{print $1}'))
	for disk in ${disks[@]}
	do
		if [ "$(lsblk -p -o kname,type | grep $disk | awk '{print $2}')" == "disk" ]
		then
			echo -e -n "[${YELLOW}$(hostname -s)${NC}]	ceph-disk zap $disk... " 1>&2
			ceph-disk zap $disk >> auto-add-osd_log && echo -e "${GREEN}completed${NC}." 1>&2 || echo -e "${RED}failed${NC}." 1>&2
			echo -e -n "[${YELLOW}$(hostname -s)${NC}]	ceph-disk prepare $disk... " 1>&2
			ceph-disk prepare $disk >> auto-add-osd_log && echo -e "${GREEN}completed${NC}." 1>&2 || echo -e "${RED}failed${NC}." 1>&2
			echo -e -n "[${YELLOW}$(hostname -s)${NC}]	ceph-disk activate \"$disk\"1... " 1>&2
			ceph-disk activate "$disk"1 >> auto-add-osd_log 2>> auto-add-osd_log && echo -e "${GREEN}completed${NC}." 1>&2 || echo -e "${RED}failed${NC}." 1>&2
		fi
	done
fi

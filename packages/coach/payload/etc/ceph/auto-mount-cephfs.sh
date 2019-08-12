#!/bin/bash

while [ -z "$(df -h | grep /mnt/cephfs)" ]
do
	ceph -s
	ceph_mons=""
	mons=($(ceph mon dump 2>/dev/null | grep mon | awk '{print $2}' | awk '{split($0,a,"/"); print a[1]}'))
	for i in ${mons[@]}
	do
		if [ -z "$ceph_mons" ]
		then
			ceph_mons=$i
		else
			ceph_mons="$ceph_mons,$i"
		fi
	done
	secret=$(ceph-authtool -p /etc/ceph/ceph.client.admin.keyring)
	mount -t ceph $ceph_mons:/ /mnt/cephfs -o name=admin,secret=$secret
done

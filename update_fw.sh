#!/bin/bash
#
#  Copyright (c) 2020 by Penguin Computing
#
#
PDU_IP=${1:?Specify PDU on command line}
PDU_USR=admin
PDU_PWD=654321
#
#logfile=$(date +$0.%Y%m%d-%H%M.log)
#exec 2>&1 | tee -a $logfile
#echo "Starting at $(date) logging to $logfile"
echo "=== $(date)  Starting ... "

wget --user $PDU_USR  --password $PDU_PWD  --read-timeout=5 -nv -O/dev/null http://${PDU_IP}/setting.html
if ( test $? -ne  0) then
	echo Can not talk to $PDU_IP with wget.  Retrying ...
	wget --user $PDU_USR  --password $PDU_PWD  --read-timeout=5 -nv -O/dev/null http://${PDU_IP}/setting.html
	while ( test $? -ne  0) do
		echo -n "."
		sleep 5
		wget --user $PDU_USR  --password $PDU_PWD  --read-timeout=5 -nv -O/dev/null http://${PDU_IP}/setting.html
	done
	echo "$PDU_IP is back online"
fi
#
vers=$(snmpget -v2c -cpublic $PDU_IP sysDescr | sed -e 's/.*\(V1.*\) -.*/\1/')
echo "=== $PDU_IP version is $vers"
#
# Find a firmware file
# look locally for the "latest" SCC* file
local_FW=$(ls -1 SCC* | tail -1)
PDU_FW=${2:-$local_FW}
echo "Firmware in this directory is"
ls -1 SCC*
if [ ! -f $PDU_FW ]; then echo "WARNING: Requested $PDU_FW is not a file or does not exist" ; fi
read -p "Update to firmware to $PDU_FW ? [y/N] " ans
if test "$ans" = "y"
then
	echo "Upgrading to $PDU_FW"
else 
	echo "Not upgrading"
	exit 1
fi
name_FW=$(basename $PDU_FW)

# put into accepting FW mode
echo "=== $(date)  Putting powershelf into accepting FW mode ..."
echo "NOTE: Timeout is normal and expected"
curl --user $PDU_USR:$PDU_PWD --verbose --max-time 40 --get --url http://${PDU_IP}/setting.html?51=51
# determine when controller returns
curl --user $PDU_USR:$PDU_PWD --verbose  --retry 25 --retry-delay 10 --get --url http://${PDU_IP}/ | grep -A2 -a dl=
#
# POST Firmware file
echo
echo "=== $(date)  Starting firmware upload ..."
# uploading firmware is a form upload with a field named "upfile" having the file that needs to be uploaded.
curl --user $PDU_USR:$PDU_PWD --verbose  --max-time 60  -F "upfile=@$PDU_FW;filename=$name_FW;type=application/octet-stream" --url http://${PDU_IP}/ | grep -A2 -a dl=
echo
echo "=== $(date)  Finished uploading"

( wget --user $PDU_USR  --password $PDU_PWD -nv -O-  --read-timeout=5 http://${PDU_IP} | grep -A2 -a dl= ; echo )
if ( test $? -ne  0) then
	echo Can not talk to $PDU_IP with wget.  Retrying ...
	wget --user $PDU_USR  --password $PDU_PWD -nv -O/dev/null --read-timeout=5 http://${PDU_IP} 
	while ( test $? -ne  0) do
		echo -n "."
		sleep 5
		wget --user $PDU_USR  --password $PDU_PWD -nv -O/dev/null --read-timeout=5 http://${PDU_IP}
	done
	echo "$PDU_IP is back online"
fi
# Reboot controller
echo "=== $(date)  Rebooting PSU $PDU_IP"
echo "NOTE: Timeout is normal and expected"
curl --user $PDU_USR:$PDU_PWD --verbose --max-time 30 --get --url http://${PDU_IP}/?b=NGC
#
sleep 5
wget --user $PDU_USR  --password $PDU_PWD  --read-timeout=5 -nv -O/dev/null http://${PDU_IP}/setting.html
if ( test $? -ne  0) then
	echo Can not yet talk to $PDU_IP with wget.  Retrying ...
	wget --user $PDU_USR  --password $PDU_PWD  --read-timeout=5 -nv -O/dev/null  http://${PDU_IP}/setting.html
	while ( test $? -ne  0) do
		echo -n "."
		sleep 5
		wget --user $PDU_USR  --password $PDU_PWD  --read-timeout=5 -nv -O/dev/null  http://${PDU_IP}/setting.html
	done
fi
echo "=== $(date)  $PDU_IP is back online"
#
# Check the current version.
vers=$(snmpget -v2c -cpublic $PDU_IP sysDescr | sed -e 's/.*\(V1.*\) -.*/\1/')
echo "=== $(date)  $PDU_IP version is $vers"
#
#
exit 0

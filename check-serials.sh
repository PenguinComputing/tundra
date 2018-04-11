#!/bin/bash
#
# Check rectifier serial numbers for repair/replace/RMA status
#

# Some specific OID from EES-POWER-MIB.mib

# rectNumberPresent
rectNP=enterprises.6302.3.1.20

# rectRectifierModel
rectRM=enterprises.6302.3.1.21.1.13

# rectRectifierSerialNumber
rectRSN=enterprises.6302.3.1.21.1.14

# rectLEDFlash
# NOTE: 0 is BLINKING, 1 is NOT blinking
rectLEDF=enterprises.6302.3.1.21.1.15

# Usage
usage () {
   echo "usage: $0  psu-ip [ psu-ip ]"
   echo "where:  psu-ip is a name or IP address of one or more power shelves"
   echo "        Will check that power shelf for rectifiers and list their status"
   echo ""
   echo "usage: $0 -b psu-ip SN"
   echo "where:  SN is a rectifer serial number"
   echo "        Will blink a rectifier with the given serial number if found"
}

# Classify by SN
checkSN () {
   local SN=$1
   shift

   if [ -z "$SN" ]; then return; fi

   case "$SN" in

   ### Rectifiers that need to be identified for beta firmware
   03160400443 | 03160400455 | 03160400469 | 03160400497 | 03160400509 | 03160400512 | 03160400517 | 03160400525 | 03160400526 )
      status="RMA to Penguin"
      ;;

   ### Rectifiers to be reworked, BEFORE 1708
   031[1-6][0-9][0-9]* | 03170[0-7]* )
      status="Return for rework"
      ;;

   ### Rectifers that are fine, 1708 or later
   03170[89]* | 0317[1-9][0-9]* | 031[89][0-9][0-9]* )
      status="Return for firmware update"
      ;;

   ### Unrecognized SN
   * )
      status="Unrecognized, please REPORT"
      ;;

   esac

   if [[ "x$1" = x-q* ]]; then
      :  # Don't echo, just set 'status'
   else
      echo "$status"
   fi

   return
}

for psu in "$@" ; do
   count=$(snmpget -v2c -cpublic -Oq -Ov $psu $rectNP)
   snlist=( $(snmpget -Oq -Ov $psu $(seq -f "$rectRSN.%.0f" 1 $count) ) )

   for sn in "${snlist[@]}" ; do 
      checkSN "$sn" -q
      echo "$psu: $sn = $(checkSN "$sn") -- $status"
   done
done


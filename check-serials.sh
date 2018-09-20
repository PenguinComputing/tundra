#!/bin/bash
#
# Check rectifier serial numbers for repair/replace/RMA status
#

# Some specific OID from EES-POWER-MIB.mib
#   Use numeric OID here so we don't have to depend on EES-POWER-MIB.mib being
#      functionally available

# Controller firmware
contSWV=sysDescr
#.1.3.6.1.2.1.1.1 = STRING: Vertiv - 12VDC Shelf Control Card - SW V1.05.04 - 00:09:f5:0e:6d:33

# rectNumberPresent
rectNP=enterprises.6302.3.1.20

# rectRectifierModel
rectRM=enterprises.6302.3.1.21.1.13

# rectRectifierSerialNumber
rectRSN=enterprises.6302.3.1.21.1.14

# rectHWVersion
rectHWV=enterprises.6302.3.1.21.1.20

# rectSWVersion
rectSWV=enterprises.6302.3.1.21.1.21

# rectDateCode
rectDC=enterprises.6302.3.1.21.1.22

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
   03170[89]* | 0317[1-9][0-9]* )
      status="Return for firmware update"
      ;;

   ### Rectifiers that are newest build.  Should not require updates
   0318* )
      status="New unit, no rework"
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

blink=""
for psu in "$@" ; do

   #### BLINK function
   if [[ "x$psu" = x-b* ]]; then
      # Switch to blink mode
      blink=yes
      continue ;
   fi

   if [[ -n "$blink" ]]; then
      # Is this a serial number?
      if [[ "$psu" = 03[0-9]* ]]; then
         # Send blink command to saved psu
         if [[ -z "$blinkpsu" ]]; then
            echo "*** Specify PSU first before serial numbers for blink mode"
         else
            # Find the SN on the psu
            sn=$psu
            count=$(snmpget -v2c -cpublic -Oq -Ov $blinkpsu $rectNP)
            slot=$(snmpget -v2c -cpublic -Oq -Ov $blinkpsu $(seq -f "$rectRSN.%.0f" 1 $count) | awk '$1==sn{print NR}' sn=$sn)
            if [[ -z "$slot" ]]; then
               echo "*** Serial number '$sn' not found on $blinkpsu"
            else
               echo "Blinking serial number '$sn' on $blinkpsu"
               snmpset -v2c -cprivate $blinkpsu $rectLEDF.$slot i 0
            fi
         fi
      else
         # Assume it's a PSU name/IP address
         blinkpsu=$psu
      fi
      continue  # next parameter
   fi
   #### END BLINK function

   #### PSU and serial number checking
   version=$(snmpget -v2c -cpublic -Oq -Ov $psu $contSWV)
   echo "$psu: $version"
   case "$version" in
   *SW\ V1.03.03* )
       echo "*** WARNING: Old shelf manager firmware detected."
       echo "       Unable to read rectifier details.  Only checking serial numbers"
       psufw=V1.03.03 ;;
   *SW\ V1.0[56].* )
       psufw=V1.05.x ;;
   * )
       echo "*** WARNING: Unrecognized module firmware.  Please upgrade to V1.05.04 or later"
       psufw=error ;;
   esac

   count=$(snmpget -v2c -cpublic -Oq -Ov $psu $rectNP)
   echo "=== Found $count rectifiers"

   # snlist=( $(snmpget -v2c -cpublic -Oq -Ov $psu $(seq -f "$rectRSN.%.0f" 1 $count) ) )

   # Check each rectifier "slot"
   for slot in $(seq -f "%.0f" 1 $count) ; do

      sn=$(snmpget -v2c -cpublic -Oq -Ov $psu $rectRSN.$slot | tr -d '"')
      iscurrent=no

      if [[ "$psufw" = V1.05?* ]]; then
         iscurrent=yes   # Assume is current
         # Update "status" with HW/SW/DateCode details
         hwv=$(snmpget -v2c -cpublic -Oq -Ov $psu $rectHWV.$slot | tr -d '"')
         swv=$(snmpget -v2c -cpublic -Oq -Ov $psu $rectSWV.$slot | tr -d '"')
         rdc=$(snmpget -v2c -cpublic -Oq -Ov $psu $rectDC.$slot | tr -d '"')

         status="DC $rdc"

         if [[ "$hwv" == A02 ]]; then
            status="$status -- HW $hwv is current"
         else
            status="$status -- HW $hwv requires REWORK"
            iscurrent=no
         fi


         if [[ "$swv" == 9.0[67] || "$swv" == 1.03 ]]; then
            status="$status -- SW $swv is current"
         else
            status="$status -- SW $swv requires UPDATE"
            iscurrent=no
         fi

         if [[ "$iscurrent" == no ]]; then
            status="Return for update -- $status"
         else
            status="Is current -- $status"
         fi
      else
         iscurrent=no   # Assume is NOT current
         checkSN "$sn" -q    # sets "status"
      fi

      echo "$psu: $sn = $status"
   done
done


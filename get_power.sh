#!/bin/bash
#

for psu in "$@" ; do
   if [ "$psu" = header ]; then
      printf "%-10s %7s %5s %6s\n" "  Shelf" Voltage Amps Watts ;
   else 
      printf "%-10s %7d %5d %6d\n" "$psu" \
            $(snmpget -v2c -cpublic --mibfile=EES-POWER-MIB-201805160526Z.mib -Oq -Ov $psu statusShelfOutputVoltage.0 statusShelfOutputCurrent.0 statusShelfOutputPower.0)
   fi
done

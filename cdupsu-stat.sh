#!/bin/bash
#
# Version 1.1
#    Consolidated snmpget into one call per device
#    Accept rack numbers on the command line

# Command line list or default?
racklist=( "$@" )
if [[ ${#racklist[@]} -eq 0 ]]; then
   # No rack numbers on the command line
   racklist=( 1 2 3 5 6 7 9 10 11 12 13 14 16 17 18 20 21 22 )
fi

# Header
echo "=== $(date)"
if [[ -z "$HEADER" ]]; then
  echo   "    |       CDU                                      |           PSU "
  printf "%4s| %4s %4s %3s %3s %4s %3s %3s %4s %4s %5s | %5s %5s %5s %s\n" Rack  Ctrl Flow Fin Fot Fmb Sin Sot Smb Leak Watts  kW Volt Amp Status
fi

for rack in "${racklist[@]}" ; do

   if [[ -z "$(getent hosts cdu$rack)" ]]; then
      # Skip this rack number since there is no cdu name?
      continue ;
   fi

#   ping -c2 cdu$rack >/dev/null 2>&1 &
#   ping -c2 psu$rack >/dev/null 2>&1 &
#   wait ;

   rack1psu=( $(snmpget -Oq -Ov -OU psu$((rack * 2 -1)) \
            statusShelfOutputPower.0 statusShelfOutputCurrent.0) )
#   rack2psu=( $(snmpget -Oq -Ov -OU psu$((rack * 2)) \
#            statusShelfOutputPower.0 statusShelfOutputCurrent.0) )
   rack2psu=( 0 0 )


   printf "%3d | %4d %4d %3d %3d %4d %3d %3d %4d %4d %5d | %5d       %5d\n" $rack \
      $(snmpget -Oq -Ov -OU cdu$rack \
            controllerOut.0 flowFacility.0 temperatureFacilityIn.0 \
            temperatureFacilityOut.0 pressureFacility.0 \
            temperatureServerIn.0 temperatureServerOut.0 \
            pressureServer.0 serverLeak.0 heatload.0) \
      $(( ${rack1psu[0]} + ${rack2psu[0]} )) \
      $(( ${rack1psu[1]} + ${rack2psu[1]} )) 

#   printf "                                                     | %5d %5d %5d %s\n" \
#      $(snmpget -Oq -Ov -OU psu$((rack * 2)) \
#            statusShelfOutputPower.0 statusShelfOutputVoltage.0 \
#            statusShelfOutputCurrent.0 statusShelfStatus.0) 

   printf "                                                     | %5d %5d %5d %s\n" \
      $(snmpget -Oq -Ov -OU psu$((rack * 2 -1)) \
            statusShelfOutputPower.0 statusShelfOutputVoltage.0 \
            statusShelfOutputCurrent.0 statusShelfStatus.0) 

done

wait ;

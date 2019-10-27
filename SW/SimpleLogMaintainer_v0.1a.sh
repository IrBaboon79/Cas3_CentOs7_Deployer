#!/usr/bin/env bash

LOGFILE=log_file_to_maintain
MAXREPAIRLOGSIZE=100

ACTUALSIZE=`du -sm "$LOGFILE" | cut -f 1`

echo "Simple Log File Maintainer / RTi 2019"
echo "*************************************"
echo "`date +%Y-%m-%d:%H:%M:%S` - File: $LOGFILE, Max allowed Size: $MAXREPAIRLOGSIZE MB, Detected size: $ACTUALSIZE MB"
echo -n "`date +%Y-%m-%d:%H:%M:%S` - Result : "

if [ $ACTUALSIZE -lt $MAXREPAIRLOGSIZE ] ; then 
    echo "Below Threshold : leaving file alone!"; 
else 
    echo "Over Threshold => purging logfile!"; 
    rm -f $LOGFILE
fi
#!/usr/bin/env bash

##### VERSION #####
script_version='v0.2c'

##### CONFIGURATION #####
CASSANDRA_CONFIG_DIR="/etc/cassandra"
CASSANDRA_NODETOOL_DIR="/usr/bin/"
JMX_REMOTE_PORT=8090
LOGDIR="/var/log/cassandra/MaintenanceLog"
LOGFILE="$LOGDIR/repairlog.log"
MAX_LOG_SIZE=100M
##### CONFIGURATION #####


#####
## Script History
## --------------
##  v0.2c / 05-2021 - Fixed a few minor bugs wr to logging & improved the handling in general
##                  - Added check/abort on non-existing cassandra yaml & nodetool pointing to invalid configuration of the 2 variables.
##                  - more comments
#####

# set an array with the names of the days
DayName_array=(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)
DOW=$(date +%A) # get today's full name
RUNSTART=$(date +%c)

# this simplifies logging and just makes things clearer to read
function log_write()
{
  if [[ $2 =~ 'nostamp' ]]; then echo "$1" | tee -a $LOGFILE   
    else echo "[`date +%Y-%m-%d:%H:%M:%S`] $1" | tee -a $LOGFILE 
  fi   
}

# This can happen on multiple occasions for multiple reasons so let's generalize this here...
function exit_script()
{
 log_write "================================================< Done! exit code: $1 / $RUNSTART >==" nostamp
 exit $1
}

clear

if [ -f $LOGFILE ]; then # only if file exists..
        # wipe large logfile; note there is also a seperate systemd 'service' that maintains the logfile as well so this is basically no longer needed...just for security then!
	if [ `du -sm "$LOGFILE" | cut -f 1` -lt $MAX_LOG_SIZE ]; then 	
	      	LOGSTAT="Logfile $LOGFILE below $MAX_LOG_SIZE threshold - leaving it alone for now..."
	 else
	        rm -f $LOGFILE
	        LOGSTAT="Logfile $LOGFILE exceeded $MAX_LOG_SIZE MiB - logfile was cleared!"
	fi
fi

# if directory does not exist
if [ ! -d $LOGDIR ]; then 
 mkdir -p $LOGDIR > /dev/null  # create the logfolder
fi

log_write "Cassandra Node Maintenance bash Magic $script_version / RTi" nostamp
log_write "==< Start / $RUNSTART >==============================================================" nostamp
log_write "Starting Cassandra 3 Repair Script ..."
log_write "Reading Cassandra Configuration from: $CASSANDRA_CONFIG_DIR/cassandra.yaml"
log_write "Using nodetool location: $CASSANDRA_NODETOOL_DIR "
log_write "Logging to journal/stdout & Writing logfile to: $LOGFILE"
log_write "$LOGSTAT"

#check if config file / nodetool can be found...
 if [ ! -f $CASSANDRA_CONFIG_DIR/cassandra.yaml ] || [ ! -f $CASSANDRA_NODETOOL_DIR/nodetool ]; then 
   log_write "Error finding cassandra.yaml ($CASSANDRA_CONFIG_DIR ??) or nodetool ($CASSANDRA_NODETOOL_DIR ??) - configuration error! Aborting!"
   exit_script 1
fi


# First figure out local listening Address...

log_write "Determining this node's listening address from /cassandra/conf/cassandra.yaml..."
Local_Listen_Address=$(cat $CASSANDRA_CONFIG_DIR/cassandra.yaml | grep "listen_address:" | cut -d " " -f 2)

if [ -z $Local_Listen_Address ]; then  # failsafe, try the hostname if above fails...
       Local_Listen_Address=`hostname -i`   
     fi
     log_write "Using Listen Address (from cassanda.yaml): $Local_Listen_Address ..."

# now see if we can reach it!

log_write "Querying Node Status..."
NodeStatusArray=($($CASSANDRA_NODETOOL_DIR/nodetool -h $Local_Listen_Address -p $JMX_REMOTE_PORT status 2> /dev/null | grep "UN " | sort | awk '{print $2}'))
# The returned array SHOULD be properly sorted with the lowest number in position #0...

# array empty OR failed to execute cassandra/nodetool?

if [ -z "$NodeStatusArray" ]; then #Array is empty, we exit hard here so we dont end up doing nonsense!
    log_write "Cassandra Service seems down/unreachable on Node ($Local_Listen_Address) or we received an unexpected response ==> Unable to perform action - Aborting!"
    exit_script 1
    else 
      log_write "Node $Local_Listen_Address successfully contacted..."

fi

Array_len=${#NodeStatusArray[@]} #get the length of the array

log_write "$Array_len Nodes that Reported as Up/Normal..."
echo $NodeStatusArray | nl -n rn | tee -a $LOGFILE

log_write "Detected $Array_len nodes with UN (Up + Normal) status..."

for (( i=0; i<=$(( $Array_len -1 )); i++ ))
do
    #first get the mod 7 so we know the day a node should be triggered
    day=$(($i%7))
    echo -ne "\t\t      Node ${NodeStatusArray[$i]} would be scheduled on ${DayName_array[$day]} " | tee -a $LOGFILE
    
    if [[ "${DayName_array[$day]}" == "$DOW" ]]; then 
                                                      log_write "==> This node should be repaired today... Let's add it to the list of Repairees..." nostamp
                                                      Nodes_To_Repair_Today_Array+=( ${NodeStatusArray[$i]} )
     else
        log_write "==> This should NOT be repaired today!" nostamp
     fi
done

Repair_Array_len=${#Nodes_To_Repair_Today_Array[@]} #get the length of the array


if [ "$Repair_Array_len" -gt 1 ]; then # if there is more than 1 item to repair in the list, pick the first item as the Commander node.
   log_write "$Repair_Array_len Nodes due for Repair Today:"
   echo "$Nodes_To_Repair_Today" | nl -n rn | tee -a $LOGFILE
   
   log_write "*ASSUMING* First Node as 'Commander': ${NodeStatusArray[0]}"
   Commander_Node=${NodeStatusArray[0]}

   else
      log_write "No ($Repair_Array_len) Nodes due for Repair Today! Exiting Normally..."
      exit_script 0      
      
fi

# Now, figure out which node will be the one executing the repair command...
# 1) We'll assume the FIRST element of the nodes (as it's sorted) will be the one to execute the command and will issue it to anything in need of repair
# 2) Determine if this node is the commander
# 3) in case it's localhost we make an exception and take the commander role.
# 4) the commander will iterate through the list of repairees; this will probably break when nodes exceed >255 OR repair time exceeds 24h (the next trigger of the script...) but we're not google so worry about that later.

if [[ "$Local_Listen_Address" = "$Commander_Node" ||  "$Local_Listen_Address" = "localhost" ]] ; then
                                                     for Node in $Nodes_To_Repair_Today_Array; do
                                                            log_write "Current Machine is assumed to be the Commander - Proceeding to Repair Action..."
                                                            log_write "Starting nodetool -h $Node -p $JMX_REMOTE_PORT repair -pr"                                                            
							    log_write " ==> Executing repair against $Node: $CASSANDRA_NODETOOL_DIR/nodetool -h $Node -p $JMX_REMOTE_PORT repair -pr" nostamp
                                                            $CASSANDRA_NODETOOL_DIR/nodetool -h $Node -p $JMX_REMOTE_PORT repair -pr | tee -a $LOGFILE

                                                                    if [ $? -ne 0 ]; then
                                                                        log_write "Error while running the repair job on Node $Node !!"
                                                                        exit_script 1
                                                                                                        
                                                                    else
                                                                        log_write "Finished nodetool -h $Node -p $JMX_REMOTE_PORT repair -pr - Exiting Normally..."
                                                                        exit_script 0
                                                                    fi
                                                                                        done
  else
   log_write "Current Machine is NOT the Commander ==> Skipping Repair Action and leaving this to the Commander Node ($Commander_Node). Exiting Normally..."
   exit_script 0
 fi
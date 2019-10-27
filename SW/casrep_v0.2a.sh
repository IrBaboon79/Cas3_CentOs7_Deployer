#!/usr/bin/env bash

script_version='v0.2a'
# configuration...
CASSANDRA_DIR="/cassandra"
JMX_REMOTE_PORT=8090
LOGDIR="/CassandraStorage/MaintenanceLog"
LOGFILE="$LOGDIR/repairlog.log"
MAX_LOG_SIZE=100M

DayName_array=(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)
DOW=$(date +%A) # get today's full name

function exit_script(){
echo "================================================< Done! exit code: $1 >==" | tee -a $LOGFILE
exit $1
}

clear
# wipe large logfile; note there is a seperate service that maintains the logfile as well so this is basically no longer needed...
if [ `find $LOGFILE -type f -size +$MAX_LOG_SIZE -delete | wc -l` -gt 1 ]; then
    LOGSTAT="Logfile $LOGFILE exceeded $MAX_LOG_SIZE - logfile was purged!"
    else  LOGSTAT="Logfile $LOGFILE below $MAX_LOG_SIZE threshold - leaving it alone for now..."
 fi
mkdir -p $LOGDIR > /dev/null
# create the logfolder and set first entry...

echo "Cassandra Node Maintenance bash Magic $script_version / RTi" | tee -a $LOGFILE
echo "==< Start >==============================================================" | tee -a $LOGFILE

echo "[`date +%Y-%m-%d:%H:%M:%S`] Starting Cassandra 3 Repair Script ..." | tee -a $LOGFILE
echo "[`date +%Y-%m-%d:%H:%M:%S`] $LOGSTAT"
echo "[`date +%Y-%m-%d:%H:%M:%S`] Logging to journal/stdout & Writing logfile to: $LOGFILE" 

# First figure out MY listening Address...

echo "[`date +%Y-%m-%d:%H:%M:%S`] Determining this node's listening address from /cassandra/conf/cassandra.yaml..." | tee -a $LOGFILE
Local_Listen_Address=$(cat $CASSANDRA_DIR/conf/cassandra.yaml | grep "listen_address:" | cut -d " " -f 2)

if [ -z $Local_Listen_Address ]; then  # failsafe, try the hostname if above fails...
       Local_Listen_Address=`hostname -i`   
     fi
     echo "[`date +%Y-%m-%d:%H:%M:%S`] Using Listen Address (from cassanda.yaml): $Local_Listen_Address ..." | tee -a $LOGFILE

# now see if we can reach it!

echo "[`date +%Y-%m-%d:%H:%M:%S`] Querying Node Status..."
# This SHOULD be properly sorted with the lowest number in position #0...
NodeStatusArray=($($CASSANDRA_DIR/bin/nodetool -h $Local_Listen_Address -p $JMX_REMOTE_PORT status 2> /dev/null | grep "UN " | sort | awk '{print $2}'))

echo "[`date +%Y-%m-%d:%H:%M:%S`] Nodes that Reported as Up/Normal..." | tee -a $LOGFILE
echo $NodeStatusArray | nl -n rn | tee -a $LOGFILE

# array empty OR failed to execute cassandra/nodetool?

if [ -z "$NodeStatusArray" ]; then #Array is empty, we exit hard here so we dont end up doing nonsense!
    echo "[`date +%Y-%m-%d:%H:%M:%S`] Cassandra Service seems down on Node ($Local_Listen_Address) or we received an unexpected response ==> Unable to perform action - Aborting!" | tee -a $LOGFILE
    exit 1
    else echo "[`date +%Y-%m-%d:%H:%M:%S`] Node $Local_Listen_Address also says hi... :)  - let's continue then..."
fi

Array_len=${#NodeStatusArray[@]} #get the length of the array

echo "[`date +%Y-%m-%d:%H:%M:%S`] Detected $Array_len nodes with UN (Up + Normal) status..." | tee -a $LOGFILE

for (( i=0; i<=$(( $Array_len -1 )); i++ ))
do
    #first get the mod 7 so we know the day a node should be triggered
    day=$(($i%7))
    echo -ne "\t\t      Node ${NodeStatusArray[$i]} would be scheduled on ${DayName_array[$day]}" | tee -a $LOGFILE
    
    if [[ "${DayName_array[$day]}" == "$DOW" ]]; then 
                                                      echo " ==> This node should be repaired today... Let's add it to the list of Repairees..." | tee -a $LOGFILE
                                                      Nodes_To_Repair_Today+=( ${NodeStatusArray[$i]} )
     else
        echo " ==> This should NOT be repaired today!" | tee -a $LOGFILE
     fi
done

if [ "$Array_len" -gt 0 ]; then # if there is more than 1 item to repair in the list, pick the first item as the Commander node.
   echo "[`date +%Y-%m-%d:%H:%M:%S`] Nodes due for Repair Today:" | tee -a $LOGFILE
   echo "$Nodes_To_Repair_Today" | nl -n rn | tee -a $LOGFILE
   
   echo "[`date +%Y-%m-%d:%H:%M:%S`] *ASSUMING* First Node as 'Commander': ${NodeStatusArray[0]} " | tee -a $LOGFILE
   Commander_Node=${NodeStatusArray[0]}

   else
      echo "[`date +%Y-%m-%d:%H:%M:%S`] - No Nodes due for Repair Today! Exiting..." | tee -a $LOGFILE
      exit_script 0
      
      
fi

# Now, figure out which node will be the one executing the repair command...
# 1) We'll assume the FIRST element of the nodes (as it's sorted) will be the one to execute the command and will issue it to anything in need of repair
# 2) Determine if this node is the commander
# 3) in case it's localhost we make an exception and take the commander role. (not fully implemented)

if [ "$Local_Listen_Address" = "$Commander_Node" -o  "$Local_Listen_Address" = "localhost" ] ; then
                                                     for Node in $Nodes_To_Repair_Today; do
 
						       echo "[`date +%Y-%m-%d:%H:%M:%S`] Current Machine is assumed to be the Commander - Proceeding to Repair Action..." | tee -a $LOGFILE
					   	       echo  "[`date +%Y-%m-%d:%H:%M:%S`] Starting nodetool -h $Node -p $JMX_REMOTE_PORT repair -pr" | tee -a $LOGFILE
						       echo  " ==> Executing repair against $Node: $CASSANDRA_DIR/bin/nodetool -h $Node -p $JMX_REMOTE_PORT repair -pr" | tee -a $LOGFILE
						       $CASSANDRA_DIR/bin/nodetool -h $Node -p $JMX_REMOTE_PORT repair -pr | tee -a $LOGFILE

					                if [ $? -ne 0 ]; then
							  	         echo "[`date +%Y-%m-%d:%H:%M:%S`]  Error while running the repair job on Node $Node !!" | tee -a $LOGFILE
							  	         exit_script 1
                                                                         
						         else
 								          echo "[`date +%Y-%m-%d:%H:%M:%S`] Finished nodetool -h $Node -p $JMX_REMOTE_PORT repair -pr" | tee -a $LOGFILE
 								          exit_script 0
						        fi
                                                     done
  else
   echo "[`date +%Y-%m-%d:%H:%M:%S`] Current Machine is NOT the Commander ==> Skipping Repair Action and leaving this to the Commander Node ($Commander_Node) ..." | tee -a $LOGFILE
   exit_script 0
 fi
 

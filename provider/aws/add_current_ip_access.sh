#!/bin/bash

# define starting dir
starting_dir=`pwd`
echo $starting_dir

###########################################################################################################
# import parameters and utility functions 
###########################################################################################################
#. $starting_dir/provider/aws/demo.properties
. $starting_dir/provider/aws/prereq_utils.sh
. $starting_dir/provider/aws/.info


# function for logging
log() {
    echo "[$(date)]: $*"
}
# set your current ip address
current_ip=`curl -s ipinfo.io/ip`

log "Adding IP --> " ${current_ip:?}
add_ip_access_rule ${current_ip:?}

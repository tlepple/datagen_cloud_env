#!/bin/bash

# define starting dir
starting_dir=`pwd`
echo ${starting_dir}

###########################################################################################################
# import parameters and utility functions 
###########################################################################################################
#. ${starting_dir}/provider/aws/demo.properties
. ${starting_dir}/provider/aws/prereq_utils.sh
. ${starting_dir}/provider/aws/.info


# function for logging
log() {
    echo "[$(date)]: $*"
    echo "[$(date)]: $*" >> terminate.log
}

#delete the instance(s)
terminate_all_ec2 

#archive .info file
archive_info_file

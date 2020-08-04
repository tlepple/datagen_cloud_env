#!/bin/bash

#########################################################
# Input parameters
#########################################################

case "$1" in
        aws)
           echo "you chose aws"
            ;;
        azure)
           echo "you chose azure"
            ;;
        gcp)
	   echo "you chose gcp"
            ;;
        *)
            echo $"Usage: $0 {aws|azure|gcp} template-file [docker-device]"
            echo $"example: ./setup.sh azure default_template.json"
            echo $"example: ./setup.sh aws cdsw_template.json /dev/xvdb"
            exit 0
esac

CLOUD_PROVIDER=$1

#########################################################
# utility functions
#########################################################
dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

starting_dir=`pwd`
#echo "starting_dir=${starting_dir:?}" >> $starting_dir/provider/aws/.info

# log the CLOUD_PROVIDER
#echo "CLOUD_PROVIDER=${CLOUD_PROVIDER:?}" >> $starting_dir/provider/aws/.info

# logging function
log() {
    echo -e "[$(date)] [$BASH_SOURCE: $BASH_LINENO] : $*"
    echo -e "[$(date)] [$BASH_SOURCE: $BASH_LINENO] : $*" >> $starting_dir/setup-all.log
}
# Load util functions.
#. $starting_dir/bin/utils.sh


#####################################################
#
#####################################################

case "$CLOUD_PROVIDER" in
        aws)
            echo "execute aws code here... "
	    . /app/colab-cdpdc-wwbank/provider/aws/aws_setup.sh
            ;;
        azure)
           echo "execute azure code here"
            . /app/colab-cdpdc-wwbank/provider/azure/azure_setup.sh
            ;;
        gcp)
           echo "execute gcp code here"
            ;;
        *)
            echo "you had a different choice... is this block needed?"
	    ;;
esac



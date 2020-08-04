#!/bin/bash

###########################################################################################################
# Define Functions:
###########################################################################################################

#####################################################
# Functions: create AWS prereqs (VPC, subnets, security group, db subnet)
#####################################################

create_prereqs() {
  if [ -s $starting_dir/provider/aws/.info ]; then
    log "Looks like you have not propertly terminated the previous environment, as there are still entries in .info. Execute first terminate.sh and rerun. Exiting..."
    exit 1
  fi

  #####################################################
  # record main info for the cluster
  #####################################################
  # starting_dir
  echo "AWS_REGION=${AWS_REGION:?}" > $starting_dir/provider/aws/.info
  echo "OWNER_TAG=${OWNER_TAG:?}" >> $starting_dir/provider/aws/.info
  echo "starting_dir=${starting_dir:?}" >> $starting_dir/provider/aws/.info
  echo "CLOUD_PROVIDER=${CLOUD_PROVIDER:?}" >> $starting_dir/provider/aws/.info
  #####################################################
  # create VPC
  #####################################################
  if [ "${MY_VPC}" = "" ]; then
    vpc_id=`aws --output json --region ${AWS_REGION:?} ec2 create-vpc --cidr-block 10.0.0.0/16 | jq -r ".Vpc.VpcId"`
    if [ "${vpc_id}" = "" ]; then
      log "VPC could not be created. Most likely the limit has beeen exceeded. Please pick a different region, or use an existing VPC by setting 'export MY_VPC=...' and rerun the script. Exiting..."
      exit 1
    fi
    echo "existingVpc=false" >> $starting_dir/provider/aws/.info
    aws --region ${AWS_REGION:?} ec2 create-tags --resources ${vpc_id:?} --tags Key=owner,Value=${OWNER_TAG:?} Key=Name,Value=${OWNER_TAG:?}-vpc
    log "New VPC in ${AWS_REGION:?} created: ${OWNER_TAG:?}-vpc, ${vpc_id:?}"
  else
    vpc_id="${MY_VPC}"
    echo "existingVpc=true" >> $starting_dir/provider/aws/.info
    log "Existing VPC in ${AWS_REGION:?} used: ${vpc_id:?}"
  fi
  echo "vpc_id=${vpc_id:?}" >> $starting_dir/provider/aws/.info
  aws --region ${AWS_REGION:?} ec2 modify-vpc-attribute --enable-dns-hostnames --vpc-id ${vpc_id:?}
 
  ##################################################### 
  # create public subnets
  #####################################################
  subnet_id=`aws --output json --region ${AWS_REGION:?} ec2 create-subnet --availability-zone ${AWS_REGION:?}a --vpc-id ${vpc_id:?} --cidr-block 10.0.8.0/24 | jq -r ".Subnet.SubnetId"`
  echo "subnet_id=${subnet_id:?}" >> $starting_dir/provider/aws/.info
  log "New Subnet in ${AWS_REGION:?}a created: ${OWNER_TAG:?}-subnet, ${subnet_id:?}"
  aws --region ${AWS_REGION:?} ec2 create-tags --resources ${subnet_id:?} --tags Key=owner,Value=${OWNER_TAG:?} Key=Name,Value=${OWNER_TAG:?}-subnet
 
  ##################################################### 
  # create/get internet gateway
  #####################################################
  igw=`aws --region ${AWS_REGION:?} ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=${vpc_id:?} | jq -r ".InternetGateways[0].InternetGatewayId"`
  if [ "$igw" == "null" ]; then
    igw=`aws --output json --region ${AWS_REGION:?} ec2 create-internet-gateway | jq -r ".InternetGateway.InternetGatewayId"`
    aws --region ${AWS_REGION:?} ec2 attach-internet-gateway --vpc-id ${vpc_id:?} --internet-gateway-id ${igw}
    aws --region ${AWS_REGION:?} ec2 create-tags --resources ${igw:?} --tags Key=owner,Value=${OWNER_TAG:?} Key=Name,Value=${OWNER_TAG:?}-internet-gw
  fi
  echo "igw=${igw:?}" >> $starting_dir/provider/aws/.info
  log "Internet gateway used: ${igw:?}"


  ##################################################### 
  # create elastic IP
  #####################################################  

  eip_id=`aws --region ${AWS_REGION:?} ec2 allocate-address --domain vpc | jq -r ".AllocationId"`
  echo "eip_id=${eip_id:?}" >> $starting_dir/provider/aws/.info
  aws --region ${AWS_REGION:?} ec2 create-tags --resources ${eip_id:?} --tags Key=owner,Value=${OWNER_TAG:?} Key=Name,Value=${OWNER_TAG:?}-eip
  eip_public_ip=`aws ec2 describe-addresses --allocation-ids ${eip_id:?} | jq -r ".Addresses[0].PublicIp"`
  echo "eip_public_ip=${eip_public_ip:?}" >> $starting_dir/provider/aws/.info
 
  ##################################################### 
  # create route table
  #####################################################
  rtb=`aws --output json --region ${AWS_REGION:?} ec2 create-route-table --vpc-id ${vpc_id:?} | jq -r ".RouteTable.RouteTableId"`
  aws --region ${AWS_REGION:?} ec2 create-route --route-table-id ${rtb:?} --destination-cidr-block 0.0.0.0/0 --gateway-id ${igw:?}
  aws --region ${AWS_REGION:?} ec2 associate-route-table  --subnet-id ${subnet_id:?} --route-table-id ${rtb:?}
  aws --region ${AWS_REGION:?} ec2 create-tags --resources ${rtb:?} --tags Key=owner,Value=${OWNER_TAG:?} Key=Name,Value=${OWNER_TAG:?}-route-table
  echo "rtb=${rtb:?}" >> $starting_dir/provider/aws/.info
  log "Route table used: ${rtb:?}"
 
  ##################################################### 
  # create PEM file
  #####################################################
  aws --region ${AWS_REGION:?} ec2 create-key-pair --key-name ${OWNER_TAG:?}-key-file --query 'KeyMaterial' --output text > $starting_dir/provider/aws/${OWNER_TAG:?}-key-file.pem
  chmod 400  $starting_dir/provider/aws/${OWNER_TAG:?}-key-file.pem
  echo "KEY_FILENAME=${OWNER_TAG:?}-key-file" >> $starting_dir/provider/aws/.info
  echo "KEY_FILE_PATH=${starting_dir}/provider/aws/" >> $starting_dir/provider/aws/.info
  export KEY_FILENAME=${OWNER_TAG:?}-key-file
  export KEY_FILE_PATH=${starting_dir}/provider/aws/

  #####################################################
  # create Security Group
  #####################################################
  #####################################################
  # create Security Group
  #####################################################
  sg=`aws --output json --region ${AWS_REGION:?} ec2 create-security-group --group-name ${OWNER_TAG:?}-security-group --description "Security group" --vpc-id ${vpc_id:?} | jq -r ".GroupId"`
  aws --region ${AWS_REGION:?} ec2 authorize-security-group-ingress --group-id ${sg:?} --protocol all --port 0-65535 --source-group ${sg:?}
  #  need to add a port 22 access here...
  #  this next one might need to be removed...  its sets the ip allowed to the public ip address of the host running this code.  (jumpbox).
  # orig version
  aws --region ${AWS_REGION:?} ec2 authorize-security-group-ingress --group-id ${sg:?} --protocol tcp --port 0-65535 --cidr `curl -s ipinfo.io/ip`/32
  # added this to map to my home ip address and not the jumpbox server
  #aws --region ${AWS_REGION:?} ec2 authorize-security-group-ingress --group-id ${sg:?} --protocol all --port 0-65535 --cidr ${MY_HOME_IP:?}
  # add the elastic ip address public IP
  aws --region ${AWS_REGION:?} ec2 authorize-security-group-ingress --group-id ${sg:?} --protocol tcp --port 0-65535 --cidr ${eip_public_ip:?}/32
  
  aws --region ${AWS_REGION:?} ec2 create-tags --resources ${sg:?} --tags Key=owner,Value=${OWNER_TAG:?} Key=Name,Value=${OWNER_TAG:?}-security-group
  echo "sg=${sg:?}" >> $starting_dir/provider/aws/.info
  log "New Security Group in ${AWS_REGION:?} created: ${OWNER_TAG:?}-security-group, ${sg:?}"

  
}

#####################################################
# Function: delete all the prereqs created for the demo
#####################################################
terminate_prereqs() {
  log "Deleting security group ${sg}..."
  aws --region ${AWS_REGION:?} ec2 delete-security-group --group-id ${sg}
  log "Deleting subnet ${subnet_id}..."
  aws --region ${AWS_REGION:?} ec2 delete-subnet --subnet-id ${subnet_id}
  log "Deleting route table ${rtb}..."
  aws --region ${AWS_REGION} ec2 delete-route-table --route-table-id ${rtb}
  if [ "$existingVpc" = "false" ]; then
    log "Detaching internet gateway from VPC..."
    aws --region ${AWS_REGION:?} ec2 detach-internet-gateway --vpc-id ${vpc_id} --internet-gateway-id ${igw}
    log "Deleting internet gateway ${igw}..."
    aws --region ${AWS_REGION:?} ec2 delete-internet-gateway --internet-gateway-id ${igw}
    log "Deleting VPC ${vpc_id}..."
    aws --region ${AWS_REGION:?} ec2 delete-vpc --vpc-id ${vpc_id}
  else
    log "Skipping existing internet gateway and VPC..."
  fi
  log "Deleting key ${OWNER_TAG:?}-key-file..."
  aws --region ${AWS_REGION:?} ec2 delete-key-pair --key-name ${KEY_FILENAME:?}
  log "Deleting elastic ip --> ${eip_id:?}"
  aws --region ${AWS_REGION:?} ec2 release-address --allocation-id ${eip_id:?}
  mv -f $starting_dir/provider/aws/${KEY_FILENAME:?}.pem $starting_dir/provider/aws/.${KEY_FILENAME:?}.pem.old.$(date +%s)
  mv -f $starting_dir/provider/aws/.info $starting_dir/provider/aws/.info.old.$(date +%s)
   export U=`whoami`
#  rm -f ${BIND_MNT_TARGET:?}/${BIND_FILENAME:?}.pem
 rm -f /${U}${BIND_MNT_TARGET}${BIND_FILENAME}
#  rm -f /${U}${BIND_MNT_TARGET:?}/${BIND_FILENAME:?}.pem
  touch $starting_dir/provider/aws/.info
  cd $starting_dir
}

#####################################################
# Function terminate ec2 instances
#####################################################
terminate_all_ec2() {
  log "Terminating all ec2 instances"
  terminate_id=`aws --output json --region ${AWS_REGION:?} ec2 describe-instances --filters "Name=tag:Name,Values=${HOST_PREFIX}${OWNER_TAG:?}" | jq -r ".Reservations[].Instances[].InstanceId"`
  log "The following instances will be deleted:" $terminate_id
  if [ -z $terminate_id ]; then
    log "No instances found. Skipping."
  else
    for i in $terminate_id; do
        status=`aws --output json --region ${AWS_REGION:?} ec2 terminate-instances --instance-ids $i | jq -r ".TerminatingInstances[0].CurrentState.Name"`
        log "Status: $status"
        log 'Waiting for instances to terminate'
        sleep 10s
        aws --region ${AWS_REGION:?} ec2 wait instance-terminated --instance-ids $i
        log "Instance $i terminated"
    done
  fi
}

#####################################################
# Function to archive .info (needed for terminate of ec2)
#####################################################

archive_info_file () {
    mv -f ${starting_dir}/provider/aws/${KEY_FILENAME:?}.pem ${starting_dir}/provider/aws/.${KEY_FILENAME:?}.pem.old.$(date +%s)
    mv -f ${starting_dir}/provider/aws/.info ${starting_dir}/provider/aws/.info.old.$(date +%s)
    touch ${starting_dir}/provider/aws/.info
    cd ${starting_dir}
}









#####################################################
# Function to install aws cli
#####################################################

install_aws_cli() {

	#########################################################
	# BEGIN
	#########################################################
	log "BEGIN setup.sh"

	unameOut="$(uname -s)"
	case "${unameOut}" in
	  Linux*)     machine=Linux;;
	  Darwin*)    machine=Mac;;
	  CYGWIN*)    machine=Cygwin;;
	  MINGW*)     machine=MinGw;;
	  *)          machine="UNKNOWN:${unameOut}"
	esac
	log "Current machine is: $machine"

	#####################################################
	# first check if JQ is installed
	#####################################################
	log "Installing jq"

	jq_v=`jq --version 2>&1`
	if [[ $jq_v = *"command not found"* ]]; then
	  if [[$machine = "Mac" ]]; then
	    curl -L -s -o jq "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-osx-amd64"
	  else
	    curl -L -s -o jq "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64"
	  fi 
	  chmod +x ./jq
	  cp jq /usr/bin
	else
	  log "jq already installed. Skipping"
	fi

	jq_v=`jq --version 2>&1`
	if [[ $jq_v = *"command not found"* ]]; then
	  log "error installing jq. Please see README and install manually"
	  echo "Error installing jq. Please see README and install manually"
	  exit 1 
	fi  

	####################################################
 	# then install AWS CLI
	#####################################################
  	log "Installing AWS_CLI"
  	aws_cli_version=`aws --version 2>&1`
  	log "Current CLI version: $aws_cli_version"
  	if [[ $aws_cli_version = *"aws-cli"* ]]; then
    		log "AWS CLI already installed. Skipping"
    		return
  	fi
  	if [ $machine = 'Linux' ]; then
    		yum -y install unzip
  	fi  
  		curl -s -O "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip"
  		unzip awscli-bundle.zip
  		./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws 
  		rm -rf awscli-bundle*
  	log "Done installing AWS CLI"

}

#####################################################
# Function to create instance
#####################################################
create_onenode_instance() {
	log "Create oneNode ec2 instance"
	oneNodeInstanceId=`aws --output json --region ${AWS_REGION:?} ec2 run-instances --image-id ${AMI_ID:?} --key-name ${KEY_FILENAME:?} --security-group-ids ${sg:?} --instance-type ${ONE_NODE_INSTANCE:?} --subnet-id ${subnet_id:?} --associate-public-ip-address --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"DeleteOnTermination":true,"VolumeSize":20,"VolumeType":"gp2","Encrypted":false}},{"DeviceName":"/dev/sdc","Ebs":{"DeleteOnTermination":true,"VolumeSize":10,"VolumeType":"gp2","Encrypted":false}}]' | jq -r ".Instances[0].InstanceId"`

	log "Instance ID: ${oneNodeInstanceId:?}"
	aws --region ${AWS_REGION:?} ec2 create-tags --resources ${oneNodeInstanceId:?} --tags Key=owner,Value=${OWNER_TAG:?} Key=Name,Value=${HOST_PREFIX}${OWNER_TAG:?} Key=enddate,Value=${ENDATE_TAG:?} Key=project,Value='personal development'
	echo "oneNodeInstanceId=${oneNodeInstanceId:?}" >> $starting_dir/provider/aws/.info
}

#####################################################
# Function to associate elastic ip to ec2 instance
#####################################################
associate_eip_2_instance() {
    log "Associate Elastic IP to an instance"
    AssociationID=`aws --output json --region ${AWS_REGION:?} ec2 associate-address --allocation-id ${eip_id:?} --instance-id ${oneNodeInstanceId:?}  | jq -r ".AssociationId"`
    log "ElasticIP AssociationID: --> ${AssociationID:?}"
    echo "AssociationID=${AssociationID:?}" >> $starting_dir/provider/aws/.info
}

#####################################################
# Function to check ec2 instance is ready
#####################################################
check_ec2(){
  log "Checking EC2 Status"
  sleep 60s
  stage=`aws --output json --region ${AWS_REGION:?} ec2 describe-instance-status --instance-ids $1 | jq -r ".InstanceStatuses[0].InstanceStatus.Status"`

  while [ "$stage" == 'initializing' ]
  do
    log "EC2 status: $stage"
    log "sleeping for 20s"
    sleep 20
    stage=`aws --output json --region ${AWS_REGION:?} ec2 describe-instance-status --instance-ids $1 | jq -r ".InstanceStatuses[0].InstanceStatus.Status"`
   
  done
  log "EC2 status: $stage"
  if [ "$stage" != 'ok' ]
  then
    log "EC2 instance not in 'OK' status. Please check the EC2 console. Exiting..."
    exit 1
  fi
  log "ec2 instance ready"

  # we grab the director IP and FQDN from AWS
#  ONENODE_PUBLIC_IP=`aws --output json --region ${AWS_REGION:?} ec2 describe-instances --instance-ids $1 | jq -r ".Reservations[0].Instances[0].PublicIpAddress"`
  ONENODE_PRIVATE_IP=`aws --output json --region ${AWS_REGION:?} ec2 describe-instances --instance-ids $1 | jq -r ".Reservations[0].Instances[0].PrivateIpAddress"`
  ONENODE_FQDN_PRIVATE=`aws --output json --region ${AWS_REGION:?} ec2 describe-instances --instance-ids $1 | jq -r ".Reservations[0].Instances[0].PrivateDnsName"`
#  echo "ONENODE_PUBLIC_IP=${ONENODE_PUBLIC_IP:?}" >> $starting_dir/provider/aws/.info
  echo "ONENODE_PRIVATE_IP=${ONENODE_PRIVATE_IP:?}" >> $starting_dir/provider/aws/.info
  echo "ONENODE_FQDN_PRIVATE=${ONENODE_FQDN_PRIVATE:?}" >> $starting_dir/provider/aws/.info
  log "oneNode privateIP: $ONENODE_PRIVATE_IP, privateFQDN: $ONENODE_FQDN_PRIVATE"

}

#####################################################
# Function to copy key file to a bind mount
#####################################################
replicate_key() {

    # build a unique filename for this pem key
	BIND_FILENAME=${OWNER_TAG}-${AWS_REGION}-${oneNodeInstanceId}-${ONENODE_PRIVATE_IP}.pem
        echo "BIND_FILENAME=${BIND_FILENAME:?}" >> $starting_dir/provider/aws/.info
	echo "file to copy is --> " ${KEY_FILE_PATH}${KEY_FILENAME}.pem
#	echo " here is current string --> " ${KEY_FILE_PATH}${KEY_FILENAME}.pem ${BIND_MNT_TARGET}${BIND_FILENAME}
#	echo "listing file contents ..."
#	ls ${KEY_FILE_PATH}
	export U=`whoami`
#	cp ${KEY_FILE_PATH}${KEY_FILENAME}.pem ${BIND_MNT_TARGET}${BIND_FILENAME}
	cp ${KEY_FILE_PATH}${KEY_FILENAME}.pem /${U}${BIND_MNT_TARGET}${BIND_FILENAME}
}

#####################################################
# Function to add network access
#####################################################
add_ip_access_rule () {
	arg_ip_in=$1
	
	# add the IP address to the security group for access
	aws --region ${AWS_REGION:?} ec2 authorize-security-group-ingress --group-id ${sg:?} --protocol tcp --port 0-65535 --cidr ${arg_ip_in:?}/32

	log "added rule for IP --> ${arg_ip_in:?}"

}

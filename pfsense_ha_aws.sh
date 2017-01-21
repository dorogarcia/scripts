#!/bin/bash
#
# https://doro.es/configurar-pfsense-con-high-availability-en-una-vpc-de-amazon-aws/
#
# dg \4t doro.es
#   2017.01.21
#
# This script is a Proof of Concept for pfSense HA in AWS.
# It will monitor pfSense nodes and will take over public and private IPs.
#
# If a node response pings, script never will reassign resources!
# Feel free if you want implement extended checks
#

PFSENSE1_IP=10.1X.XX.XX1
PFSENSE2_IP=10.1X.XX.XX2
PFSENSE_VIP1=10.1X.XX.XX0

PFSENSE_EIP=X.X.X.X

REGION=eu-west-1

CLUSTER_RETRY_CONF=3
SLEEP_TIME_BWR=1

# Log prefix
function log_date() {
	echo `date +%Y.%m.%d_%H:%M:%S: `
}

function checks() {
	# Check ping to pfSense 1
	PING_PFSENSE1=`ping -c 3 -W 3 ${PFSENSE1_IP} >/dev/null 2>/dev/null && echo 0 || echo 1`
	# Check ping to pfSense 2
	PING_PFSENSE2=`ping -c 3 -W 3 ${PFSENSE2_IP} >/dev/null 2>/dev/null && echo 0 || echo 1`
	# Check ping to VIP
	PING_VIP=`ping -c 3 -W 3 ${PFSENSE_VIP1} >/dev/null 2>/dev/null && echo 0 || echo 1`
	# Get instance_id where EIP is assigned
	EIP_INSTANCE=`aws ec2 describe-instances --region ${REGION} --query 'Reservations[].Instances[].[InstanceId]' --filters "Name=ip-address,Values=${PFSENSE_EIP}"`
	# Get instance_id where VIP1 is assigned
	VIP_INSTANCE=`aws ec2 describe-instances --region ${REGION} --query 'Reservations[].Instances[].[InstanceId]' --filters "Name=network-interface.addresses.private-ip-address,Values=${PFSENSE_VIP1}"`
	# Get Primary IP of instance where VIP is assgined
	VIP_INSTANCE_IP=`aws ec2 describe-instances --region ${REGION} --query 'Reservations[].Instances[].[PrivateIpAddress]' --filters "Name=network-interface.addresses.private-ip-address,Values=${PFSENSE_VIP1}"`
	# Check ping to VIP
	PING_VIP_INSTANCE=`ping -c 3 -W 3 ${VIP_INSTANCE_IP} >/dev/null 2>/dev/null && echo 0 || echo 1`
}

# Check status of both instances and conectivity
function cluster_status() {
	checks
	if [ ${PING_PFSENSE1} -eq 0 ] && [ ${PING_PFSENSE2} -eq 0 ] && [ ${PING_VIP} -eq 0 ] && [ ${PING_VIP_INSTANCE} -eq 0 ] && [ ${EIP_INSTANCE} == ${VIP_INSTANCE} ]; then
		echo "`log_date` Cluster: OK - Both pfSense and VIP active instance are responding to ping, VIP and EIP are assigned in the same instance: ${VIP_INSTANCE}"
		STATUS=OK
		exit 0
		else
			echo "`log_date` Cluster: ERROR - PING_PFSENSE1: ${PING_PFSENSE1}, PING_PFSENSE2: ${PING_PFSENSE2}, PING_VIP: ${PING_VIP}, PING_VIP_INSTANCE: ${PING_VIP_INSTANCE}, EIP_INSTANCE: ${EIP_INSTANCE}, VIP_INSTANCE: ${VIP_INSTANCE}"
			STATUS=ERROR
			exit 2
	fi
}

# Check if VIP and EIP are working
function service_status() {
	checks
        if [ ${PING_VIP_INSTANCE} -eq 0 ] && [ ${EIP_INSTANCE} == ${VIP_INSTANCE} ]; then
                echo "`log_date` Service: OK - VIP active instance is responding to ping, VIP and EIP are assigned in the same instance: ${VIP_INSTANCE}"
                STATUS=OK
                else
                        echo "`log_date` Service: ERROR - PING_PFSENSE1: ${PING_PFSENSE1}, PING_PFSENSE2: ${PING_PFSENSE2}, PING_VIP: ${PING_VIP}, PING_VIP_INSTANCE: ${PING_VIP_INSTANCE}, EIP_INSTANCE: ${EIP_INSTANCE}, VIP_INSTANCE: ${VIP_INSTANCE}"
                        STATUS=ERROR
        fi
}

# If something fails, here will try to configure pfSense HA 1 or pfSense HA 2
function configure_cluster() {
        # If something is wrong we try configure pfSense 1 as master if it is alive.
        if [ ${PING_PFSENSE1} -eq 0 ]; then
                echo "`log_date` Moving VIP and EIP to pfSense 1: ${PFSENSE1_IP}"
                ENI_ID=`aws ec2 describe-instances --region ${REGION} --filters --query 'Reservations[].Instances[].NetworkInterfaces[].[NetworkInterfaceId]' "Name=private-ip-address,Values=${PFSENSE1_IP}"`
                INSTANCE_ID=`aws ec2 describe-instances --region ${REGION} --filters --query 'Reservations[].Instances[].[InstanceId]' "Name=private-ip-address,Values=${PFSENSE1_IP}"`
                ALLOCATION_ID=`aws ec2 describe-addresses|grep ${PFSENSE_EIP}|awk '{ print $2 }'`
		# Configure Virtual IP
                aws ec2 assign-private-ip-addresses --network-interface-id ${ENI_ID} --private-ip-address ${PFSENSE_VIP1} --allow-reassignment
		# Configure Elastic IP
                aws ec2 associate-address --instance-id ${INSTANCE_ID} --allocation-id ${ALLOCATION_ID} --allow-reassociation >/dev/null
        # If something is wrong we try configure pfSense 2 as master if it is alive, after try to configure in pfSense HA 1
        elif [ ${PING_PFSENSE2} -eq 0 ]; then
		echo "`log_date` Moving VIP and EIP to pfSense 2: ${PFSENSE2_IP}"
                ENI_ID=`aws ec2 describe-instances --region ${REGION} --filters --query 'Reservations[].Instances[].NetworkInterfaces[].[NetworkInterfaceId]' "Name=private-ip-address,Values=${PFSENSE2_IP}"`
                INSTANCE_ID=`aws ec2 describe-instances --region ${REGION} --filters --query 'Reservations[].Instances[].[InstanceId]' "Name=private-ip-address,Values=${PFSENSE2_IP}"`
                ALLOCATION_ID=`aws ec2 describe-addresses|grep ${PFSENSE_EIP}|awk '{ print $2 }'`
		# Configure Virtual IP
                aws ec2 assign-private-ip-addresses --network-interface-id ${ENI_ID} --private-ip-address ${PFSENSE_VIP1} --allow-reassignment
		# Configure Elastic IP
		aws ec2 associate-address --instance-id ${INSTANCE_ID} --allocation-id ${ALLOCATION_ID} --allow-reassociation >/dev/null
	# If both instances fail, we are down!
        else
                echo "`log_date` FATAL ERROR - Both nodes are down :("
                exit 2
	fi
}

echo " "
echo "`log_date` ...:: Checking pfSense cluster ::..."
service_status

# If status return ERROR, we try to configure pfSense cluster
if [ "${STATUS}" == "ERROR" ]; then
	# Try to configure cluster
	for try in `seq 1 ${CLUSTER_RETRY_CONF}`; do
		echo `log_date` Trying to configure cluster: $try
		configure_cluster
		sleep ${SLEEP_TIME_BWR}
		service_status
		if [ "${STATUS}" == "OK" ]; then
			echo `log_date` Cluster is configured
			exit 0
		fi
	done

	echo "`log_date` Cluster is dead :("
fi

cluster_status

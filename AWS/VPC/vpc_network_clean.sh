#!/bin/bash

# Alles löschen ###############################################################################################
echo "deleting key pairs"
aws ec2 delete-key-pair --key-name python_key
aws ec2 delete-key-pair --key-name database_key
rm python_key
rm database_key
rm python_key.pem
rm database_key.pem


# Finden von X und löschen aller nach Reihenfolge



echo "deleting ec2s"
aws ec2 terminate-instances --instance-ids $python_instance_id
aws ec2 terminate-instances --instance-ids $database_instance_id

echo "waiting for shutdown of ec2 instances"
sleep 120

echo "deleting security groups"
aws ec2 delete-security-group --group-id $sg_database_id
aws ec2 delete-security-group --group-id $sg_python_id


echo "deleting nat gateway"
aws ec2 delete-nat-gateway --nat-gateway-id $ngw_id > /dev/null


echo "deleting elastic ip"
aws ec2 disassociate-address --association-id $association_public_id
aws ec2 release-address --allocation-id $allocation_id


echo "deleting route table for public subnet"
aws ec2 disassociate-route-table --association-id $association_public_id
aws ec2 delete-route-table --route-table-id $rtb_public_id


echo "deleting route table for private subnet"
aws ec2 disassociate-route-table --association-id $association_private_id
aws ec2 delete-route-table --route-table-id $rtb_private_id



echo "detach and deleting igw..."

aws ec2 detach-internet-gateway --internet-gateway-id $igw_id --vpc-id $vpc_id
aws ec2 delete-internet-gateway --internet-gateway-id $igw_id

echo "waiting for deleting the network interface, 2min"
sleep 120

echo "deleting subnets..."
aws ec2 delete-subnet --subnet-id $public_subnet_id
aws ec2 delete-subnet --subnet-id $private_subnet_id


echo "deleting vpc..."
aws ec2 delete-vpc --vpc-id $vpc_id

echo "done..."

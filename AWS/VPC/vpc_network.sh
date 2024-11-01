#!/bin/bash

ami_id="ami-04dd23e62ed049936"


# VPC erstellen #############################################################################################

echo "creating vpc..."
vpc_id=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 | jq -r '.Vpc.VpcId')
echo ">>> VPC ID: $vpc_id"

# Subnets erstellen #########################################################################################

echo "creating public subnet"
public_subnet_id=$(aws ec2 create-subnet --vpc-id "$vpc_id" --cidr-block 10.0.5.0/24 --availability-zone us-west-2a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=public_subnet}]' | jq -r '.Subnet.SubnetId')
echo ">>> Public Subnet ID: $public_subnet_id"

echo "creating private subnet"
private_subnet_id=$(aws ec2 create-subnet --vpc-id "$vpc_id" --cidr-block 10.0.10.0/24 --availability-zone us-west-2a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=public_subnet}]' | jq -r '.Subnet.SubnetId')
echo ">>> Private Subnet ID: $private_subnet_id"

# Internet Gateway erstellen #################################################################################

echo "creating internet gateway"
igw_id=$(aws ec2 create-internet-gateway | jq -r ".InternetGateway.InternetGatewayId")

echo ">>> Internet Gateway ID: $igw_id"

echo "attach Internet Gateway to VPC"
aws ec2 attach-internet-gateway --vpc-id $vpc_id --internet-gateway-id $igw_id


# Route Table erstellen und verbinden #########################################################################

echo "creating route table for public subnet"
rtb_public_id=$(aws ec2 create-route-table --vpc-id $vpc_id | jq -r ".RouteTable.RouteTableId")
echo ">>> Route Table ID: $rtb_public_id"

echo "creating route for Internet"
aws ec2 create-route --route-table-id $rtb_public_id --destination-cidr-block 0.0.0.0/0 --gateway-id $igw_id > /dev/null

echo "associate route table with public subnet"
association_public_id=$(aws ec2 associate-route-table --subnet-id $public_subnet_id --route-table-id $rtb_public_id | jq -r ".AssociationId")
echo ">>> Association ID: $association_public_id"

# Nat Gateway erstellen #######################################################################################

echo "creating elastic ip for Nat Gateway"
allocation_id=$(aws ec2 allocate-address | jq -r ".AllocationId")
echo ">>> Allocation ID: $allocation_id"

# Route Table für Private Subnet erstellen und Nate Gateway hinzufügen ########################################

echo "creating Nat Gateway"
ngw_id=$(aws ec2 create-nat-gateway --subnet-id $public_subnet_id --allocation-id $allocation_id | jq -r ".NatGateway.NatGatewayId")
echo ">>> Nat Gateway ID: $ngw_id"

echo "waiting 1min for creating the Nat Gateway..."
sleep 60


echo "creating route table for private subnet"
rtb_private_id=$(aws ec2 create-route-table --vpc-id $vpc_id | jq -r ".RouteTable.RouteTableId")
echo ">>> Route Table ID: $rtb_private_id"

echo "creating route for private nat gateway"
aws ec2 create-route --route-table-id $rtb_private_id --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $ngw_id > /dev/null


echo "associate route table with private subnet"
association_private_id=$(aws ec2 associate-route-table --subnet-id $private_subnet_id --route-table-id $rtb_private_id | jq -r ".AssociationId")
echo ">>> Association ID: $association_private_id"



# Alles löschen ###############################################################################################


echo "deleting nat gateway"
aws ec2 delete-nat-gateway --nat-gateway-id $ngw_id > /dev/null


echo "deleting elastic ip"
#aws ec2 disassociate-address --association-id $association_id
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

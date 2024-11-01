#!/bin/bash

ubuntu_ami_id="ami-04dd23e62ed049936"
linux_ami_id="ami-07c5ecd8498c59db5"

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


# Security Group erstellen #####################################################################################

echo "creating secutity group for python"
sg_python_id=$(aws ec2 create-security-group --group-name PythonSG --description "Security group for Python EC2" --vpc-id $vpc_id | jq -r ".GroupId")
echo ">>> Security Group ID: $sg_python_id"

echo "creating secutity group for database"
sg_database_id=$(aws ec2 create-security-group --group-name DatabaseSG --description "Security group for MySql Database EC2" --vpc-id $vpc_id | jq -r ".GroupId")
echo ">>> Security Group ID: $sg_database_id"

echo "allow port 22 for SSH"
aws ec2 authorize-security-group-ingress --group-id $sg_python_id --protocol tcp --port 22 --cidr 0.0.0.0/0 > /dev/null

echo "allow connection for python over port 3306"
aws ec2 authorize-security-group-ingress --group-id $sg_database_id --protocol tcp --port 3306 --source-group $sg_python_id > /dev/null


# Ec2 Instanzen erstellen #####################################################################################

echo "creating ssh keys"
aws ec2 create-key-pair --key-name python_key --key-type rsa --key-format pem --output text > python_key.pem
aws ec2 create-key-pair --key-name database_key --key-type rsa --key-format pem --output text > database_key.pem

echo "creating python instance with amazon linux"
python_instance_id=$(aws ec2 run-instances --image-id $linux_ami_id --instance-type t2.micro --key-name python_key --subnet-id $public_subnet_id --security-group-ids $sg_python_id --user-data $(base64 -w 0 user_data_python.sh) --associate-public-ip-address | jq -r ".Instances[0].InstanceId")
echo ">>> Python Instance ID: $python_instance_id"

echo "creating database instance with ubuntu"
database_instance_id=$(aws ec2 run-instances --image-id $ubuntu_ami_id --instance-type t2.micro --key-name database_key --subnet-id $private_subnet_id --security-group-ids $sg_database_id --user-data $(base64 -w 0 user_data_database.sh) | jq -r ".Instances[0].InstanceId")
echo ">>> Database Instance ID: $database_instance_id"

echo "wait 5min for initialising EC2s"
sleep 300


# Alles löschen ###############################################################################################
echo "deleting key pairs"
aws ec2 delete-key-pair --key-name python_key
aws ec2 delete-key-pair --key-name database_key
rm python_key
rm database_key
rm python_key.pem
rm database_key.pem


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

#!/bin/bash

ami_id="ami-04dd23e62ed049936"


# VPC erstellen 
echo "creating vpc..."
vpc_id=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 | jq -r '.Vpc.VpcId')

echo "VPC ID: $vpc_id"

# Subnets erstellen

echo "creating public subnet"
public_subnet_id=$(aws ec2 create-subnet --vpc-id "$vpc_id" --cidr-block 10.0.5.0/24 --availability-zone us-west-2a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=public_subnet}]' | jq -r '.Subnet.SubnetId')
echo "Public Subnet ID: $public_subnet_id"


echo "creating private subnet"
private_subnet_id=$(aws ec2 create-subnet --vpc-id "$vpc_id" --cidr-block 10.0.10.0/24 --availability-zone us-west-2a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=public_subnet}]' | jq -r '.Subnet.SubnetId')
echo "Private Subnet ID: $private_subnet_id"


echo "creating internet gateway"
igw_id=$(aws ec2 create-internet-gateway | jq -r ".InternetGateway.InternetGatewayId")

echo "Internet Gateway ID: $igw_id"

echo "attach Internet Gateway to VPC"
aws ec2 attach-internet-gateway --vpc-id $vpc_id --internet-gateway-id $igw_id

echo "creating route table for public subnet"
rtb_id=$(aws ec2 create-route-table --vpc-id $vpc_id | jq -r ".RouteTable.RouteTableId")
echo "Route Table ID: $rtb_id"









echo "deleting route table for public subnet"
aws ec2 delete-route-table --route-table-id $rtb_id

echo "detach and deleting igw..."
aws ec2 detach-internet-gateway --internet-gateway-id $igw_id --vpc-id $vpc_id
aws ec2 delete-internet-gateway --internet-gateway-id $igw_id


echo "deleting subnets..."
aws ec2 delete-subnet --subnet-id $public_subnet_id
aws ec2 delete-subnet --subnet-id $private_subnet_id


echo "deleting vpc..."
aws ec2 delete-vpc --vpc-id $vpc_id

echo "done..."

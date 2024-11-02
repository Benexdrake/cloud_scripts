yum update -y
yum install -y python3
python3 -m ensurepip --upgrade
pip3 install mysql-connector-python
echo "print("Hello, world!")" > /home/ec2-user/script.py
python3 /home/ec2-user/script.py'

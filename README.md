
# AWS CLI Anleitung: EC2-Instanzen mit VPC, Subnets, NAT und Internet Gateway

## Voraussetzungen
- AWS CLI ist installiert und konfiguriert (`aws configure`).
- Ein vorhandenes Key-Pair für SSH-Zugriff auf die Python-Instanz.

## Schritte

### 1. VPC erstellen
```bash
aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=mein-vpc}]'
```
Notiere dir die `VpcId` aus der Ausgabe. Alternativ kannst du auch einen Befehl eingeben, um dir die VPCs anzeigen zu lassen. Schaue dazu in die offizielle AWS Dokumentation.
```bash
aws ec2 describe-vpcs
```

### 2. Subnets erstellen
- Erstelle ein **Public Subnet** (für die Python-Instanz):
  ```bash
  aws ec2 create-subnet --vpc-id <VpcId> --cidr-block 10.0.5.0/24 --availability-zone <deine-AZ> --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=public_subnet}]'
  ```
- Erstelle ein **Private Subnet** (für die Datenbank-Instanz):
  ```bash
  aws ec2 create-subnet --vpc-id <VpcId> --cidr-block 10.0.10.0/24 --availability-zone <deine-AZ> --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=private_subnet}]'
  ```
  
Notiere dir die `SubnetId`s für das Public und Private Subnet.

### 3. Internet Gateway und Route Table für das Public Subnet erstellen
- **Internet Gateway erstellen und an VPC anhängen**:
  ```bash
  aws ec2 create-internet-gateway
  ```
  Füge es zur VPC hinzu:
  ```bash
  aws ec2 attach-internet-gateway --vpc-id <VpcId> --internet-gateway-id <InternetGatewayId>
  ```

- **Route Table für das Public Subnet**:
  ```bash
  aws ec2 create-route-table --vpc-id <VpcId>
  ```
  Erstelle eine Route für den Internetverkehr:
  ```bash
  aws ec2 create-route --route-table-id <RouteTableId> --destination-cidr-block 0.0.0.0/0 --gateway-id <InternetGatewayId>
  ```
  Assoziiere die Route Table mit dem Public Subnet:
  ```bash
  aws ec2 associate-route-table --subnet-id <PublicSubnetId> --route-table-id <RouteTableId>
  ```

### 4. NAT Gateway und Route Table für das Private Subnet erstellen
- **Elastic IP für NAT Gateway erstellen**:
  ```bash
  aws ec2 allocate-address
  ```
- **NAT Gateway erstellen**:
  ```bash
  aws ec2 create-nat-gateway --subnet-id <PublicSubnetId> --allocation-id <AllocationId>
  ```

- **Route Table für das Private Subnet**:
  ```bash
  aws ec2 create-route-table --vpc-id <VpcId>
  ```
  Route hinzufügen für das NAT Gateway:
  ```bash
  aws ec2 create-route --route-table-id <RouteTableIdPrivate> --destination-cidr-block 0.0.0.0/0 --nat-gateway-id <NatGatewayId>
  ```
  Assoziiere die Route Table mit dem Private Subnet:
  ```bash
  aws ec2 associate-route-table --subnet-id <PrivateSubnetId> --route-table-id <RouteTableIdPrivate>
  ```

### 5. Security Groups erstellen
- **Security Group für die Python-Instanz**:
  ```bash
  aws ec2 create-security-group --group-name PythonSG --description "Security group for Python EC2" --vpc-id <VpcId>
  ```
  Erlaube SSH-Zugriff (Port 22) :
  ```bash
  aws ec2 authorize-security-group-ingress --group-id <PythonSGId> --protocol tcp --port 22 --cidr 0.0.0.0/0
  ```

- **Security Group für die Datenbank-Instanz**:
  ```bash
  aws ec2 create-security-group --group-name DatabaseSG --description "Security group for MySQL Database EC2" --vpc-id <VpcId>
  ```
  Erlaube Verbindungen von der Python-Instanz auf Port 3306:
  ```bash
  aws ec2 authorize-security-group-ingress --group-id <DatabaseSGId> --protocol tcp --port 3306 --source-group <PythonSGId>
  ```

### 6. EC2-Instanzen erstellen
- Wir gehen in die Sandbox und downloaden unter AWS Details den SSH-Key (.pem-Datei). Du downloadest die Datei und die heißt "labsuser.pem". Das zugehörige Key-Pair heißt dann vockey. Dieses muss dann bei der Instanzerstellung angegeben werden.
- **Python-Instanz im Public Subnet** mit einem User Data Script, das ein Python-Skript ausführt. Das Image ist Amazon Linux 2:
  ```bash
  aws ec2 run-instances --image-id <AMI-ID> --instance-type t2.micro --key-name <KeyPairName> --subnet-id <PublicSubnetId> --security-group-ids <PythonSGId> --user-data '#!/bin/bash
  yum update -y
  yum install -y python3
  python3 -m ensurepip --upgrade
  pip3 install mysql-connector-python
  echo "print("Hello, world!")" > /home/ec2-user/script.py
  python3 /home/ec2-user/script.py' --associate-public-ip-address
  ```

- **MySQL-Instanz im Private Subnet** mit einem User Data Script für die Installation von MariaDB und die Erstellung eines Datenbank-Benutzers und einer Datenbank. Das Image ist Ubuntu 24.04:
  ```bash
  aws ec2 run-instances --image-id <AMI-ID> --instance-type t2.micro --key-name <KeyPairName> --subnet-id <PrivateSubnetId> --security-group-ids <DatabaseSGId> --user-data '#!/bin/bash
  apt update -y
  apt install mysql-server -y
  systemctl start mmysql
  systemctl enable mysql

  # bind-address auf 0.0.0.0 setzen
  sed -i "s/^bind-address.*/bind-address = 0.0.0.0/" /etc/mysql/mysql.conf.d/mysqld.cnf
  systemctl restart mysql

  # Datenbank und Benutzer erstellen
  DB_NAME="meinedb"
  DB_USER="meinbenutzer"
  DB_PASS="geheimespasswort"
  
  mysql -e "CREATE DATABASE $DB_NAME;"
  mysql -e "CREATE USER '$DB_USER'@'%' IDENTIFIED BY '$DB_PASS';"
  mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'%';"
  mysql -e "FLUSH PRIVILEGES;"
  '
  ```

### 7. Abschlusstests
- **Überprüfe die Verbindungen**:
  - SSH in die Python-Instanz.
  - Von der Python-Instanz aus teste die Verbindung zur MySQL-Instanz über Port 3306, um sicherzustellen, dass der Datenbankzugriff möglich ist.
  - Schreibe folgendes Python-Skript auf die Python-Instanz
```python
import os
from datetime import datetime
from mysql import connector

def create_connection():
        connection = connector.connect(
        host='<private-ip-der-db-instanz>',
        user='<user>',
        password='<password>',
        database='<db_name>'  
    )
        return connection

# CREATE funkiton 
def add_task(name, description, due, prio, state):
    conn = create_connection()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO tasks (name, description, due, prio, state)
        VALUES (?, ?, ?, ?, ?)
    ''', (name, description, due, prio, state))
    conn.commit()
    conn.close()

# READ function
def show_tasks(order_by='prio'):
    conn = create_connection()
    cursor = conn.cursor()
    cursor.execute(f'SELECT * FROM tasks ORDER BY {order_by}')
    tasks = cursor.fetchall()
    conn.close()
    return tasks

# UPDATE funktion
def update_task(task_id, name=None, description=None, due=None, prio=None, state=None):
    conn = create_connection()
    cursor = conn.cursor()
    query = 'UPDATE tasks SET '
    params = []

    if name:
        query += 'name = ?, '
        params.append(name)
    if description:
        query += 'description = ?, '
        params.append(description)
    if due:
        query += 'due = ?, '
        params.append(due)
    if prio:
        query += 'prio = ?, '
        params.append(prio)
    if state:
        query += 'state = ?, '
        params.append(state)
    
    query = query.rstrip(', ') + ' WHERE id = ?'
    params.append(task_id)

    cursor.execute(query, params)
    conn.commit()
    conn.close()

# DELETE funktion
def delete_task(task_id):
    conn = create_connection()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM tasks WHERE id = ?', (task_id,))
    conn.commit()
    conn.close()

# Multifunktionale Methode zum senden einer SQL Query
def execute(query:str):
    conn = create_connection()
    cursor = conn.cursor()
    cursor.execute(query)
    result = cursor.fetchall()
    conn.commit()
    cursor.close()
    conn.close()
    return result

# Main
def main():
    while True:
        print("\n---------- Aufgabenverwaltung ----------")
        print("1. Aufgabe hinzufügen")
        print("2. Aufgaben anzeigen")
        print("3. Aufgabe aktualisieren")
        print("4. Aufgabe löschen")
        print("5. Programm beenden")

        choice = input("\nWähle eine Option zwischen 1 und 5: ")

        if choice == '1':
            name = input("Aufgabenbezeichnung: ")
            description = input("Beschreibung: ")
            due = input("Fälligkeitsdatum (TT.MM.JJJJ HH:MM): ")
            due_dt = datetime.strptime(due, "%d.%m.%Y %H:%M").strftime("%Y-%m-%d %H:%M")
            prio = int(input("Priorität (1=Hoch), (2=Mittel), (3=Niedrig): "))
            state = input("Status: ")
            add_task(name, description, due_dt, prio, state)
            print("Aufgabe hinzugefügt.")

        elif choice == '2':
            id = input(
                "Gib die ID ein oder drücke ENTER für alle Datensätze: ")
            tasks = show_tasks(id if id else None)
            print("Aufgaben:")
            for task in tasks:
                task_color = get_status_color(task[6], task[4])
                due_date = format_date(task[4])
                print(
                    f"{RESET}{task_color}ID: {task[0]}, Name: {task[1]}, Beschreibung: {task[2]}, Fällig: {due_date}, Priorität: {task[5]}, Status: {task[6]}{RESET}")
     
        elif choice == '3':
            task_id = int(input("Aufgaben-ID zum Aktualisieren: "))
            name = input("Neuer Aufgabenname (ENTER = beibehalten): ") or None
            description = input("Neue Beschreibung (ENTER = beibehalten): ") or None
            due = input("Neues Fälligkeitsdatum (TT.MM.JJJJ HH:MM) (ENTER = beibehalten): ") or None
            prio = input("Neue Priorität (leave blank to keep current): ") or None
            state = input("Neuer Status (Offen, In Bearbeitung, Abgeschlossen) (ENTER = beibehalten): ") or None

            update_task(task_id,
                        name,
                        description,
                        datetime.strptime(due, "%d.%m.%Y %H:%M").strftime("%Y-%m-%d %H:%M") if due else None,
                        int(prio) if prio else None,
                        state)
            print("Aufgabe aktualisiert.")

        elif choice == '4':
            task_id = int(input("Aufgaben-ID zum Löschen: "))
            delete_task(task_id)
            print("Aufgabe gelöscht.")

        elif choice == '5':
            print("Programm beendet.")
            break

        else:
            print("Ungültige Auswahl. Bitte wähle eine Option zwischen 1 und 5.")

if __name__ == "__main__":
    connection = create_connection()
    cursor = connection.cursor()
    main()
    cursor.close()
    connection.close()
```
Das kannst du auch mit SCP machen. Führe dazu folgenden Befehl aus.
```bash
scp -i <pfad zum key> <pfad von zu kopierender Datei> ec2-user@<ip der instanz>:~/
```

## Zusammenfassung
- Du hast nun eine VPC mit einem Public und Private Subnet, ein Internet Gateway, eine Route Table für jedes Subnet sowie ein NAT Gateway für ausgehenden Datenverkehr des Private Subnet erstellt.
- Die Python-Instanz befindet sich im Public Subnet und kann per SSH erreicht werden.
- Die MySQL-Datenbank befindet sich im Private Subnet und ist nur von der Python-Instanz erreichbar.



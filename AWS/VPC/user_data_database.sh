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

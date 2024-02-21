#!/bin/bash

# Function to generate a secure password
generate_password() {
  openssl rand -base64 12
}

# Check for root access
if [ "$(id -u)" -ne 0 ]; then
  echo "Please run this script as root or using sudo."
  exit 1
fi

# Get user input for domain
read -p "Enter your domain (without http:// or https://): " domain

# Update the system
apt update && apt upgrade -y

# Install necessary packages
apt install -y sudo nano lsb-release ca-certificates apt-transport-https software-properties-common gnupg2 wget unzip curl apache2 mariadb-client mariadb-server

# Determine the installed PHP version
php_version=$(php -v | grep -Eo 'PHP [0-9]+\.[0-9]+' | cut -d ' ' -f2)

# Adjust php.ini
ini_file="/etc/php/$php_version/apache2/php.ini"
sed -i -e 's/memory_limit = .*/memory_limit = 1024M/' "$ini_file"
sed -i -e 's/upload_max_filesize = .*/upload_max_filesize = 16G/' "$ini_file"
sed -i -e 's/post_max_size = .*/post_max_size = 16G/' "$ini_file"
sed -i -e 's/;date.timezone =.*/date.timezone = America\/Chicago/' "$ini_file"

# Installation of other required programs
apt install -y apache2 mariadb-client mariadb-server

# Setting up a Database
db_password="$(generate_password)"
mysql -u root -e "create database $domain;"
mysql -u root -e "create user 'admin'@'localhost' identified by '$db_password';"
mysql -u root -e "grant all privileges on $domain.* to 'admin'@'localhost';"
mysql -u root -e "flush privileges;"

# Display the MariaDB root password
echo "MariaDB root password: $db_password"

# Delete the Placeholder Website
cd /var/www/html && rm index.html

# Download WordPress Files
cd /home && wget https://wordpress.org/latest.zip
unzip latest.zip
rm latest.zip
cp -R /home/wordpress/* /var/www/html

# Adjust Folder Permissions
chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;

# Setting up a Reverse-Proxy
cat > /etc/apache2/sites-available/wordpress.conf <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html/
    ServerName $domain

    <Directory /var/www/html/>
        Options +FollowSymlinks
        AllowOverride All
        Require all granted
        <IfModule mod_dav.c>
            Dav off
        </IfModule>
        SetEnv HOME /var/www/html
        SetEnv HTTP_HOME /var/www/html
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

# Activate the config and restart Apache
a2ensite wordpress.conf
systemctl restart apache2

# Installing an SSL Certificate via Certbot
apt install -y certbot python3-certbot-apache
certbot --apache -d $domain

# Configure WordPress
wp_config="/var/www/html/wp-config.php"
cp /var/www/html/wp-config-sample.php $wp_config

# Update database connection details in wp-config.php
sed -i -e "s/database_name_here/$domain/" $wp_config
sed -i -e "s/username_here/admin/" $wp_config
generated_password="$(generate_password)"
sed -i -e "s/password_here/$generated_password/" $wp_config
sed -i -e "s/localhost/localhost/" $wp_config
sed -i -e "s/wp_/$domain\_/" $wp_config

# Add a cronjob to ping WordPress wp-cron.php each minute
(crontab -l ; echo "*/1 * * * * curl -s http://$domain/wp-cron.php >/dev/null 2>&1") | crontab -

# Setup firewall to allow only SSH
ufw allow ssh
ufw --force enable

# Display WordPress login details
echo "WordPress has been configured."
echo "You can log in at: http://$domain/wp-login.php"
echo "Username: admin"
echo "Password: $generated_password"
echo "Note: It is recommended to change the password after logging in."

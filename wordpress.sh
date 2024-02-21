#!/bin/bash

# Function to generate a secure password
generate_password() {
  openssl rand -base64 12
}

# Function to replace dots with dashes in a string
replace_dots_with_dashes() {
  echo "$1" | tr '.' '-'
}

# Check for root access
if [ "$(id -u)" -ne 0 ]; then
  echo "Please run this script as root or using sudo."
  exit 1
fi

# Get user input for domain
read -p "Enter your domain (without http:// or https://): " domain

# Replace dots with dashes for the database name and username
db_name=$(replace_dots_with_dashes "$domain")
db_user=$(replace_dots_with_dashes "$domain")

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
mysql -u root -e "create database $db_name;"
mysql -u root -e "create user '$db_user'@'localhost' identified by '$db_password';"
mysql -u root -e "grant all privileges on $db_name.* to '$db_user'@'localhost';"
mysql -u root -e "flush privileges;"

# Display the MariaDB root password
echo "MariaDB root password: $db_password"

# Delete the Placeholder Website
rm -f /var/www/html/index.html

# Download WordPress Files
cd /home && wget https://wordpress.org/latest.zip
unzip -o latest.zip -d /var/www/html
rm latest.zip

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
certbot --apache -d $domain --non-interactive --agree-tos --email webmaster@$domain

# Configure WordPress
wp_config="/var/www/html/wp-config.php"
cp /var/www/html/wp-config-sample.php $wp_config

# Update database connection details in wp-config.php
sed -i -e "s/database_name_here/$db_name/" $wp_config
sed -i -e "s/username_here/$db_user/" $wp_config
generated_password="$(generate_password)"
sed -i -e "s/password_here/$generated_password/" $wp_config
sed -i -e "s/localhost/localhost/" $wp_config
sed -i -e "s/wp_/$db_name\_/" $wp_config

# Add a cronjob to ping WordPress wp-cron.php each minute
(crontab -l ; echo "*/1 * * * * curl -s http://$domain/wp-cron.php >/dev/null 2>&1") | crontab -

# Setup firewall to allow only SSH
ufw allow ssh
ufw --force enable

# Display WordPress login details
echo "WordPress has been configured."
echo "You can log in at: http://$domain/wp-login.php"
echo "Username: $db_user"
echo "Password: $generated_password"
echo "Note: It is recommended to change the password after logging in."
echo "Database Name: $db_name"
echo "Database User: $db_user"
echo "Database Password: $db_password"

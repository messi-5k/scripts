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

# Add the ondrej/php repository for the latest PHP version
add-apt-repository -y ppa:ondrej/php
apt update

# Install the latest PHP version
php_version=$(apt search ^php | grep -Eo 'php[0-9]+\.[0-9]+' | sort -V | tail -n 1)
apt install -y "$php_version"

# Install WordPress CLI
wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# Adjust php.ini
ini_file="/etc/php/$php_version/apache2/php.ini"
sed -i -e 's/memory_limit = .*/memory_limit = 1024M/' "$ini_file"
sed -i -e 's/upload_max_filesize = .*/upload_max_filesize = 16G/' "$ini_file"
sed -i -e 's/post_max_size = .*/post_max_size = 16G/' "$ini_file"
sed -i -e 's/;date.timezone =.*/date.timezone = America\/Chicago/' "$ini_file"

# Installation of other required programs
apt install -y apache2 mariadb-client mariadb-server

# Setting up a Database
mysql -u root -p
# Enter root password
create database $domain;
create user 'admin'@'localhost' identified by "$(generate_password)";
# Set a secure password for admin user
grant all privileges on $domain.* to 'admin'@'localhost';
flush privileges;
exit

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
nano /etc/apache2/sites-available/wordpress.conf

# Paste the VirtualHost configuration and replace <YourEmail>, <Your(Sub)Domain>, and add the domain for Certbot
sed -i -e "s/<Your(Sub)Domain>/$domain/" /etc/apache2/sites-available/wordpress.conf

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

# Display wp-cli installation message
echo "WordPress CLI (wp-cli) has been installed. You can use 'wp' command for WordPress management."

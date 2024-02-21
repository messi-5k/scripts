#!/bin/bash

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

echo "If prompted, please accept the questions in the prompts to continue."

# Generate passwords
wordpress_user_admin="$(openssl rand -hex 10)"
mysql_pass="$(openssl rand -hex 64)"
mysql_user_pass="$(openssl rand -hex 64)"

# Go to the home directory
cd ~/

# Save installation and software passwords
echo "Installation and software passwords:" > passwords.txt
echo "wordpress_admin_password=$wordpress_user_admin" >> passwords.txt
echo "mysql_root_password=$mysql_pass" >> passwords.txt
echo "mysql_wordpress_user_password=$mysql_user_pass" >> passwords.txt

# Setup firewall to allow only SSH
ufw allow ssh
ufw --force enable

# Update packages without interaction, keeping existing config files
DEBIAN_FRONTEND=noninteractive apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade

# Update software repositories and upgrade packages
apt-get update && apt-get upgrade -y

# Install unattended-upgrades package for automatic updates
apt-get install unattended-upgrades -y

# Ensure unattended-upgrades service is enabled
systemctl enable unattended-upgrades.service

# Install required packages
apt-get install apache2 \
                 unzip \
                 ghostscript \
                 libapache2-mod-php \
                 mariadb-server \
                 php \
                 php-bcmath \
                 php-curl \
                 php-imagick \
                 php-intl \
                 php-json \
                 php-mbstring \
                 php-mysql \
                 php-xml \
                 php-zip -y

# Install WordPress
mkdir -p /srv/www
chown www-data: /srv/www
curl https://wordpress.org/latest.tar.gz | sudo -u www-data tar zx -C /srv/www

# Configure Apache for WordPress
echo "<VirtualHost *:80>
    DocumentRoot /srv/www/wordpress
    <Directory /srv/www/wordpress>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    <Directory /srv/www/wordpress/wp-content>
        Options FollowSymLinks
        Require all granted
    </Directory>
</VirtualHost>" > /etc/apache2/sites-available/wordpress.conf

# Enable the site and required modules
a2ensite wordpress.conf
a2enmod rewrite
a2dissite 000-default
systemctl reload apache2
systemctl restart apache2

# Start MySQL service and run the secure installation script
systemctl start mariadb.service
mysql_secure_installation <<EOF
y
$mysql_pass
$mysql_pass
y
y
y
y
EOF

# Create WordPress database and user
mysql --user="root" --password="$mysql_pass" --execute="CREATE DATABASE wordpress;"
mysql --user="root" --password="$mysql_pass" --execute="CREATE USER 'wordpress'@'localhost' IDENTIFIED BY '$mysql_user_pass';"
mysql --user="root" --password="$mysql_pass" --execute="GRANT ALL PRIVILEGES ON wordpress.* TO 'wordpress'@'localhost';"
mysql --user="root" --password="$mysql_pass" --execute="FLUSH PRIVILEGES;"

# Configure WordPress config
sudo -u www-data cp /srv/www/wordpress/wp-config-sample.php /srv/www/wordpress/wp-config.php
sudo -u www-data sed -i 's/database_name_here/wordpress/' /srv/www/wordpress/wp-config.php
sudo -u www-data sed -i 's/username_here/wordpress/' /srv/www/wordpress/wp-config.php
sudo -u www-data sed -i -e "s/password_here/${mysql_user_pass}/g" /srv/www/wordpress/wp-config.php

# Insert unique authentication keys and salts
wget -O /tmp/wp.keys https://api.wordpress.org/secret-key/1.1/salt/
sed -i '/AUTH_KEY/d' /srv/www/wordpress/wp-config.php
sed -i '/SECURE_AUTH_KEY/d' /srv/www/wordpress/wp-config.php
sed -i '/LOGGED_IN_KEY/d' /srv/www/wordpress/wp-config.php
sed -i '/NONCE_KEY/d' /srv/www/wordpress/wp-config.php
sed -i '/AUTH_SALT/d' /srv/www/wordpress/wp-config.php
sed -i '/SECURE_AUTH_SALT/d' /srv/www/wordpress/wp-config.php
sed -i '/LOGGED_IN_SALT/d' /srv/www/wordpress/wp-config.php
sed -i '/NONCE_SALT/d' /srv/www/wordpress/wp-config.php
sed -i '/\$table_prefix/r /tmp/wp.keys' /srv/www/wordpress/wp-config.php

# Clean up
rm /tmp/wp.keys

# Install Diode and publish new site (Check for the latest method to install Diode as this might change)
curl -Ssf https://diode.io/install.sh | sh
export PATH=/root/opt/diode:$PATH
diode_address=$(diode config 2>&1 | awk '/<address>/ { print $NF }')

# Install WordPress CLI
wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -O /usr/local/bin/wp
chmod +x /usr/local/bin/wp

# Finish WordPress installation
wp core install --allow-root --path="/srv/www/wordpress" --title="WordPress on Diode" --url="http://${diode_address}.diode.link" --admin_email="admin@localhost.com" --admin_password="$wordpress_user_admin" --admin_user="admin"

# Install plugins and theme
wp plugin install wp-fail2ban --allow-root --path="/srv/www/wordpress"
wp plugin activate wp-fail2ban --allow-root --path="/srv/www/wordpress"

# Set ownership
chown -R www-data:www-data /srv/www

# Configure systemd for Diode (if applicable, adjust based on Diode's current deployment options)
echo "[Unit]
Description=Diode blockchain network client

[Service]
Type=simple
ExecStart=/root/opt/diode/diode publish -public 80:80
Restart=always
RuntimeMaxSec=14400
ExecStartPre=/bin/sleep 60
User=root

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/diode.service

#Enable diode
systemctl enable diode
echo "Starting Diode - 60 second delay..."
systemctl start diode
systemctl status diode

echo "Done setting up the Diode CLI - it is now persistent on this system"
echo "You can type 'systemctl status diode' to get status on the Diode CLI in the future"

#display login instructions
echo "wordpress url is http://${diode_address}.diode.link"
echo "log into wordpress with the user name admin"
echo "and the password $wordpress_user_admin"
echo "remember to change the password and save it in a password manager"

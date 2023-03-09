#!/bin/sh
# Instructions on how to use this script:
# chmod +x SCRIPTNAME.sh
# sudo ./SCRIPTNAME.sh
#

# Change the default pkg repository from quarterly to latest
sed -ip 's/quarterly/latest/g' /etc/pkg/FreeBSD.conf

# Update packages (it will first download the pkg repo from latest)
# secondly it will upgrade any installed packages.
pkg upgrade -y

# Install Fail2ban
pkg install -y py39-fail2ban nano

# Enable the service to be started/stopped/restarted/etc
sysrc fail2ban_enable="YES"

# Configure a Jail to protect the SSH connections
touch /usr/local/etc/fail2ban/jail.d/ssh-ipfw.local

echo "[ssh-ipfw]
enabled = true
filter = sshd
action = ipfw[name=SSH, port=ssh, protocol=tcp]
logpath = /var/log/auth.log
findtime = 600
maxretry = 2
bantime = 604800" >> /usr/local/etc/fail2ban/jail.d/ssh-ipfw.local

# Start the service
service fail2ban start

# Simple IPFW workstation firewall
sysrc firewall_enable="YES"
sysrc firewall_quiet="YES"
sysrc firewall_type="workstation"
sysrc firewall_logdeny="YES"
sysrc firewall_allowservices="any"


# To enable services like remote SSH access or setting up a web server
# uncommenting the following up will allow them when issuing this script.
sysrc firewall_myservices="22/tcp 80/tcp 443/tcp"

# Start up the firewall
service ipfw start

pkg install -y apache24

# Add service to be fired up at boot time
sysrc apache24_enable="YES"

# Install MariaDB 10.6
pkg install -y mariadb106-server mariadb106-client

# Add service to be fired up at boot time
sysrc mysql_enable="YES"
sysrc mysql_args="--bind-address=127.0.0.1"

pkg install -y	php82\
		php82-bcmath\
		php82-bz2\
		php82-ctype\
		php82-curl\
		php82-dom\
		php82-exif\
		php82-extensions\
		php82-fileinfo\
		php82-filter\
		php82-ftp\
		php82-gd\
		php82-iconv\
		php82-intl\
		php82-mbstring\
		php82-mysqli\
		php82-opcache\
		php82-pdo\
		php82-pdo_mysql\
		php82-pecl-mcrypt\
		php82-phar\
		php82-posix\
		php82-session\
		php82-simplexml\
		php82-soap\
		php82-sockets\
		php82-sqlite3\
		php82-tokenizer\
		php82-xml\
		php82-xmlreader\
		php82-xmlwriter\
		php82-zip\
		php82-zlib


# Install the 'old fashioned' Expect to automate the mysql_secure_installation part
pkg install -y expect

# Set a ServerName directive in Apache HTTP. Place a name to your server.
sed -i -e 's/#ServerName www.example.com:80/ServerName skireviewer/g' /usr/local/etc/apache24/httpd.conf

# Configure Apache HTTP to use MPM Event instead of the Prefork default
# 1.- Disable the Prefork MPM
sed -i -e '/prefork/s/LoadModule/#LoadModule/' /usr/local/etc/apache24/httpd.conf

# 2.- Enable the Event MPM
sed -i -e '/event/s/#LoadModule/LoadModule/' /usr/local/etc/apache24/httpd.conf

# 3.- Enable the proxy module for PHP-FPM to use it
sed -i -e '/mod_proxy.so/s/#LoadModule/LoadModule/' /usr/local/etc/apache24/httpd.conf

# 4.- Enable the FastCGI module for PHP-FPM to use it
sed -i -e '/mod_proxy_fcgi.so/s/#LoadModule/LoadModule/' /usr/local/etc/apache24/httpd.conf

# Enable PHP to use the FPM process manager
sysrc php_fpm_enable="YES"

# Create configuration file for Apache HTTP to 'speak' PHP
touch /usr/local/etc/apache24/modules.d/003_php-fpm.conf

# Add the configuration into the file
echo "
<IfModule proxy_fcgi_module>
    <IfModule dir_module>
        DirectoryIndex index.php
    </IfModule>
    <FilesMatch \"\.(php|phtml|inc)$\">
        SetHandler \"proxy:fcgi://127.0.0.1:9000\"
    </FilesMatch>
</IfModule>" >> /usr/local/etc/apache24/modules.d/003_php-fpm.conf

# Create configuration file for PHPINFO
touch /usr/local/www/apache24/data/info.php

# Add the configuration into the file
echo "
<?php
phpinfo();
phpinfo(INFO_MODULES);
?>" >> /usr/local/www/apache24/data/info.php

# Set the PHP's default configuration
cp /usr/local/etc/php.ini-production /usr/local/etc/php.ini

# Fire up the services
service apache24 start
service mysql-server start
service php-fpm start

# Make the 'safe' install for MariaDB
echo "Performing MariaDB secure install"

SECURE_MARIADB=$(expect -c "
set timeout 10
spawn mysql_secure_installation
expect \"Switch to unix_socket authentication\"
send \"n\r\"
expect \"Change the root password?\"
send \"n\r\"
expect \"Remove anonymous users?\"
send \"y\r\"
expect \"Disallow root login remotely?\"
send \"y\r\"
expect \"Remove test database and access to it?\"
send \"y\r\"
expect \"Reload privilege tables now?\"
send \"y\r\"
expect eof
")

echo "$SECURE_MARIADB"

# 1.- Removing the OS type and modifying version banner (no mod_security here). 
# 1.1- ServerTokens will only display the minimal information possible.
sed -i '' -e '227i\
# ServerTokens Prod' /usr/local/etc/apache24/httpd.conf

# 1.2- ServerSignature will disable the server exposing its type.
sed -i '' -e '228i\
# ServerSignature Off' /usr/local/etc/apache24/httpd.conf

# Alternatively we can inject the line at the bottom of the file using the echo command.
# This is a safer option if you make heavy changes at the top of the file.
# echo 'ServerTokens Prod' >> /usr/local/etc/apache24/httpd.conf
# echo 'ServerSignature Off' >> /usr/local/etc/apache24/httpd.conf

# 2.- Avoid PHP's information (version, etc) being disclosed
sed -i -e '/expose_php/s/expose_php = On/expose_php = Off/' /usr/local/etc/php.ini

# 3.- Fine tunning access to the DocumentRoot directory structure
sed -i '' -e 's/Options Indexes FollowSymLinks/Options -Indexes +FollowSymLinks -Includes/' /usr/local/etc/apache24/httpd.conf

# 4.- Enabling TLS connections with a self signed certificate. 
# 4.1- Key and certificate generation
# IMPORTANT: Please do adapt to your needs the fields below like: Organization, Common Name and Email, etc.
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /usr/local/etc/apache24/server.key -out /usr/local/etc/apache24/server.crt -subj "/C=RU/ST=Kaliningrad/L=New/O=1big.ru/CN=example.com/emailAddress=youremail@gmail.com"

# Because we have generated a certificate + key we will enable SSL/TLS in the server.
# 4.3- Enabling TLS connections in the server.
sed -i -e '/mod_ssl.so/s/#LoadModule/LoadModule/' /usr/local/etc/apache24/httpd.conf

# 4.4- Enable the server's default TLS configuration to be applied.
sed -i -e '/httpd-ssl.conf/s/#Include/Include/' /usr/local/etc/apache24/httpd.conf

# 4.5- Enable TLS session cache.
sed -i -e '/mod_socache_shmcb.so/s/#LoadModule/LoadModule/' /usr/local/etc/apache24/httpd.conf

# 4.6- Redirect HTTP connections to HTTPS (port 80 and 443 respectively)
# 4.6.1- Enabling the rewrite module
sed -i -e '/mod_rewrite.so/s/#LoadModule/LoadModule/' /usr/local/etc/apache24/httpd.conf

# 4.6.2- Adding the redirection rules.
# Use the following sed entries if you are using the event-php-fpm.sh script.
sed -i '' -e '181i\
RewriteEngine On' /usr/local/etc/apache24/httpd.conf

sed -i '' -e '182i\
RewriteCond %{HTTPS}  !=on' /usr/local/etc/apache24/httpd.conf

sed -i '' -e '183i\
RewriteRule ^/?(.*) https://%{SERVER_NAME}/$1 [R,L]' /usr/local/etc/apache24/httpd.conf

# 5.- Secure the headers to a minimum
echo "
<IfModule mod_headers.c>
    Header set Content-Security-Policy \"upgrade-insecure-requests;\"
    Header set Strict-Transport-Security \"max-age=31536000; includeSubDomains\"
    Header always edit Set-Cookie (.*) \"\$1; HttpOnly; Secure\"
    Header set X-Content-Type-Options \"nosniff\"
    Header set X-XSS-Protection \"1; mode=block\"
    Header set Referrer-Policy \"strict-origin\"
    Header set X-Frame-Options: \"deny\"
    SetEnv modHeadersAvailable true
</IfModule>" >>  /usr/local/etc/apache24/httpd.conf

# 6.- Disable the TRACE method.
echo 'TraceEnable off' >> /usr/local/etc/apache24/httpd.conf

# 7.- Allow specific HTTP methods.
sed -i '' -e '269i\
    <LimitExcept GET POST HEAD>' /usr/local/etc/apache24/httpd.conf

sed -i '' -e '270i\
       deny from all' /usr/local/etc/apache24/httpd.conf

sed -i '' -e '271i\
    </LimitExcept>' /usr/local/etc/apache24/httpd.conf


# 8.- Restart Apache HTTP so changes take effect.
service apache24 restart

# Create the database and user. Mind this is MariaDB.
#pkg install -y pwgen

#touch /root/new_db_name.txt
#touch /root/new_db_user_name.txt
#touch /root/newdb_pwd.txt

# Create the database and user. 
#NEW_DB_NAME=$(pwgen 8 --secure --numerals --capitalize) && export NEW_DB_NAME && echo $NEW_DB_NAME >> /root/new_db_name.txt

#NEW_DB_USER_NAME=$(pwgen 10 --secure --numerals --capitalize) && export NEW_DB_USER_NAME && echo $NEW_DB_USER_NAME >> /root/new_db_user_name.txt

#NEW_DB_PASSWORD=$(pwgen 32 --secure --numerals --capitalize) && export NEW_DB_PASSWORD && echo $NEW_DB_PASSWORD >> /root/newdb_pwd.txt

#NEW_DATABASE=$(expect -c "
#set timeout 10
#spawn mysql -u root -p
#expect \"Enter password:\"
#send \"\r\"
#expect \"root@localhost \[(none)\]>\"
#send \"CREATE DATABASE $NEW_DB_NAME;\r\"
#expect \"root@localhost \[(none)\]>\"
#send \"CREATE USER '$NEW_DB_USER_NAME'@'localhost' IDENTIFIED BY '$NEW_DB_PASSWORD';\r\"
#expect \"root@localhost \[(none)\]>\"
#send \"GRANT ALL PRIVILEGES ON $NEW_DB_NAME.* TO '$NEW_DB_USER_NAME'@'localhost';\r\"
#expect \"root@localhost \[(none)\]>\"
#send \"FLUSH PRIVILEGES;\r\"
#expect \"root@localhost \[(none)\]>\"
#send \"exit\r\"
#expect eof
#")

#echo "$NEW_DATABASE"

# Enable the use of .htaccess.
sed -i '' -e '279s/AllowOverride None/AllowOverride All/g' /usr/local/etc/apache24/httpd.conf

# Restart Apache HTTP so changes take effect
service apache24 restart

chown -R www:www /usr/local/www/apache24/data

echo 'Restarting services'

# Preventive services restart
service apache24 restart
service php-fpm restart
service mysql-server restart

# No one but root can read these files. Read only permissions.
#chmod 400 /root/new_db_name.txt
#chmod 400 /root/new_db_user_name.txt
#chmod 400 /root/newdb_pwd.txt

# Display the new database, username and password generated on MySQL
#echo "Your DB_ROOT_PASSWORD is blank if you are root or a highly privileged user"
#echo "Your NEW_DB_NAME is written on this file /root/new_db_name.txt"
#echo "Your NEW_DB_USER_NAME is written on this file /root/new_db_user_name.txt"
#echo "Your NEW_DB_PASSWORD is written on this file /root/newdb_pwd.txt"

# Actions on the CLI are now finished.
echo 'Actions on the CLI are now finished. Please visit the ip/domain of the site with a web browser and proceed with the final steps of install
'
echo 'Remember to place 127.0.0.1 in the Host field in the Advanced Parameters section, otherwise the install will probably not work.'

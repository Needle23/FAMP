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
pkg install -y py39-fail2ban nano htop

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

# Install NGINX web server
pkg install -y nginx

# Include NGINX as a service to fire up at boot time
sysrc nginx_enable="YES"

# Rename default NGINX configuration. A customized one is found below.
mv /usr/local/etc/nginx/nginx.conf /usr/local/etc/nginx/nginx.conf.original

# Create an empty default NGINX configuration file.
touch /usr/local/etc/nginx/nginx.conf

# Generate TLS self-signed key and certificate with OpenSSL

openssl genpkey -algorithm RSA -out /usr/local/etc/nginx/cert.key 
openssl req -new -x509 -days 365 -key /usr/local/etc/nginx/cert.key -out /usr/local/etc/nginx/cert.crt -sha256 -subj "/C=RU/ST=Russia/L=Kaliningrad/O=Adminbyaccident/OU=Operations/CN=server.ru"

# Configure NGINX (as a reverse proxy)
echo "

#user  nobody;
worker_processes  1;

# This default error log path is compiled-in to make sure configuration parsing
# errors are logged somewhere, especially during unattended boot when stderr
# isn't normally logged anywhere. This path will be touched on every nginx
# start regardless of error log location configured here. See
# https://trac.nginx.org/nginx/ticket/147 for more info. 
#
#error_log  /var/log/nginx/error.log;
#

#pid        logs/nginx.pid;


events {
    worker_connections  1024;
}


http {
    include       mime.types;
    default_type  application/octet-stream;

    #log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
    #                  '$status $body_bytes_sent "$http_referer" '
    #                  '"$http_user_agent" "$http_x_forwarded_for"';

    #access_log  logs/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    #keepalive_timeout  0;
    keepalive_timeout  65;

    #gzip  on;

server {
    listen 80;
    return 301 https://$host$request_uri;
}

server {

    listen 443 ssl;
    server_name localhost;

    auth_basic "Restricted Access";
    auth_basic_user_file /usr/local/etc/nginx/htpasswd.users;
    
    ssl_certificate           /usr/local/etc/nginx/cert.crt;
    ssl_certificate_key       /usr/local/etc/nginx/cert.key;

    ssl_session_cache  builtin:1000  shared:SSL:10m;
    ssl_protocols   TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!eNULL:!EXPORT:!CAMELLIA:!DES:!MD5:!PSK:!RC4;
    ssl_prefer_server_ciphers on;
    
    access_log            /var/log/nginx/elk.log;
    add_header Strict-Transport-Security "max-age=63072000" always;


    location / {

      proxy_set_header        Host $host;
      proxy_set_header        X-Real-IP $remote_addr;
      proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header        X-Forwarded-Proto $scheme;
      proxy_pass              http://localhost:5601;
      proxy_read_timeout      90;

      proxy_redirect      http://localhost:5601 https://$host$request_uri;
    }
  }

}
" >> /usr/local/etc/nginx/nginx.conf

# Create an empty log file to register NGINX
touch /var/log/nginx/elk.log

# Wait a few seconds for Kibana to get ready
sleep 15

# Start NGINX web server
service nginx start

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

# Enable PHP to use the FPM process manager
sysrc php_fpm_enable="YES"

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

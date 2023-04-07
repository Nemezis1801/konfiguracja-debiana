#!/bin/bash

# Aktualizacja systemu i instalacja narzędzi
apt update
apt upgrade -y
apt install build-essential curl git -y

# Instalacja serwera Apache
apt install apache2 -y
systemctl start apache2
systemctl enable apache2

# Instalacja PHP i modułów PHP
apt install php libapache2-mod-php php-cli php-curl php-gd php-mysql php-mbstring php-xml -y

# Instalacja bazy danych MySQL/MariaDB
apt install mariadb-server mariadb-client -y
systemctl start mariadb
systemctl enable mariadb

# Zabezpieczenie bazy danych MySQL/MariaDB
mysql_secure_installation

# Instalacja narzędzi do pracy z plikami FTP
apt install vsftpd -y
systemctl start vsftpd
systemctl enable vsftpd

# Instalacja narzędzi do monitorowania serwera
apt install htop -y

# Instalacja fail2ban i ufw
apt install fail2ban ufw -y

# Konfiguracja Fail2ban
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sed -i 's/bantime = 10m/bantime = 1h/g' /etc/fail2ban/jail.local
sed -i 's/maxretry = 5/maxretry = 3/g' /etc/fail2ban/jail.local
systemctl enable fail2ban
systemctl start fail2ban

# Konfiguracja firewalla UFW
ufw allow OpenSSH
ufw allow 'Apache Full'
ufw enable

# Konfiguracja SSL
apt install certbot python3-certbot-apache -y
certbot --apache

# Wyłączenie niepotrzebnych modułów Apache
a2dismod status
a2dismod autoindex
a2dismod negotiation

# Zablokowanie dostępu do plików .htaccess
echo "<Files .htaccess>" > /etc/apache2/conf-available/htaccess.conf
echo "Order allow,deny" >> /etc/apache2/conf-available/htaccess.conf
echo "Deny from all" >> /etc/apache2/conf-available/htaccess.conf
echo "</Files>" >> /etc/apache2/conf-available/htaccess.conf
a2enconf htaccess

# Włączenie modułu mod_security
apt install libapache2-mod-security2 -y
sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/g' /etc/modsecurity/modsecurity.conf-recommended
ln -s /usr/share/modsecurity-crs/owasp-crs.load /etc/apache2/mods-enabled/
ln -s /usr/share/modsecurity-crs/owasp-crs.conf /etc/apache2/mods-enabled/
systemctl restart apache2

# Utworzenie użytkownika www-data bez loginu
useradd --no-create-home --shell /usr/sbin/nologin www-data

# Zmiana uprawnień dla plików i katalogów
chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 750 {} \;
find /var/www/html -type f -exec chmod 640 {} \;

# Restart Apache
systemctl restart apache2

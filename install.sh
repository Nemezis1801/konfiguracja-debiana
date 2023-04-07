#!/bin/bash

# Pobranie wartości od użytkownika i przypisanie jej do zmiennej
read -p "Wprowadź użytkownika bez uprawnień root (służy do ograczenia dostępu temu użytkownikowi): " USERS
read -p "Wprowadź adresy IP z których można się logować w formie np. 192.168.0.0/24 10.0.0.0/24: " allowed_ips
read -p "Wprowadź użytkowników, którzy mogą się logować wymieniając ich w formie \"user1\" \"user2\": " allowed_users

# Pobranie hasła do użytkownika root w MySQL
echo -n "Podaj hasło użytkownika root w MySQL: "
read -s mysql_password
echo

# Ustawienie adresów IP, dla których będzie dostępny serwer
allowed_ips=("$allowed_ips")

# Ustawienie użytkowników, którzy mają mieć dostęp do serwera
allowed_users=(allowed_users)

cat >>  /etc/resolv.conf << EOF
		search umg.edu.pl
		nameserver 153.19.111.230
		nameserver 153.19.250.19
		nameserver 153.19.112.230
EOF

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

# Wywołanie funkcji mysql_secure_installation z automatycznym wprowadzeniem danych
mysql_secure_installation <<EOF

$mysql_password
y
$mysql_password
y
y
y
y

EOF

# Instalacja narzędzi do pracy z plikami FTP
apt install vsftpd -y
systemctl start vsftpd
systemctl enable vsftpd

# Ustawienie opcji chroot_local_user na YES
sed -i 's/#chroot_local_user=YES/chroot_local_user=YES/g' /etc/vsftpd.conf

# Dodanie opcji local_root=/home/$USER
echo "local_root=/home/\$USER" >> /etc/vsftpd.conf

# Dodanie opcji write_enable=YES
echo "write_enable=YES" >> /etc/vsftpd.conf

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

# Ustawienie domyślnych zasad firewalla
ufw default deny incoming
ufw default allow outgoing

# Konfiguracja firewalla UFW
ufw allow ssh
ufw allow http
ufw allow https
ufw enable

# Wyłączenie niepotrzebnych modułów Apache
a2dismod status
a2dismod autoindex
a2dismod cgi
a2dismod negotiation
a2dismod userdir

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

# Utworzenie użytkownika www-data bez loginu
useradd --no-create-home --shell /usr/sbin/nologin www-data

# Zmiana uprawnień dla plików i katalogów
chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 750 {} \;
find /var/www/html -type f -exec chmod 640 {} \;

# Utworzenie osobnego pliku logów dla Apache
cp /etc/apache2/conf-available/other-vhosts-access-log.conf /etc/apache2/conf-available/other-vhosts-access-log.conf.bak
sed -i 's|CustomLog /var/log/apache2/other_vhosts_access.log vhost_combined|#CustomLog /var/log/apache2/other_vhosts_access.log vhost_combined|g' /etc/apache2/conf-available/other-vhosts-access-log.conf
echo "CustomLog /var/log/apache2/access.log combined" >> /etc/apache2/conf-available/other-vhosts-access-log.conf

# Pobranie numeru wersji PHP
php_version=$(php -r "echo PHP_VERSION;")

# Utworzenie osobnego pliku logów dla PHP
cp /etc/php/$php_version/apache2/php.ini /etc/php/$php_version/apache2/php.ini.bak
sed -i 's|;error_log = log/php_error.log|error_log = /var/log/php_errors.log|g' /etc/php/$php_version/apache2/php.ini
touch /var/log/php_errors.log
chmod 666 /var/log/php_errors.log
systemctl restart apache2

# Edycja pliku konfiguracyjnego SSH
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
sed -i 's/#MaxAuthTries 6/MaxAuthTries 3/' /etc/ssh/sshd_config
sed -i 's/#LoginGraceTime 2m/LoginGraceTime 1m/' /etc/ssh/sshd_config
sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords no/' /etc/ssh/sshd_config
sed -i 's/Subsystem/#Subsystem/' /etc/ssh/sshd_config
sed -i 's/#ServerSignature Off/ServerSignature Off/' /etc/apache2/conf-enabled/security.conf
sed -i 's/#TraceEnable Off/TraceEnable Off/' /etc/apache2/conf-enabled/security.conf
sed -i 's/TraceEnable On/#TraceEnable On/' /etc/apache2/conf-enabled/security.conf
sed -i 's/ServerSignature On/#ServerSignature On/' /etc/apache2/conf-enabled/security.conf

# Utworzenie pliku konfiguracyjnego SSH
echo "AllowUsers ${allowed_users[*]}" >> /etc/ssh/sshd_config

# Dodanie reguł do firewalla
for ip in "${allowed_ips[@]}"
do
    ufw allow from $ip to any port 22
done

# Restart Apache
systemctl restart apache2

# Restart usługi SSH
systemctl restart sshd

# Restart usługi vsftpd
systemctl restart vsftpd

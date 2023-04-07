#!/bin/bash

# Pobranie wartości od użytkownika i przypisanie jej do zmiennej
read -p "Wprowadź użytkownika bez uprawnień root (służy do ograczenia dostępu temu użytkownikowi): " USERS
read -p "Wprowadź adresy IP z których można się logować w formie np. 192.168.0.0/24 10.0.0.0/24: " allowed_ips
read -p "Wprowadź użytkowników, którzy mogą się logować wymieniając ich w formie \"user1\" \"user2\": " allowed_users
read -p "Podaj adresy DNS oddzielone spacją: " dns_addresses
read -p "Podaj adres domenowy DNS: " domena
read -p "Podaj hasło użytkownika root w MySQL: " mysql_password


# Ustawienie adresów IP, dla których będzie dostępny serwer
allowed_ips=("$allowed_ips")

# Ustawienie użytkowników, którzy mają mieć dostęp do serwera
allowed_users=(allowed_users)

# Dodanie wpisów do pliku /etc/resolv.conf
echo "Dodawanie domeny do pliku /etc/resolv.conf"
cat > /etc/resolv.conf <<EOF
search $domena
EOF

# Dodanie wpisów do pliku /etc/resolv.conf
echo "Dodawanie adresów IP do resolv.conf"
cat > /etc/resolv.conf <<EOF
search umg.edu.pl
EOF

for dns_address in $dns_addresses; do
    echo "nameserver $dns_address" >> /etc/resolv.conf
done

# Aktualizacja systemu i instalacja narzędzi
echo "Aktulizacja i instalacja niezbędnych narzędzi" 
apt update > /dev/null
apt upgrade -y > /dev/null
apt install htop fail2ban ufw build-essential curl git apache2 mariadb-server mariadb-client php libapache2-mod-php php-cli php-curl php-gd php-mysql php-mbstring php-xml vsftpd -y > /dev/null

# Instalacja serwera Apache
echo "Włączanie Apache"
systemctl start apache2 
systemctl enable apache2 


# Instalacja bazy danych MySQL/MariaDB
echo "Włączanie MariaDB"
systemctl start mariadb
systemctl enable mariadb

# Wywołanie funkcji mysql_secure_installation z automatycznym wprowadzeniem danych
echo "Zabezpieczanie bazy danych"
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
echo "włączanie vsftpd"
systemctl start vsftpd
systemctl enable vsftpd

# Ustawienie opcji chroot_local_user na YES
echo "Konfiguracja vsftpd"
sed -i 's/#chroot_local_user=YES/chroot_local_user=YES/g' /etc/vsftpd.conf
echo "local_root=/home/\$USER" >> /etc/vsftpd.conf
echo "write_enable=YES" >> /etc/vsftpd.conf

# Konfiguracja Fail2ban
echo "Konfiguracja Fail2ban"
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sed -i 's/bantime = 10m/bantime = 1h/g' /etc/fail2ban/jail.local
sed -i 's/maxretry = 5/maxretry = 3/g' /etc/fail2ban/jail.local
systemctl enable fail2ban
systemctl start fail2ban

# Konfiguracja zasad firewalla
echo "Konfiguracja firewalla"
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow http
ufw allow https
ufw enable

# Wyłączenie niepotrzebnych modułów Apache
echo "Wyłączanie modułów Apache"
a2dismod status
a2dismod autoindex
a2dismod cgi
a2dismod negotiation
a2dismod userdir

# Zablokowanie dostępu do plików .htaccess
echo "Zablokowanie dostępu do plików .htaccess"
echo "<Files .htaccess>" > /etc/apache2/conf-available/htaccess.conf
echo "Order allow,deny" >> /etc/apache2/conf-available/htaccess.conf
echo "Deny from all" >> /etc/apache2/conf-available/htaccess.conf
echo "</Files>" >> /etc/apache2/conf-available/htaccess.conf
a2enconf htaccess

# Sprawdzenie, czy użytkownik www-data istnieje
echo "Konfiguracja użytkownika www-data"
if id -u www-data >/dev/null 2>&1; then
    usermod --shell /usr/sbin/nologin www-data
else
    useradd --no-create-home --shell /usr/sbin/nologin www-data
fi

# Zmiana uprawnień dla plików i katalogów
echo "Zmiana uprawnień do plików i katalogów"
chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 750 {} \;
find /var/www/html -type f -exec chmod 640 {} \;

# Utworzenie osobnego pliku logów dla Apache
echo "Utworznie osobnego pliku do logów dla Apache"
cp /etc/apache2/conf-available/other-vhosts-access-log.conf /etc/apache2/conf-available/other-vhosts-access-log.conf.bak
sed -i 's|CustomLog /var/log/apache2/other_vhosts_access.log vhost_combined|#CustomLog /var/log/apache2/other_vhosts_access.log vhost_combined|g' /etc/apache2/conf-available/other-vhosts-access-log.conf
echo "CustomLog /var/log/apache2/access.log combined" >> /etc/apache2/conf-available/other-vhosts-access-log.conf

# Utworzenie osobnego pliku logów dla PHP
echo "Utworzenie osobnego pliku logów dla PHP"
php_version=$(php -r "echo substr(PHP_VERSION, 0, 3);")
cp /etc/php/$php_version/apache2/php.ini /etc/php/$php_version/apache2/php.ini.bak
sed -i 's|;error_log = log/php_error.log|error_log = /var/log/php_errors.log|g' /etc/php/$php_version/apache2/php.ini
touch /var/log/php_errors.log
chmod 666 /var/log/php_errors.log

# Edycja pliku konfiguracyjnego SSH
echo "Konfiguracja SSH"
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
echo "AllowUsers ${allowed_users[*]}" >> /etc/ssh/sshd_config

# Dodanie reguł do firewalla
echo "Dodatnie reguł do firewalla"
for ip in "${allowed_ips[@]}"
do
    ufw allow from $ip to any port 22
done

# Restart Apache
echo "Restart Apache"
systemctl restart apache2

# Restart usługi SSH
echo "Restart SSHD"
systemctl restart sshd

# Restart usługi vsftpd
echo "Restart vsftpd"
systemctl restart vsftpd

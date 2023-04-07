#!/bin/bash

allowed_ips=()
allowed_users=()
dns_addresses=()
# Pobranie wartości od użytkownika i przypisanie jej do zmiennej
read -p $'\e[33mWprowadź użytkownika bez uprawnień root (służy do ograczenia dostępu temu użytkownikowi): \e[0m' USERS

while true
do
    read -p $'\e[32mWprowadź adresy IP z maską z których można się logować (naciśnij ENTER aby zakończyć): \e[0m' value
    if [ -z "$value" ]
    then
        break
    else
        allowed_ips+=("$value")
    fi
done

while true
do
    read -p $'\e[33mWprowadź użytkowników, którzy mogą się logować (naciśnij ENTER aby zakończyć): \e[0m' value
    if [ -z "$value" ]
    then
        break
    else
        allowed_users+=("$value")
    fi
done

while true
do
    read -p $'\e[32mPodaj adresy IP DNSów (naciśnij ENTER aby zakończyć): \e[0m' value
    if [ -z "$value" ]
    then
        break
    else
        dns_addresses+=($value)
    fi
done

read -p $'\e[33mPodaj adres domenowy DNS: \e[0m' domena
read -s -p $'\e[32mPodaj hasło użytkownika root w MySQL: \e[0m' mysql_password


# Ustawienie adresów IP, dla których będzie dostępny serwer
#allowed_ips=("$allowed_ips")

# Ustawienie użytkowników, którzy mają mieć dostęp do serwera
#allowed_users=(allowed_users)

# Dodanie wpisów do pliku /etc/resolv.conf
echo -e "\e[32mDodawanie domeny do pliku /etc/resolv.conf\e[0m"
cat > /etc/resolv.conf <<EOF
search $domena
EOF

# Dodanie wpisów do pliku /etc/resolv.conf
echo -e "\e[32mDodawanie adresów IP do resolv.conf\e[0m"
cat > /etc/resolv.conf <<EOF
search umg.edu.pl
EOF

for dns_address in $dns_addresses; do
    echo "nameserver $dns_address" >> /etc/resolv.conf
done

# Aktualizacja systemu i instalacja narzędzi
echo -e "\e[32mAktulizacja i instalacja niezbędnych narzędzi\e[0m" 
apt-get update >/dev/null 2>&1
apt-get upgrade -y >/dev/null 2>&1
apt-get install htop fail2ban ufw build-essential curl git apache2 mariadb-server mariadb-client php libapache2-mod-php php-cli php-curl php-gd php-mysql php-mbstring php-xml vsftpd -y >/dev/null 2>&1

# Instalacja serwera Apache
echo -e "\e[32mWłączanie Apache\e[0m"
systemctl start apache2 >/dev/null 2>&1
systemctl enable apache2 >/dev/null 2>&1


# Instalacja bazy danych MySQL/MariaDB
echo -e "\e[32mWłączanie MariaDB\e[0m"
systemctl start mariadb >/dev/null 2>&1
systemctl enable mariadb >/dev/null 2>&1

# Wywołanie funkcji mysql_secure_installation z automatycznym wprowadzeniem danych
echo -e "\e[32mZabezpieczanie bazy danych\e[0m"
mysql_secure_installation <<EOF >/dev/null 2>&1

$mysql_password
y
$mysql_password
y
y
y
y

EOF

# Instalacja narzędzi do pracy z plikami FTP
echo -e "\e[32mwłączanie vsftpd\e[0m"
systemctl start vsftpd  >/dev/null 2>&1
systemctl enable vsftpd >/dev/null 2>&1

# Ustawienie opcji chroot_local_user na YES
echo -e "\e[32mKonfiguracja vsftpd\e[0m"
sed -i 's/#chroot_local_user=YES/chroot_local_user=YES/g' /etc/vsftpd.conf
echo "local_root=/home/\$USER" >> /etc/vsftpd.conf
echo "write_enable=YES" >> /etc/vsftpd.conf

# Konfiguracja Fail2ban
echo -e "\e[32mKonfiguracja Fail2ban\e[0m"
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sed -i 's/bantime = 10m/bantime = 1h/g' /etc/fail2ban/jail.local
sed -i 's/maxretry = 5/maxretry = 3/g' /etc/fail2ban/jail.local
systemctl enable fail2ban >/dev/null 2>&1
systemctl start fail2ban >/dev/null 2>&1

# Konfiguracja zasad firewalla
echo -e "\e[32mKonfiguracja firewalla\e[0m"
ufw default deny incoming 
ufw default allow outgoing 
ufw allow ssh 
ufw allow http
ufw allow https 
ufw enable

# Wyłączenie niepotrzebnych modułów Apache
echo -e "\e[32mWyłączanie modułów Apache\e[0m"
a2dismod --quiet status --force >/dev/null 2>&1
a2dismod --quiet autoindex --force >/dev/null 2>&1
a2dismod --quiet cgi --force >/dev/null 2>&1
a2dismod --quiet negotiation --force >/dev/null 2>&1
a2dismod --quiet userdir --force >/dev/null 2>&1

# Zablokowanie dostępu do plików .htaccess
echo -e "\e[32mZablokowanie dostępu do plików .htaccess\e[0m"
echo "<Files .htaccess>" > /etc/apache2/conf-available/htaccess.conf
echo "Order allow,deny" >> /etc/apache2/conf-available/htaccess.conf
echo "Deny from all" >> /etc/apache2/conf-available/htaccess.conf
echo "</Files>" >> /etc/apache2/conf-available/htaccess.conf
a2enconf htaccess > /dev/null

# Sprawdzenie, czy użytkownik www-data istnieje
echo -e "\e[32mKonfiguracja użytkownika www-data\e[0m"
if id -u www-data >/dev/null 2>&1; then
    usermod --shell /usr/sbin/nologin www-data >/dev/null 2>&1
else
    useradd --no-create-home --shell /usr/sbin/nologin www-data >/dev/null 2>&1
fi

# Zmiana uprawnień dla plików i katalogów
echo -e "\e[32mZmiana uprawnień do plików i katalogów\e[0m"
chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 750 {} \;
find /var/www/html -type f -exec chmod 640 {} \;

# Utworzenie osobnego pliku logów dla Apache
echo -e "\e[32mUtworznie osobnego pliku do logów dla Apache\e[0m"
cp /etc/apache2/conf-available/other-vhosts-access-log.conf /etc/apache2/conf-available/other-vhosts-access-log.conf.bak
sed -i 's|CustomLog /var/log/apache2/other_vhosts_access.log vhost_combined|#CustomLog /var/log/apache2/other_vhosts_access.log vhost_combined|g' /etc/apache2/conf-available/other-vhosts-access-log.conf
echo "CustomLog /var/log/apache2/access.log combined" >> /etc/apache2/conf-available/other-vhosts-access-log.conf

# Utworzenie osobnego pliku logów dla PHP
echo -e "\e[32mUtworzenie osobnego pliku logów dla PHP\e[0m"
php_version=$(php -r "echo substr(PHP_VERSION, 0, 3);")
cp /etc/php/$php_version/apache2/php.ini /etc/php/$php_version/apache2/php.ini.bak
sed -i 's|;error_log = log/php_error.log|error_log = /var/log/php_errors.log|g' /etc/php/$php_version/apache2/php.ini
touch /var/log/php_errors.log
chmod 666 /var/log/php_errors.log

# Edycja pliku konfiguracyjnego SSH
echo -e "\e[32mKonfiguracja SSH\e[0m"
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
echo -e "\e[32mDodatnie reguł do firewalla\e[0m"
for ip in "${allowed_ips[@]}"
do
    ufw allow from $ip to any port 22
done

# Restart Apache
echo -e "\e[32mRestart Apache\e[0m"
systemctl restart apache2

# Restart usługi SSH
echo -e "\e[32mRestart SSHD\e[0m"
systemctl restart sshd

# Restart usługi vsftpd
echo -e "\e[32mRestart vsftpd\e[0m"
systemctl restart vsftpd

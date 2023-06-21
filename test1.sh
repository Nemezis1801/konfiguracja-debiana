#!/bin/bash

# Tworzenie menu wyboru pakietów
CHOICES=$(whiptail --title "Menu wyboru pakietow" --checklist \
"Zaznacz pakiety do instalacji" 16 60 10 \
"apache2" "" OFF \
"nginx" "" OFF \
"mariadb-server" "" OFF \
"php" "" OFF \
"python3" "" OFF \
"fail2ban" "" OFF \
"ufw" "" OFF \
"git" "" OFF \
"curl" "" OFF \
"htop" "" OFF 3>&1 1>&2 2>&3)

# Wyjscie ze skryptu, jesli uzytkownik anuluje wybor
[ $? != 0 ] && echo "Anulowano wybor pakietow." && exit 1

# Przetwarzanie wyborow uzytkownika
selected_packages=$(echo $CHOICES | tr -d '"' | sed 's/ /,/g')

# Sprawdzenie, czy PHP jest wybrany i dodanie zaleznosci PHP
if [[ $selected_packages == *"php"* ]]; then
    selected_packages+=",libapache2-mod-php,php-cli,php-curl,php-gd,php-mysql,php-mbstring,php-xml"
fi

# Konfiguracja DNS
if (whiptail --title "Konfiguracja DNS" --yesno "Czy chcesz wprowadzic wlasne ustawienia DNS? \n
Jezeli wybierzesz nie to zostana uzyte domyslne ustawienia" 10 60) then
    domain=$(whiptail --inputbox "Podaj adres domeny" 10 60 3>&1 1>&2 2>&3)
    while true; do
        ip=$(whiptail --inputbox "Podaj adres IP nameservera (lub zostaw puste, aby zakonczyc)" 10 60 3>&1 1>&2 2>&3)
        if [ -z "$ip" ]; then
            break
        else
            dns_addresses+=($ip)
        fi
    done
else
    domain="example.com"
    dns_addresses=("192.168.0.1" "192.168.0.2" "192.168.0.3")
fi

# Sprawdzenie, czy MariaDB jest wybrana
if [[ $selected_packages == *"mariadb-server"* ]]; then
    if (whiptail --title "Zabezpiecz MariaDB" --yesno "Czy chcesz teraz zabezpieczyc MariaDB?" 10 60) then
        mysql_password=$(whiptail --passwordbox "Podaj haslo roota dla MariaDB" 10 60 3>&1 1>&2 2>&3)
        secure_mariadb=true
    else
        secure_mariadb=false
    fi
fi

# Aktualizacja systemu i instalacja wybranych pakietów
echo "Trwa instalacja pakietów"
apt-get update > /dev/null 2>&1 && apt-get install -y $(echo $selected_packages | tr ',' ' ') > /dev/null 2>&1

# Konfiguracja DNS
echo "search $domain" > /etc/resolv.conf
for dns_address in "${dns_addresses[@]}"; do
    echo "nameserver $dns_address" >> /etc/resolv.conf
done

# Startowanie i włączanie usług dla wybranych pakietów
for package in $(echo $selected_packages | tr ',' ' '); do
    systemctl enable $package > /dev/null 2>&1
    systemctl start $package > /dev/null 2>&1
done

# Konfiguracja Fail2Ban, jeśli został wybrany
if [[ $selected_packages == *"fail2ban"* ]]; then
    if (whiptail --title "Konfiguracja Fail2Ban" --yesno "Czy chcesz wprowadzic podstawowa konfiguracje Fail2Ban?" 10 60) then
        cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
        sed -i 's/bantime  = 10m/bantime = 1h/g' /etc/fail2ban/jail.local
        sed -i 's/maxretry = 5/maxretry = 3/g' /etc/fail2ban/jail.local
        systemctl enable fail2ban > /dev/null 2>&1
        systemctl start fail2ban > /dev/null 2>&1
    fi
fi

# Konfiguracja UFW, jeśli został wybrany
if [[ $selected_packages == *"ufw"* ]]; then
    if (whiptail --title "Konfiguracja UFW" --yesno "Czy chcesz wprowadzic podstawowa konfiguracje UFW?" 10 60) then
        ufw default deny incoming  > /dev/null 2>&1
        ufw default allow outgoing > /dev/null 2>&1
        ufw allow http > /dev/null 2>&1
        ufw allow https > /dev/null 2>&1
        ufw enable -y > /dev/null 2>&1
        systemctl enable ufw
        sed -i 's/ENABLED=no/ENABLED=yes/g' /etc/ufw/ufw.conf
        sed -i 's/IPV6=yes/IPV6=no/g' /etc/default/ufw
        while true; do
            ip=$(whiptail --inputbox "Podaj adres IP dozwolony dla portu 22 - mozliwe uzycie maski (lub zostaw puste, aby zakonczyc)" 10 60 3>&1 1>&2 2>&3)
            if [ -z "$ip" ]; then
                break
            else
                ufw allow from $ip to any port 22
            fi
        done
    fi
fi

# Wyłączanie niepotrzebnych modułów Apache, jeśli Apache został wybrany
if [[ $selected_packages == *"apache2"* ]]; then
    if (whiptail --title "Konfiguracja Apache" --yesno "Czy chcesz wylaczyc niepotrzebne moduly Apache?" 10 60) then
        a2dismod --quiet status --force > /dev/null 2>&1
        a2dismod --quiet autoindex --force > /dev/null 2>&1
        a2dismod --quiet cgi --force > /dev/null 2>&1
        a2dismod --quiet negotiation --force > /dev/null 2>&1
        a2dismod --quiet userdir --force > /dev/null 2>&1
    fi
    cp /etc/apache2/conf-available/other-vhosts-access-log.conf /etc/apache2/conf-available/other-vhosts-access-log.conf.bak
    sed -i 's|CustomLog /var/log/apache2/other_vhosts_access.log vhost_combined|#CustomLog /var/log/apache2/other_vhosts_access.log vhost_combined|g' /etc/apache2/conf-available/other-vhosts-access-log.conf
    echo "CustomLog /var/log/apache2/access.log combined" >> /etc/apache2/conf-available/other-vhosts-access-log.conf
    echo "<Files .htaccess>" > /etc/apache2/conf-available/htaccess.conf
    echo "Order allow,deny" >> /etc/apache2/conf-available/htaccess.conf
    echo "Deny from all" >> /etc/apache2/conf-available/htaccess.conf
    echo "</Files>" >> /etc/apache2/conf-available/htaccess.conf
    a2enconf htaccess > /dev/null
fi

# Konfiguracja PHP, jeśli PHP został wybrany
if [[ $selected_packages == *"php"* ]]; then
    echo "Utworzenie osobnego pliku logów dla PHP"
    php_version=$(php -r "echo substr(PHP_VERSION, 0, 3);")
    cp /etc/php/$php_version/apache2/php.ini /etc/php/$php_version/apache2/php.ini.bak
    sed -i 's|;error_log = log/php_error.log|error_log = /var/log/php_errors.log|g' /etc/php/$php_version/apache2/php.ini
    touch /var/log/php_errors.log
    chmod 666 /var/log/php_errors.log
fi

# Zabezpieczanie SSH, jeśli użytkownik zdecyduje się na to
if (whiptail --title "Zabezpiecz SSH" --yesno "Czy chcesz teraz zabezpieczyc SSH?" 10 60) then
    sed -i 's/#PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
    sed -i 's/#MaxAuthTries 6/MaxAuthTries 3/' /etc/ssh/sshd_config
    sed -i 's/#LoginGraceTime 2m/LoginGraceTime 1m/' /etc/ssh/sshd_config
    sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords no/' /etc/ssh/sshd_config
    sed -i 's/Subsystem/#Subsystem/' /etc/ssh/sshd_config
    sed -i 's/#ServerSignature Off/ServerSignature Off/' /etc/apache2/conf-enabled/security.conf
    sed -i 's/#TraceEnable Off/TraceEnable Off/' /etc/apache2/conf-enabled/security.conf
    sed -i 's/TraceEnable On/#TraceEnable On/' /etc/apache2/conf-enabled/security.conf
    sed -i 's/ServerSignature On/#ServerSignature On/' /etc/apache2/conf-enabled/security.conf
    allowed_users=$(whiptail --inputbox "Podaj nazwy uzytkownikow, ktorzy moga sie laczyc przez SSH (oddzielone przecinkami)" 10 60 3>&1 1>&2 2>&3)
    echo "AllowUsers ${allowed_users//,/ }" >> /etc/ssh/sshd_config
fi

if id -u www-data >/dev/null 2>&1; then
    usermod --shell /usr/sbin/nologin www-data >/dev/null 2>&1
else
    useradd --no-create-home --shell /usr/sbin/nologin www-data >/dev/null 2>&1
fi

chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 750 {} \;
find /var/www/html -type f -exec chmod 640 {} \;


# Zabezpieczenie bazy danych MariaDB, jesli zostalo wybrane
if [ "$secure_mariadb" = true ]; then
    mysql_secure_installation <<EOF >/dev/null 2>&1
$mysql_password
y
$mysql_password
y
y
y
y
EOF
fi


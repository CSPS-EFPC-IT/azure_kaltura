#!/bin/bash
# ------------------------------------------------------------------
# cedric.guindon@canada.ca
#
# kaltura_install
# This script will automate the installation of the Kaltura CE application
# ------------------------------------------------------------------

VERSION=0.1.0
SUBJECT=1234567890
USAGE="Usage: command -ihv args\n******************\nTo start the script:\nsh kaltura_install.sh arg1 arg2 arg3 arg4 arg5"

# --- Options processing -------------------------------------------
if [ $# == 0 ] ; then
    echo $USAGE
    exit 1;
fi

while getopts ":i:vh" optname
  do
    case "$optname" in
      "v")
        echo "Version $VERSION"
        exit 0;
        ;;
      "i")
        echo "-i argument: $OPTARG"
        ;;
      "h")
        echo -e $USAGE
        exit 0;
        ;;
      "?")
        echo "Unknown option $OPTARG"
        exit 0;
        ;;
      ":")
        echo "No argument value for option $OPTARG"
        exit 0;
        ;;
      *)
        echo "Unknown error while processing options"
        exit 0;
        ;;
    esac
  done

shift $(($OPTIND - 1))

FQDN=$1
ADMINEMAIL=$2
ADMINPASSWORD=$3
ROOTPASSWORD=$4
KALTDBPASSWORD=$5

# --- Locks -------------------------------------------------------
LOCK_FILE=/tmp/$SUBJECT.lock
if [ -f "$LOCK_FILE" ]; then
echo "Script is already running"
exit
fi

trap "rm -f $LOCK_FILE" EXIT
touch $LOCK_FILE

# --- Body --------------------------------------------------------

##### Updating the OS
yum -y update

##### Turning iptables off
iptables -F
service iptables stop
chkconfig iptables off

##### Setting selinux to permissive
setenforce permissive
sed -i 's/enforcing/permissive/' /etc/selinux/config

##### Installing the Kaltura repo
rpm -ihv http://installrepo.kaltura.org/releases/kaltura-release.noarch.rpm
# Fixing the releasever in the repo
sed -i 's/$releasever/7/' /etc/yum.repos.d/kaltura.repo

##### Installing and Configuring mariadb
yum -y install mariadb-server
yum -y install expect
service mariadb start

SECURE_MYSQL=$(expect -c "
set timeout 10
spawn mysql_secure_installation
expect \"Enter current password for root (enter for none):\"
send \"\r\"
expect \"Set root password?\"
send \"y\r\"
expect \"New password:\"
send \"$ROOTPASSWORD\r\"
expect \"Re-enter new password:\"
send \"$ROOTPASSWORD\r\"
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

echo "$SECURE_MYSQL"

##### Installing kaltura
yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum -y update
yum -y install kaltura-server

##### Moving Kaltura folder to the datadisk and creating a symbolic link
mv /opt/kaltura/ /mnt/resource/kaltura/
ln -s /mnt/resource/kaltura/ /opt/kaltura

##### Gathering the SSL certificates
yum -y install certbot
service httpd stop
certbot certonly --standalone -n --agree-tos -m $ADMINEMAIL -d $FQDN

##### Configuring httpd SSL
sed -i "s/\/etc\/pki\/tls\/certs\/localhost.crt/\/etc\/letsencrypt\/live\/$FQDN\/cert.pem/" /etc/httpd/conf.d/ssl.conf
sed -i "s/\/etc\/pki\/tls\/private\/localhost.key/\/etc\/letsencrypt\/live\/$FQDN\/privkey.pem/" /etc/httpd/conf.d/ssl.conf
sed -i "s/\/etc\/pki\/tls\/certs\/server-chain.crt/\/etc\/letsencrypt\/live\/$FQDN\/fullchain.pem/" /etc/httpd/conf.d/ssl.conf
sed -i "s/#SSLCertificateChainFile/SSLCertificateChainFile/" /etc/httpd/conf.d/ssl.conf

# Adding an entry in the hosts file so kaltura can install correctly
echo "127.0.0.1 $FQDN" >> /etc/hosts

##### Restarting services
service httpd restart
service memcached restart
chkconfig memcached on

##### Configuring kaltura
rm -rf /mnt/configall.ans

echo "TIME_ZONE=\"America/Toronto\"" > /mnt/configall.ans
echo "KALTURA_FULL_VIRTUAL_HOST_NAME=\"$FQDN\"" >> /mnt/configall.ans
echo "KALTURA_VIRTUAL_HOST_PORT=\"443\"" >> /mnt/configall.ans
echo "KALTURA_VIRTUAL_HOST_NAME=\"$FQDN\"" >> /mnt/configall.ans
echo "DB1_HOST=\"127.0.0.1\"" >> /mnt/configall.ans
echo "DB1_PORT=\"3306\"" >> /mnt/configall.ans
echo "DB1_PASS=\"$KALTDBPASSWORD\"" >> /mnt/configall.ans
echo "DB1_NAME=\"kaltura\"" >> /mnt/configall.ans
echo "DB1_USER=\"kaltura\"" >> /mnt/configall.ans
echo "SERVICE_URL=\"https://$FQDN\"" >> /mnt/configall.ans
echo "SPHINX_SERVER1=\"127.0.0.1\"" >> /mnt/configall.ans
echo "SPHINX_SERVER2=\"127.0.0.1\"" >> /mnt/configall.ans
echo "SPHINX_DB_HOST=\"127.0.0.1\"" >> /mnt/configall.ans
echo "SPHINX_DB_PORT=\"3306\"" >> /mnt/configall.ans
echo "DWH_HOST=\"127.0.0.1\"" >> /mnt/configall.ans
echo "DWH_PORT=\"3306\"" >> /mnt/configall.ans
echo "DWH_PASS=\"$KALTDBPASSWORD\"" >> /mnt/configall.ans
echo "ADMIN_CONSOLE_ADMIN_MAIL=\"$ADMINEMAIL\"" >> /mnt/configall.ans
echo "ADMIN_CONSOLE_PASSWORD=\"$ADMINPASSWORD\"" >> /mnt/configall.ans
echo "CDN_HOST=\"$FQDN\"" >> /mnt/configall.ans
echo "KALTURA_VIRTUAL_HOST_PORT=\"80\"" >> /mnt/configall.ans
echo "SUPER_USER=\"root\"" >> /mnt/configall.ans
echo "SUPER_USER_PASSWD=\"$ROOTPASSWORD\"" >> /mnt/configall.ans
echo "ENVIRONMENT_NAME=\"Kaltura Video Platform\"" >> /mnt/configall.ans
echo "CONFIG_CHOICE=\"0\"" >> /mnt/configall.ans
echo "DWH_PASS=\"$KALTDBPASSWORD\"" >> /mnt/configall.ans
echo "PROTOCOL=\"http\"" >> /mnt/configall.ans
echo "PRIMARY_MEDIA_SERVER_HOST=\"$FQDN\"" >> /mnt/configall.ans
echo "USER_CONSENT=\"0\"" >> /mnt/configall.ans
echo "VOD_PACKAGER_HOST=\"$FQDN\"" >> /mnt/configall.ans
echo "VOD_PACKAGER_PORT=\"88\"" >> /mnt/configall.ans
echo "IP_RANGE=\"0.0.0.0-255.255.255.255\"" >> /mnt/configall.ans
echo "WWW_HOST=\"$FQDN:443\"" >> /mnt/configall.ans
echo "IS_SSL=\"Y\"" >> /mnt/configall.ans
echo "RED5_HOST=\"127.0.0.1\"" >> /mnt/configall.ans
echo "IS_NGINX_SSL=\"Y\"" >> /mnt/configall.ans
echo "SSL_CERT=\"/etc/letsencrypt/live/$FQDN/fullchain.pem\"" >> /mnt/configall.ans
echo "SSL_KEY=\"/etc/letsencrypt/live/$FQDN/privkey.pem\"" >> /mnt/configall.ans
echo "VOD_PACKAGER_SSL_PORT=8443" >> /mnt/configall.ans
echo "RTMP_PORT=1935" >> /mnt/configall.ans
echo "CRT_FILE=\"/etc/letsencrypt/live/$FQDN/cert.pem\"" >> /mnt/configall.ans
echo "KEY_FILE=\"/etc/letsencrypt/live/$FQDN/privkey.pem\"" >> /mnt/configall.ans
echo "CHAIN_FILE=\"/etc/letsencrypt/live/$FQDN/fullchain.pem\"" >> /mnt/configall.ans

sh /opt/kaltura/bin/kaltura-mysql-settings.sh
sh /opt/kaltura/bin/kaltura-config-all.sh /mnt/configall.ans

##### Removing the custom entry in hosts
sed -i '$ d' /etc/hosts

##### Configuring the SSL settings for httpd and nginx
sed -i "s/<VirtualHost $FQDN>/<VirtualHost *:443>/" /etc/httpd/conf.d/zzzkaltura.ssl.conf

mysql -u root -p$ROOTPASSWORD -e "select url from kaltura.delivery_profile where id in (1001,1002,1003)\G"
mysql -u root -p$ROOTPASSWORD -e "UPDATE kaltura.delivery_profile SET url = REPLACE(url, '$FQDN:88', '$FQDN:8443') WHERE url like '$FQDN:88/%'"
mysql -u root -p$ROOTPASSWORD -e "select url from kaltura.delivery_profile where id in (1001,1002,1003)\G"

sed -i "s/http:\/\/kalapi\//https:\/\/kalapi\//" /etc/nginx/conf.d/kaltura.conf

##### Restarting web services
service httpd restart
service kaltura-nginx restart

# -----------------------------------------------------------------
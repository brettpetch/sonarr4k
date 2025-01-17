#!/bin/bash
. /etc/swizzin/sources/globals.sh
. /etc/swizzin/sources/functions/utils

# Script by @ComputerByte
# For Sonarr 4K Installs
#shellcheck=SC1017

# Log to Swizzin.log
export log=/root/logs/swizzin.log
touch $log
# Set variables
user=$(_get_master_username)

echo_progress_start "Making data directory and owning it to ${user}"
mkdir -p "/home/$user/.config/sonarr4k"
chown -R "$user":"$user" /home/$user/.config
echo_progress_done "Data Directory created and owned."

echo_progress_start "Installing systemd service file"
cat >/etc/systemd/system/sonarr4k.service <<-SERV
# This file is owned by the sonarr package, DO NOT MODIFY MANUALLY
# Instead use 'dpkg-reconfigure -plow sonarr' to modify User/Group/UMask/-data
# Or use systemd built-in override functionality using 'systemctl edit sonarr'
[Unit]
Description=Sonarr Daemon
After=network.target

[Service]
User=${user}
Group=${user}
UMask=0002

Type=simple
ExecStart=/usr/bin/mono --debug /opt/Sonarr/Sonarr.exe -nobrowser -data=/home/${user}/.config/sonarr4k
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
SERV
echo_progress_done "Sonarr 4K service installed"

# This checks if nginx is installed, if it is, then it will install nginx config for sonarr4k
if [[ -f /install/.nginx.lock ]]; then
    echo_progress_start "Installing nginx config"
    cat >/etc/nginx/apps/sonarr4k.conf <<-NGX
    location /sonarr4k {
        proxy_pass        http://127.0.0.1:8882/sonarr4k;
        proxy_set_header Host \$proxy_host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
        auth_basic "What's the password?";
        auth_basic_user_file /etc/htpasswd.d/htpasswd.${user};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$http_connection;
    }
NGX
    # Reload nginx
    systemctl reload nginx
    echo_progress_done "Nginx config applied"
fi

echo_progress_start "Generating configuration"
# Start sonarr to config
systemctl stop sonarr.service >>$log 2>&1
systemctl enable --now sonarr4k.service >>$log 2>&1
sleep 20
# Stop to change port and append baseurl
systemctl stop sonarr4k.service >>$log 2>&1
sleep 20
systemctl start sonarr.service >>$log 2>&1
sed -i "s/8989/8882/g" /home/$user/.config/sonarr4k/config.xml >>$log 2>&1
sed -i "s/<UrlBase><\/UrlBase>/<UrlBase>\/sonarr4k<\/UrlBase>/g" /home/$user/.config/sonarr4k/config.xml >>$log 2>&1
echo_progress_done "Done generating config."
sleep 20

echo_progress_start "Patching panel."
systemctl start sonarr4k.service >>$log 2>&1
#Install Swizzin Panel Profiles
if [[ -f /install/.panel.lock ]]; then
    cat <<EOF >>/opt/swizzin/core/custom/profiles.py
class sonarr4k_meta:
    name = "sonarr4k"
    pretty_name = "Sonarr 4K"
    baseurl = "/sonarr4k"
    systemd = "sonarr4k"
    check_theD = True
    img = "sonarr"
class sonarr_meta(sonarr_meta):
    check_theD = True
EOF
fi
touch /install/.sonarr4k.lock >>$log 2>&1
echo_progress_done "Panel patched."
systemctl restart panel >>$log 2>&1
echo_progress_done "Done."

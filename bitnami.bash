#!/bin/bash
function enabled_ssh_server() {
	ssh_status=($(sudo systemctl is-active --quiet ssh && echo active))
	if [ "$ssh_status" != "active" ] ;then
		echo "Activate the SSH server"
		sudo rm -f /etc/ssh/sshd_not_to_be_run
		sudo systemctl enable ssh
		sudo systemctl start ssh
	else 
		echo "SSH server is active"
	fi
}

function enabled_ssh_pass() {
	enabled_ssh_server
	sshd_config_back=/etc/ssh/sshd_config.bak
	if [ ! -f $sshd_config_back ] ;then
		echo "Configure password-based SSH authentication"
		sudo cp /etc/ssh/sshd_config $sshd_config_back
		sudo sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config
		sudo /etc/init.d/ssh force-reload
		sudo /etc/init.d/ssh restart
	else
		echo "SSH configuration already exists"
	fi
}

declare APP_DIR_PATH

function create_app_dir() {
	if [ -z "$APP_DIR_PATH" ] ;then
		read -p 'Please Enter Path:' -r r1
		if [ -z "$r1" ] ;then 
			default_path=/opt/bitnami/myapp
			echo "The path was not established, default path was set: $default_path"
			APP_DIR_PATH="$default_path"
		else
			APP_DIR_PATH="$r1"
		fi
	fi
	
	if [ ! -d $APP_DIR_PATH ] ;then
		echo "Create directory PHP Application"
		sudo mkdir -p $APP_DIR_PATH
		sudo chown -R bitnami:daemon $APP_DIR_PATH
		sudo chmod -R g+w $APP_DIR_PATH
	else	
		echo "PHP application directory already exists"
	fi
}

function create_app_php() {
	$"create_app_dir"
	myapp_vhost_conf=/opt/bitnami/apache/conf/vhosts/myapp-vhost.conf 
	if [ ! -f $myapp_vhost_conf ] ;then
		echo "Create a custom PHP application"
		vhost="<VirtualHost 127.0.0.1:80 _default_:80>\n"
		vhost+="ServerAlias *\n"
		vhost+="DocumentRoot $APP_DIR_PATH\n"
		vhost+="<Directory \"$APP_DIR_PATH\">\n"
		vhost+="Options -Indexes +FollowSymLinks -MultiViews\n"
		vhost+="AllowOverride All\n"
		vhost+="Require all granted\n"
		vhost+="</Directory>\n"
		vhost+="</VirtualHost>"
		#sudo touch $myapp_vhost_conf
		#sudo sed -i -e $'$a\\'"$vhost" "$myapp_vhost_conf"
		#sudo sed -i "$ a\$vhost" "$myapp_vhost_conf"
		sudo printf "`echo \"$vhost\"`" > "$myapp_vhost_conf"
		sudo /opt/bitnami/ctlscript.sh restart apache
	else
		echo "PHP application virtual host already exists, updating document root to $APP_DIR_PATH"
		sudo sed -i "s+.*DocumentRoot.*+DocumentRoot $APP_DIR_PATH+g" "$myapp_vhost_conf"
		sudo sed -i "s+.*<Directory.*+<Directory \"$APP_DIR_PATH\">+g" "$myapp_vhost_conf"
		sudo /opt/bitnami/ctlscript.sh restart apache
	fi
}

function share_app_dir() {
	$"create_app_dir"
	
	read -p 'Please Enter Name:' -r r1
	if [ -z "$r1" ] ;then 
		default_name="myapp"
		echo "The Name was not established, default name was set: $default_name"
		name="$default_name"
	else
		name="$r1"
	fi
	
	read -p 'Please Enter Comment:' -r r2
	if [ -z "$r2" ] ;then 
		default_comment="My App"
		echo "The Comment was not established, default comment was set: $default_comment"
		comment="$default_comment"
	else
		comment="$r2"
	fi
	
	smb_conf_back=/etc/samba/smb.conf.bak
	if [ ! -f $smb_conf_back ] ;then
		echo "Share custom application using CIFS"
		#sudo apt-get update
		sudo apt install -y samba samba-common
		sudo cp /etc/samba/smb.conf $smb_conf_back
		str="[$name]\n"
		str+="comment = $comment\n"
		str+="path = $APP_DIR_PATH\n"
		str+="browseable = yes\n"
		str+="read only = no\n"
		str+="guest ok = no\n"
		str+="valid users = bitnami\n"
		str+="create mask 0777\n"
		str+="directory mask = 0777"
		sudo sed -i -e $'$a\\\n'"$str" /etc/samba/smb.conf

		(echo "bitnami"; echo "bitnami") | sudo smbpasswd -s -a bitnami
		sudo service smbd restart

		firewall=($(sudo which nft >/dev/null && echo nftables || echo ufw))
		echo "$firewall is enabled in this system, adding rules"
		if [ "$firewall" == "nftables" ] ;then
			sudo cp /etc/nftables.conf /etc/nftables.conf.bak
			sudo sed -i "s/tcp dport { 22, 80, 443 } accept/tcp dport { 22, 80, 443, 137, 138, 139, 445 } accept/g" /etc/nftables.conf
			sudo systemctl restart nftables.service
		elif [ "$firewall" == "ufw" ]
		then
			sudo ufw allow 137:139,445/tcp
		else
			sudo apt-get -y install ufw
			sudo ufw enable
			sudo ufw allow 137:139,445/tcp
		fi
	else
		echo "Custom application CIFS configuration already exists"
	fi
}

options=(
"Activate the SSH server;enabled_ssh_server"
"Configure password-based SSH authentication;enabled_ssh_pass"
"Create A Custom PHP Application;create_app_php"
"Share A Custom Application using CIFS;share_app_dir"
)

menu() {
    clear
    echo "Avaliable options:"
    for i in ${!options[@]}; do 
        printf "%3d%s) %s\n" $((i+1)) "${choices[i]:- }" "${options[i]%;*}"
    done
    [[ "$msg" ]] && echo "$msg"; :
}

prompt="Check an option (again to uncheck, ENTER when done, Q to quit): "
while menu && read -rp "$prompt" num && [[ "$num" ]]; do
	case $num in
		q|Q) exit 0 ;;
	esac
    [[ "$num" != *[![:digit:]]* ]] &&
    (( num > 0 && num <= ${#options[@]} )) ||
    { msg="Invalid option: $num"; continue; }
    ((num--)); msg="" # msg="${options[num]} was ${choices[num]:+un}checked"
    [[ "${choices[num]}" ]] && choices[num]="" || choices[num]="+"
done

printf "You selected"; msg=" nothing"
for i in ${!options[@]}; do 
    [[ "${choices[i]}" ]] && { printf " %s" "${options[i]%;*}"; msg=""; }
done
echo "$msg"

if [ "$msg" != " nothing" ] ;then
	printf 'Do you wish to execute this program (y/n)? '
	read answer
	if [ "$answer" != "${answer#[Yy]}" ] ;then 
		for i in ${!options[@]}; do 
			[[ "${choices[i]}" == "+" ]] && selected=true || selected=false
			if [ "$selected" == true ] ;then
				"${options[i]##*;}"
			fi	
		done
	else
		exit 0
	fi
fi
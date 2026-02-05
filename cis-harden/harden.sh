#!/bin/bash

#
# This script is to harden Kairos, use in the CanvOS Dockerfile
# Benchmark targeted: CIS Ubuntu Linux 22.04 LTS Benchmark Level 2 - Server
# Based on CIS Benchmark v2.0.0, released 2024-03-28
#
# This script is designed to run during ISO build (not on a live system)
# It writes configuration files that will be applied at boot time
#


root_dir="$( cd "$( dirname "$0" )" && pwd )"
echo Root dir "$root_dir"


##########################################################################
#  Check for exit status and print error msg
##########################################################################
check_error()
{
	status=$1
	msg=$2
	exit_status=$3

	if [[ ${status} -ne 0 ]]; then
		echo -e "\033[31m       - ${msg} \033[0m"
		exit "${exit_status}"
	fi

	return 0
}


##########################################################################
#  Update the config files with specified values for hardening
##########################################################################
update_config_files() {
	search_str="$1"
	append_str="$2"
	config_file="$3"

	if [[ ! -f ${config_file} ]]; then
		check_error 1 "File ${config_file} not found"
	fi

	sed -i "s/^\($search_str.*\)$/#\1/"  "${config_file}"
	check_error $? "Failed commenting config value $search_str." 1

	echo "$append_str" >> "${config_file}"
	check_error $? "Failed appending config value $append_str" 1

	return 0
}


##########################################################################
#  Determine the Operating system
##########################################################################
get_os() {
	if [ -f /etc/os-release ]; then
		. /etc/os-release
		OS=$NAME
		VER=$VERSION_ID
	elif type lsb_release >/dev/null 2>&1; then
		OS=$(lsb_release -si)
		VER=$(lsb_release -sr)
	elif [ -f /etc/lsb-release ]; then
		. /etc/lsb-release
		OS=$DISTRIB_ID
		VER=$DISTRIB_RELEASE
	elif [ -f /etc/debian_version ]; then
		OS=Debian
		VER=$(cat /etc/debian_version)
	elif [ -f /etc/SuSe-release ]; then
		OS=Suse
	elif [ -f /etc/centos-release ]; then
		OS='CentOS Linux'
		VER=$(cat /etc/centos-release | sed 's/.*\( [0-9][^ ]\+\) .*/\1/')
	elif [ -f /etc/rocky-release ]; then
		OS='Rocky Linux'
		VER=$(cat /etc/rocky-release | sed 's/.*\( [0-9][^ ]\+\) .*/\1/')
	elif [ -f /etc/redhat-release ]; then
		OS='Red Hat Enterprise Linux'
		VER=$(cat /etc/redhat-release | sed 's/.*\( [0-9][^ ]\+\) .*/\1/')
	else
		OS=$(uname -s)
		VER=$(uname -r)
	fi

	if [[ $OS =~ 'Red Hat' ]]; then
		OS_FLAVOUR="rhel"
	elif [[ $OS =~ 'CentOS' ]]; then
		OS_FLAVOUR="centos"
	elif [[ $OS =~ 'Rocky' ]]; then
			OS_FLAVOUR="centos"
	elif [[ $OS =~ 'Ubuntu' ]]; then
		OS_FLAVOUR="ubuntu"
	else
		OS_FLAVOUR="linux"
	fi

	return 0
}


##########################################################################
#  Upgrade OS packages
##########################################################################
upgrade_packages() {
	if [[ ${OS_FLAVOUR} == "ubuntu" ]]; then
		export DEBIAN_FRONTEND=noninteractive
		apt-get update
		apt-get -y upgrade
		check_error $? "Failed upgrading packages" 1
		# CIS 1.3.1 - Install AIDE for file integrity monitoring
		# CIS 5.5.1 - Install vlock for screen locking
		DEBIAN_FRONTEND=noninteractive apt-get install -y auditd apparmor apparmor-utils libpam-pwquality aide vlock
		if  $? -ne 0 ; then
			echo 'deb http://archive.ubuntu.com/ubuntu focal main restricted' > /etc/apt/sources.list.d/repotmp.list
			apt-get update
			DEBIAN_FRONTEND=noninteractive apt-get install -y auditd apparmor apparmor-utils libpam-pwquality aide vlock
			check_error $? "Failed installing audit packages" 1
			rm -f /etc/apt/sources.list.d/repotmp.list
			apt-get update
		fi

		# CIS 1.3.2 - Initialize AIDE database
		echo "Initializing AIDE database..."
		if [[ -x /usr/sbin/aideinit ]]; then
			/usr/sbin/aideinit -y -f 2>/dev/null || true
		fi

		# CIS 1.7.1.2 - Enable AppArmor
		echo "Enabling AppArmor..."
		systemctl enable apparmor 2>/dev/null || true

		# CIS 4.2.1.2 - Enable rsyslog
		echo "Enabling rsyslog..."
		systemctl enable rsyslog 2>/dev/null || true
	fi

	if [[ ${OS_FLAVOUR} == "centos" ]]; then
		yum -y update
		yum install -y audit libpwquality
		check_error $? "Failed upgrading packages" 1
		yum clean all
	fi

	if [[ ${OS_FLAVOUR} == "rhel" ]]; then
		yum -y update
		yum install -y audit libpwquality
		check_error $? "Failed upgrading packages" 1
		yum clean all
	fi

	# Placeholder for supporting other linux OS
	if [[ ${OS_FLAVOUR} == "linux" ]]; then
		test 1 -eq 2
		check_error $? "OS not supported" 1
	fi

	return 0
}


##########################################################################
#  Harden Sysctl based parameters
##########################################################################
harden_sysctl() {
	config_file='/etc/sysctl.conf'

	echo "Harden sysctl parameters"
	echo "" >> ${config_file}
	#Disabling IP forward related hardening as it is needed for k8s
	# update_config_files 'net.ipv4.ip_forward' 'net.ipv4.ip_forward=0' ${config_file}
	# update_config_files 'net.ipv4.conf.all.forwarding' 'net.ipv4.conf.all.forwarding=0' ${config_file}
	# update_config_files 'net.ipv4.conf.all.mc_forwarding' 'net.ipv4.conf.all.mc_forwarding=0' ${config_file}

	update_config_files 'net.ipv4.conf.all.send_redirects' 'net.ipv4.conf.all.send_redirects=0' ${config_file}
	update_config_files 'net.ipv4.conf.default.send_redirects' 'net.ipv4.conf.default.send_redirects=0' ${config_file}

	update_config_files 'net.ipv4.conf.all.accept_source_route' 'net.ipv4.conf.all.accept_source_route=0' ${config_file}
	update_config_files 'net.ipv4.conf.default.accept_source_route' 'net.ipv4.conf.default.accept_source_route=0' ${config_file}

	update_config_files 'net.ipv4.conf.all.accept_redirects' 'net.ipv4.conf.all.accept_redirects=0' ${config_file}
	update_config_files 'net.ipv4.conf.default.accept_redirects' 'net.ipv4.conf.default.accept_redirects=0' ${config_file}

	update_config_files 'net.ipv4.conf.all.secure_redirects' 'net.ipv4.conf.all.secure_redirects=0' ${config_file}
	update_config_files 'net.ipv4.conf.default.secure_redirects' 'net.ipv4.conf.default.secure_redirects=0' ${config_file}


	update_config_files 'net.ipv4.conf.all.log_martians' 'net.ipv4.conf.all.log_martians=1' ${config_file}
	update_config_files 'net.ipv4.conf.default.log_martians' 'net.ipv4.conf.default.log_martians=1' ${config_file}

	update_config_files 'net.ipv4.icmp_echo_ignore_broadcasts' 'net.ipv4.icmp_echo_ignore_broadcasts=1' ${config_file}
	update_config_files 'net.ipv4.icmp_ignore_bogus_error_responses' 'net.ipv4.icmp_ignore_bogus_error_responses=1' ${config_file}

        # CIS hardening requires "net.ipv4.conf.all.rp_filter=1" but this is incompatible with CNIs, hence we set this to 0 instead
        update_config_files 'net.ipv4.conf.all.rp_filter' 'net.ipv4.conf.all.rp_filter=0' ${config_file}

        update_config_files 'net.ipv4.conf.default.rp_filter' 'net.ipv4.conf.default.rp_filter=1' ${config_file}
	update_config_files 'net.ipv4.tcp_syncookies' 'net.ipv4.tcp_syncookies=1' ${config_file}
	update_config_files 'kernel.randomize_va_space' 'kernel.randomize_va_space=2' ${config_file}
	update_config_files 'fs.suid_dumpable' 'fs.suid_dumpable=0' ${config_file}


	update_config_files 'net.ipv6.conf.all.accept_redirects' 'net.ipv6.conf.all.accept_redirects=0'  ${config_file}
	update_config_files 'net.ipv6.conf.default.accept_redirects' 'net.ipv6.conf.default.accept_redirects=0'   ${config_file}
	update_config_files 'net.ipv6.conf.all.accept_source_route' 'net.ipv6.conf.all.accept_source_route=0'   ${config_file}
	update_config_files 'net.ipv6.conf.default.accept_source_route' 'net.ipv6.conf.default.accept_source_route=0' ${config_file}
	update_config_files 'net.ipv6.conf.all.accept_ra' 'net.ipv6.conf.all.accept_ra=0'  ${config_file}
	update_config_files 'net.ipv6.conf.default.accept_ra' 'net.ipv6.conf.default.accept_ra=0' ${config_file}

	# CIS Level 2 - Additional kernel hardening
	update_config_files 'kernel.yama.ptrace_scope' 'kernel.yama.ptrace_scope=1' ${config_file}
	update_config_files 'kernel.dmesg_restrict' 'kernel.dmesg_restrict=1' ${config_file}
	update_config_files 'kernel.kptr_restrict' 'kernel.kptr_restrict=2' ${config_file}
	update_config_files 'kernel.perf_event_paranoid' 'kernel.perf_event_paranoid=3' ${config_file}

	# CIS Level 2 - IPv6 forwarding (disabled for non-routers)
	update_config_files 'net.ipv6.conf.all.forwarding' 'net.ipv6.conf.all.forwarding=0' ${config_file}

	# To restrict core dumps
	config_file='/etc/security/limits.conf'
	echo "" >> ${config_file}
	update_config_files '* hard core' '* hard core 0' ${config_file}

	return 0
}


##function################################################################
#  ssh related hardening
##########################################################################
harden_ssh() {
	config_file='/etc/ssh/sshd_config'

	echo "Harden ssh parameters"
	# Set permissions on ssh config file
	chown root:root ${config_file}
	chmod og-rwx ${config_file}

	echo "" >> ${config_file}
	update_config_files 'Protocol ' 'Protocol 2' ${config_file}
	update_config_files 'LogLevel ' 'LogLevel INFO' ${config_file}
	update_config_files 'PermitEmptyPasswords ' 'PermitEmptyPasswords no' ${config_file}
	update_config_files 'X11Forwarding ' 'X11Forwarding no' ${config_file}
	update_config_files 'IgnoreRhosts ' 'IgnoreRhosts yes' ${config_file}
	update_config_files 'MaxAuthTries' 'MaxAuthTries 4' ${config_file}
	update_config_files 'PermitRootLogin' 'PermitRootLogin no' ${config_file}
	update_config_files 'ClientAliveInterval' 'ClientAliveInterval 300' ${config_file}
	update_config_files 'ClientAliveCountMax' 'ClientAliveCountMax 3' ${config_file}
	update_config_files 'LoginGraceTime' 'LoginGraceTime 60' ${config_file}
	update_config_files 'Banner' 'Banner /etc/issue.net' ${config_file}
	update_config_files 'MaxStartups' 'MaxStartups 10:30:60' ${config_file}
	update_config_files 'MaxSessions' 'MaxSessions 10' ${config_file}
	update_config_files 'PermitUserEnvironment' 'PermitUserEnvironment no' ${config_file}
	update_config_files 'HostbasedAuthentication' 'HostbasedAuthentication no' ${config_file}
	update_config_files 'Ciphers' 'Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr' ${config_file}
	update_config_files 'MACs' 'MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256' ${config_file}
	update_config_files 'KexAlgorithms' 'KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group14-sha256,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256' ${config_file}

	# CIS Level 2 - Additional SSH hardening
	update_config_files 'GSSAPIAuthentication' 'GSSAPIAuthentication no' ${config_file}
	update_config_files 'UsePAM' 'UsePAM yes' ${config_file}
	update_config_files 'AllowTcpForwarding' 'AllowTcpForwarding no' ${config_file}
	update_config_files 'TCPKeepAlive' 'TCPKeepAlive no' ${config_file}
	update_config_files 'AllowAgentForwarding' 'AllowAgentForwarding no' ${config_file}
	update_config_files 'DisableForwarding' 'DisableForwarding yes' ${config_file}
	# CIS 5.2.6 - Ensure SSH access is configured with pubkey authentication
	update_config_files 'PubkeyAuthentication' 'PubkeyAuthentication yes' ${config_file}

	#############Shell timeout policy##################

	# Configuration lines to add to /etc/profile.d/timeout.sh
	config_lines="TMOUT=900"

	# Add configuration lines to the top of the file
	echo -e "$config_lines" > /etc/profile.d/timeout.sh

	echo "Configuration added to /etc/profile.d/timeout.sh"

	############sudo command use pty##################
	config_file='/etc/sudoers'
	echo "" >> ${config_file}

	update_config_files 'Defaults use_pty' 'Defaults use_pty' ${config_file}
	echo "Updated config file to sudo command use pty"

	return 0
}


##function################################################################
#  audit related hardening
##########################################################################
harden_audit() {

	local file_path_base="/etc/audit/rules.d/audit.rules"
	local file_path_timechange="/etc/audit/rules.d/50-time-change.rules"
	local file_path_identityrules="/etc/audit/rules.d/50-identity.rules"
	local file_path_accessrules="/etc/audit/rules.d/50-access.rules"
	local file_path_deleterules="/etc/audit/rules.d/50-delete.rules"
	local file_path_mountrules="/etc/audit/rules.d/50-mounts.rules"
	local file_path_scoperules="/etc/audit/rules.d/50-scope.rules"
	local file_path_actionsrules="/etc/audit/rules.d/50-actions.rules"
	local file_path_modulesrules="/etc/audit/rules.d/50-modules.rules"
	local file_path_immutablerules="/etc/audit/rules.d/99-finalize.rules"
	local file_path_networkrules="/etc/audit/rules.d/50-system-locale.rules"
	local file_path_MACrules="/etc/audit/rules.d/50-MAC-policy.rules"
	local file_path_logineventsrules="/etc/audit/rules.d/50-logins.rules"
	local file_path_DACrules="/etc/audit/rules.d/50-perm_mod.rules"

	local content_base=(
		"-D"
		"-b 8192"
		"--backlog_wait_time 60000"
		"-f 1"
	)

	local content_timechange=(
		"-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change"
		"-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time-change"
		"-a always,exit -F arch=b64 -S clock_settime -k time-change"
		"-a always,exit -F arch=b32 -S clock_settime -k time-change"
		"-w /etc/localtime -p wa -k time-change"
	)

	local content_identityrules=(
		"-w /etc/group -p wa -k identity"
		"-w /etc/passwd -p wa -k identity"
		"-w /etc/gshadow -p wa -k identity"
		"-w /etc/shadow -p wa -k identity"
		"-w /etc/security/opasswd -p wa -k identity"
	)

	local content_accessrules=(
		"-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access"
		"-a always,exit -F arch=b32 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access"
		"-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access"
		"-a always,exit -F arch=b32 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access"
	)

	local content_deleterules=(
		"-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete"
		"-a always,exit -F arch=b32 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete"
	)

	local content_mountrules=(
		"-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts"
		"-a always,exit -F arch=b32 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts"
	)

	local content_scoperules=(
		"-w /etc/sudoers -p wa -k scope"
		"-w /etc/sudoers.d/ -p wa -k scope"
	)

	local content_actionsules=(
		"-a always,exit -F arch=b64 -C euid!=uid -F euid=0 -Fauid>=1000 -F auid!=4294967295 -S execve -k actions"
		"-a always,exit -F arch=b32 -C euid!=uid -F euid=0 -Fauid>=1000 -F auid!=4294967295 -S execve -k actions"
	)

	local content_modulesrules=(
		"-w /sbin/insmod -p x -k modules"
		"-w /sbin/rmmod -p x -k modules"
		"-w /sbin/modprobe -p x -k modules"
		"-a always,exit -F arch=b64 -S init_module -S delete_module -k modules"
	)

	local content_immutablerules=(
		"-e 2"
	)

	local content_networkrules=(
		"-a always,exit -F arch=b64 -S sethostname -S setdomainname -k system-locale"
		"-a always,exit -F arch=b32 -S sethostname -S setdomainname -k system-locale"
		"-w /etc/issue -p wa -k system-locale"
		"-w /etc/issue.net -p wa -k system-local"
		"-w /etc/hosts -p wa -k system-locale"
		"-w /etc/network -p wa -k system-locale"
	)

	local content_MACrules=(
		"-w /etc/apparmor/ -p wa -k MAC-policy"
	)

	local content_logineventsrules=(
		"-w /var/log/faillog -p wa -k logins"
		"-w /var/log/lastlog -p wa -k logins"
		"-w /var/log/tallylog -p wa -k logins"
	)

	# CIS 4.1.3.* - Session initiation information audit rules
	local file_path_sessionrules="/etc/audit/rules.d/50-session.rules"
	local content_sessionrules=(
		"-w /var/run/utmp -p wa -k session"
		"-w /var/log/wtmp -p wa -k session"
		"-w /var/log/btmp -p wa -k session"
	)

	local content_DACrules=(
		"-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod"
		"-a always,exit -F arch=b32 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod"
		"-a always,exit -F arch=b64 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod"
		"-a always,exit -F arch=b32 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod"
		"-a always,exit -F arch=b64 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod"
		"-a always,exit -F arch=b32 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod"
	)


	# Create or append to the time change rules
	echo "" > "$file_path_base"
	for line in "${content_base[@]}"; do
		echo "$line" | sudo tee -a "$file_path_base" >/dev/null
	done

	# Create or append to the time change rules
	for line in "${content_timechange[@]}"; do
		echo "$line" | sudo tee -a "$file_path_timechange" >/dev/null
	done

	# Create or append to the identity rules
	for line in "${content_identityrules[@]}"; do
		echo "$line" | sudo tee -a "$file_path_identityrules" >/dev/null
	done

	# Create or append to the access rules
	for line in "${content_accessrules[@]}"; do
		echo "$line" | sudo tee -a "$file_path_accessrules" >/dev/null
	done

		# Create or append to the delete rules
	for line in "${content_deleterules[@]}"; do
		echo "$line" | sudo tee -a "$file_path_deleterules" >/dev/null
	done

		# Create or append to the mount rules
	for line in "${content_mountrules[@]}"; do
		echo "$line" | sudo tee -a "$file_path_mountrules" >/dev/null
	done

		# Create or append to the scope rules
	for line in "${content_scoperules[@]}"; do
		echo "$line" | sudo tee -a "$file_path_scoperules" >/dev/null
	done

		# Create or append to the actions rules
	for line in "${content_actionsules[@]}"; do
		echo "$line" | sudo tee -a "$file_path_actionsrules" >/dev/null
	done

		# Create or append to the modules rules
	for line in "${content_modulesrules[@]}"; do
		echo "$line" | sudo tee -a "$file_path_modulesrules" >/dev/null
	done

		# Create or append to the immutables rules
	for line in "${content_immutablerules[@]}"; do
		echo "$line" | sudo tee -a "$file_path_immutablerules" >/dev/null
	done

		# Create or append to the network rules
	for line in "${content_networkrules[@]}"; do
		echo "$line" | sudo tee -a "$file_path_networkrules" >/dev/null
	done

		# Create or append to the MAC rules
	for line in "${content_MACrules[@]}"; do
		echo "$line" | sudo tee -a "$file_path_MACrules" >/dev/null
	done

		# Create or append to the login/logout events rules
	for line in "${content_logineventsrules[@]}"; do
		echo "$line" | sudo tee -a "$file_path_logineventsrules" >/dev/null
	done

		# Create or append to the DAC rules
	for line in "${content_DACrules[@]}"; do
		echo "$line" | sudo tee -a "$file_path_DACrules" >/dev/null
	done

	# CIS 4.1.3.* - Create or append to the session rules
	for line in "${content_sessionrules[@]}"; do
		echo "$line" | sudo tee -a "$file_path_sessionrules" >/dev/null
	done


	# Verify if the files were created or appended successfully
	if [ -f "$file_path_timechange" ] && [ -f "$file_path_identityrules" ] && [ -f "$file_path_accessrules" ] && [ -f "$file_path_deleterules" ] && [ -f "$file_path_mountrules" ] && [ -f "$file_path_scoperules" ] && [ -f "$file_path_actionsrules" ] && [ -f "$file_path_modulesrules" ] && [ -f "$file_path_immutablerules" ] && [ -f "$file_path_networkrules" ] && [ -f "$file_path_MACrules" ] && [ -f "$file_path_logineventsrules" ] && [ -f "$file_path_DACrules" ]; then
		echo "Files '$file_path_timechange', '$file_path_identityrules', '$file_path_accessrules', '$file_path_deleterules', '$file_path_mountrules', '$file_path_scoperules', '$file_path_actionsrules', '$file_path_modulesrules', '$file_path_immutablerules', '$file_path_networkrules', '$file_path_MACrules', '$file_path_logineventsrules'& '$file_path_DACrules' created/appended successfully."
	else
		echo "Failed to create/append to files '$file_path_timechange' and/or '$file_path_identityrules' and or '$file_path_accessrules' and or '$file_path_deleterules' and or '$file_path_mountrules' and or '$file_path_scoperules' and or '$file_path_actionsrules' and or '$file_path_modulesrules' and or '$file_path_immutablerules' and or '$file_path_networkrules' and or '$file_path_MACrules' and or '$file_path_logineventsrules' and or '$file_path_DACrules'."
	fi

	# Define the desired value for max_log_file
	max_log_file_value=100

	# Set the max_log_file parameter in auditd.conf
	sed -i "s/^max_log_file = 8/max_log_file = ${max_log_file_value}/" /etc/audit/auditd.conf

	echo "The max_log_file parameter has been set to ${max_log_file_value}."

	# Enable auditd service
	systemctl enable auditd

	return 0
}

##function################################################################
#  boot up related hardening
##########################################################################
harden_boot() {
	echo "Disable Ctrl + Alt + Del key"
	systemctl mask ctrl-alt-del.target

	grub_conf='/etc/cos/grub.cfg'

	if [[ -f ${grub_conf} ]]; then
		chown root:root ${grub_conf}
		chmod u-wx,go-rwx ${grub_conf}

		sed -i 's/set baseExtraArgs=""/set baseExtraArgs="audit=1"/g' /etc/cos/bootargs.cfg

		echo "Grub configuration updated successfully."
	fi

	return 0
}

##function################################################################
#  password related hardening
##########################################################################
harden_password_files() {

	chmod 644 /etc/passwd
	chown root:root  /etc/passwd
	chmod 644 /etc/passwd-
	chown root:root  /etc/passwd-
	chmod 640 /etc/shadow
	chown root:root  /etc/shadow
	chmod 000 /etc/shadow-
	chown root:root  /etc/shadow-
	chmod 000 /etc/gshadow
	chown root:root  /etc/gshadow
	chmod 000 /etc/gshadow-
	chown root:root  /etc/gshadow-
	chmod 644 /etc/group
	chown root:root  /etc/group
	chmod 644 /etc/group-
	chown root:root  /etc/group-

	return 0
}


##function################################################################
#  os related hardening
##########################################################################
harden_system() {

	echo "Check if root user has 0 as guid , if not set it"
	root_gid=$(grep '^root:' /etc/passwd | cut -d : -f 4)
	if [[ ${root_gid} -ne 0 ]]; then
		usermod -g 0 root
		check_error $? "Failed changing root guid to 0" 1
	fi

	echo "Error out if there are users with empty password"
	cat /etc/shadow |awk -F : '($2 == "" ){ exit 1}'
	if $? -ne 0 ; then
		echo "Users present with empty password. Remove the user or set password for the users"
		exit 1
	fi

	echo "Check if any user other than root has uid of 0"
	root_uid_count=$(cat /etc/passwd | awk -F ":"  '($3 == 0){print $3}' | wc -l)
	if [[ ${root_uid_count} -ne 1 ]]; then
		echo "Non root users have UID of 0.Correct the error and retry"
		exit 1
	fi

	echo "Fix permission of all cron files"
	cron_files="/etc/etc/cron.daily /etc/cron.hourly /etc/cron.d /etc/cron.monthly /etc/cron.weekly /etc/crontab"
	for each in ${cron_files}; do
		if [[ -e ${each} ]]; then
			stat -L -c "%a %u %g" "${each}" | grep -E ".00 0 0"
			if $? -ne 0 ; then
				chown root:root "${each}"
				chmod og-rwx "${each}"
			fi
		fi
	done

	echo "Remove cron and at deny files and have allow files in place"
	rm -f /etc/cron.deny
	rm -f /etc/at.deny
	touch /etc/cron.allow
	touch /etc/at.allow
	chmod g-wx,o-rwx /etc/cron.allow
	chmod g-wx,o-rwx /etc/at.allow
	chown root:root /etc/cron.allow
	chown root:root /etc/at.allow

	if [[ ! -f /etc/issue ]]; then
		echo "### Authorized users only. All activity may be monitored and reported ###" > /etc/issue
	fi
	chmod 644 /etc/issue
	chown root:root /etc/issue

	if [[ ! -f /etc/issue.net ]]; then
		echo "### Authorized users only. All activity may be monitored and reported ###" > /etc/issue.net
	fi
	chmod 644 /etc/issue.net
	chown root:root /etc/issue.net

	if [[ -f /etc/rsyslog.conf ]]; then
		chmod 0640 /etc/rsyslog.conf
	fi

	##################users' home directories permissions are 750 or more restrictive######
	awk -F: '($1 !~ /^(halt|sync|shutdown|nfsnobody)$/ && $7 !~ /^(\/usr)?\/sbin\/nologin(\/)?$/ && $7 !~ /^(\/usr)?\/bin\/false(\/)?$/) {print $6}' /etc/passwd | while read -r dir; do
		if [ -d "$dir" ]; then
			dirperm=$(stat -L -c '%a' "$dir")
			if [ "$(echo "$dirperm" | cut -c6)" != "-" ] || [ "$(echo "$dirperm" | cut -c8)" != "-" ] || [ "$(echo "$dirperm" | cut -c9)" != "-" ] || [ "$(echo "$dirperm" | cut -c10)" != "-" ]; then
				chmod g-w,o-rwx "$dir"
			fi
		fi
	done

	return 0
}

##########################################################################
#  Remove unnecessary packages
##########################################################################
remove_services() {

	if [[ ${OS_FLAVOUR} == "ubuntu" ]]; then
		echo "Disable setrouble shoot service if enabled"
		systemctl disable setroubleshoot 2>/dev/null || true

		echo "Removing legacy networking services"
		systemctl disable xinetd 2>/dev/null || true
		apt-get remove -y openbsd-inetd rsh-client rsh-redone-client nis talk telnet ldap-utils gdm3 2>/dev/null || true
		apt-get purge -y telnet vim vim-common vim-runtime vim-tiny 2>/dev/null || true

		echo "Removing X packages"
		apt-get remove -y xserver-xorg* 2>/dev/null || true

		# CIS Level 2 - Additional packages to remove
		echo "Removing additional CIS Level 2 packages"
		apt-get remove -y avahi-daemon cups rpcbind nfs-kernel-server vsftpd apache2 nginx samba squid snmpd 2>/dev/null || true

		# CIS Level 2 - Disable additional services
		echo "Disabling additional CIS Level 2 services"
		systemctl disable avahi-daemon 2>/dev/null || true
		systemctl disable cups 2>/dev/null || true
		systemctl disable rpcbind 2>/dev/null || true
		systemctl disable nfs-server 2>/dev/null || true
		systemctl disable bluetooth 2>/dev/null || true
		systemctl disable apport 2>/dev/null || true
		systemctl disable autofs 2>/dev/null || true

		# CIS 1.6.1 - Disable kdump service
		echo "Disabling kdump service"
		systemctl disable kdump-tools 2>/dev/null || true
		systemctl mask kdump-tools 2>/dev/null || true
	fi

	if [[ ${OS_FLAVOUR} == "centos" ]] || [[ ${OS_FLAVOUR} == "rhel" ]]; then
		echo "Disable setrouble shoot service if enabled"
		chkconfig setroubleshoot off

		echo "Removing legacy networking services"
		yum erase -y inetd xinetd ypserv tftp-server telnet-server rsh-server gdm3 telnet vim vim-common vim-runtime vim-tiny

		echo "Removing X packages"
		yum groupremove -y "X Window System"
		yum remove -y xorg-x11*
	fi

  	# Placeholder for supporting other linux OS
  	if [[ ${OS_FLAVOUR} == "linux" ]]; then
			test 1 -eq 2
			check_error $? "OS not supported" 1
  	fi

  	return 0
}

##########################################################################
#  Block unnecessary modules
##########################################################################
disable_modules() {

	if [[ -d  /etc/modprobe.d ]]; then
	echo "Disabling unnecessary modules"

	echo "install dccp /bin/true"   > /etc/modprobe.d/dccp.conf
	echo "install sctp /bin/true"  >> /etc/modprobe.d/sctp.conf
	echo "install rds /bin/true"   >> /etc/modprobe.d/rds.conf
	echo "install tipc /bin/true"  >> /etc/modprobe.d/tipc.conf

	echo "install cramfs /bin/false"   > /etc/modprobe.d/cramfs.conf
	echo "install freevxfs /bin/true" > /etc/modprobe.d/freevxfs.conf
	echo "install jffs2 /bin/true"    > /etc/modprobe.d/jffs2.conf
	echo "install hfs /bin/true"      > /etc/modprobe.d/hfs.conf
	echo "install hfsplus /bin/true"  > /etc/modprobe.d/hfsplus.conf

	# CIS Level 2 - Additional filesystem modules to disable
	echo "blacklist cramfs" >> /etc/modprobe.d/cramfs.conf
	echo "blacklist freevxfs" >> /etc/modprobe.d/freevxfs.conf
	echo "blacklist jffs2" >> /etc/modprobe.d/jffs2.conf
	echo "blacklist hfs" >> /etc/modprobe.d/hfs.conf
	echo "blacklist hfsplus" >> /etc/modprobe.d/hfsplus.conf

	# Needed for Kairos - do not disable squashfs and udf
	#echo "install squashfs /bin/true"  > /etc/modprobe.d/squashfs.conf
	#echo "install udf /bin/true"       > /etc/modprobe.d/udf.conf
	#echo "install usb-storage /bin/false" > /etc/modprobe.d/usb_storage.conf
	fi

	return 0
}

##########################################################################
#  CIS Level 2 - Journald Hardening
##########################################################################
harden_journald() {
	echo "Configuring journald for CIS Level 2 compliance"

	local journald_conf="/etc/systemd/journald.conf"

	if [[ -f ${journald_conf} ]]; then
		# Ensure journald is configured to compress large log files
		if grep -q "^Compress=" ${journald_conf}; then
			sed -i "s/^Compress=.*/Compress=yes/" ${journald_conf}
		else
			echo "Compress=yes" >> ${journald_conf}
		fi

		# Ensure journald is configured to write logfiles to persistent disk
		if grep -q "^Storage=" ${journald_conf}; then
			sed -i "s/^Storage=.*/Storage=persistent/" ${journald_conf}
		else
			echo "Storage=persistent" >> ${journald_conf}
		fi

		# Ensure journald is not configured to send logs to rsyslog
		if grep -q "^ForwardToSyslog=" ${journald_conf}; then
			sed -i "s/^ForwardToSyslog=.*/ForwardToSyslog=no/" ${journald_conf}
		else
			echo "ForwardToSyslog=no" >> ${journald_conf}
		fi

		echo "Journald configuration updated for CIS Level 2 compliance"
	fi

	return 0
}

##########################################################################
#  Login Banner
##########################################################################

harden_banner() {

	local file_path_locallogin="/etc/issue"
	local file_path_remotelogin="/etc/issue.net"

	local content_locallogin=(
    "Authorized uses only. All activity may be monitored and reported."
	)

	local content_remotelogin=(
    "Authorized uses only. All activity may be monitored and reported."
	)
	# Create or append to the local login banner
	for line in "${content_locallogin[@]}"; do
		echo "$line" | sudo tee -a "$file_path_locallogin" >/dev/null
	done

	# Create or append to the remote login banner
	for line in "${content_remotelogin[@]}"; do
		echo "$line" | sudo tee -a "$file_path_remotelogin" >/dev/null
	done

	# Verify if the files were created or appended successfully
	if [ -f "$file_path_locallogin" ] && [ -f "$file_path_remotelogin" ]; then
		echo "Files $file_path_locallogin', '$file_path_remotelogin' created/appended successfully."
	else
		echo "Failed to create/append to files '$file_path_locallogin' and or '$file_path_remotelogin'."
	fi

	# Delete motd file
	if [[ -f /etc/motd ]]; then rm /etc/motd; fi

	return 0
}


#############################################################
#		Log files permission
#############################################################
harden_log() {

	# Ensure permissions on all logfiles are configured

	# Find and set permissions on log files
	find /var/log -type f -exec chmod g-wx,o-rwx '{}' + -o -type d -exec chmod g-w,o-rwx '{}' +

	echo "750 permission set on all log files & directories inside /var/log"

	# Ensure logrotate assigns appropriate permissions

	# Define restrictive permissiom
	utmp="create 0640 root utmp"
	# Modify the logrotate configuration

	if [ -e "/etc/logrotate.conf" ]; then
		# Check if the logrotation restrictive permission exists
		if grep -q "^create 0640" /etc/logrotate.conf; then
			# Modify the existing line
			sed -i "s/^create 0640.*/$utmp/" /etc/logrotate.conf
			echo "Modified restrictive permission in /etc/logrotate.conf"
		else
			# Add the new restrictive permission at the end of the file
			echo "$utmp" >> /etc/logrotate.conf
			echo "Added restrictive permission to /etc/logrotate.conf"
		fi
	fi

	# Ensure sudo log file exists
	# Define sudo log file
	logfile="Defaults logfile=/var/log/sudo.log"

	if [ -e "/etc/sudoers" ]; then
		# Check if the sudo log file path exists
		if grep -q "$logfile" /etc/sudoers; then
			echo "sudo log file path already exist in /etc/sudoers"
		else
			# Add the log file path at the end of the file
			echo "$logfile" >> /etc/sudoers
			echo "Added log file path to /etc/sudoers"
		fi
	fi

	return 0
}


##########################################################################
#  Authentication/Login Hardening
##########################################################################
harden_auth() {

	# Define the new values for minlen and minclass
	new_minlen="minlen = 14"
	new_minclass="minclass = 4"
	new_difok="difok = 2"
	new_dictcheck="dictcheck = 0"
	new_maxrepeat="maxrepeat = 3"

	# Check if the file exists
	if [ -e "/etc/security/pwquality.conf" ]; then
		# Check if the minlen line already exists
		if grep -q "^minlen" /etc/security/pwquality.conf; then
			# Modify the existing minlen line
			sed -i "s/^minlen.*/$new_minlen/" /etc/security/pwquality.conf
			echo "Modified minlen in /etc/security/pwquality.conf"
		else
			# Add the new minlen line at the end of the file
			echo "$new_minlen" >> /etc/security/pwquality.conf
			echo "Added minlen to /etc/security/pwquality.conf"
		fi

		# Check if the minclass line already exists
		if grep -q "^minclass" /etc/security/pwquality.conf; then
			# Modify the existing minclass line
			sed -i "s/^minclass.*/$new_minclass/" /etc/security/pwquality.conf
			echo "Modified minclass in /etc/security/pwquality.conf"
		else
			# Add the new minclass line at the end of the file
			echo "$new_minclass" >> /etc/security/pwquality.conf
			echo "Added minclass to /etc/security/pwquality.conf"
		fi

		# Check if the difok line already exists
		if grep -q "^difok" /etc/security/pwquality.conf; then
			# Modify the existing difok line
			sed -i "s/^difok.*/$new_difok/" /etc/security/pwquality.conf
			echo "Modified difok in /etc/security/pwquality.conf"
		else
			# Add the new difok line at the end of the file
			echo "$new_difok" >> /etc/security/pwquality.conf
			echo "Added difok to /etc/security/pwquality.conf"
		fi

		# Check if the dictcheck line already exists
		if grep -q "^dictcheck" /etc/security/pwquality.conf; then
			# Modify the existing dictcheck line
			sed -i "s/^dictcheck.*/$new_dictcheck/" /etc/security/pwquality.conf
			echo "Modified dictcheck in /etc/security/pwquality.conf"
		else
			# Add the new dictcheck line at the end of the file
			echo "$new_dictcheck" >> /etc/security/pwquality.conf
			echo "Added dictcheck to /etc/security/pwquality.conf"
		fi

		# Check if the maxrepeat line already exists
		if grep -q "^maxrepeat" /etc/security/pwquality.conf; then
			# Modify the existing maxrepeat line
			sed -i "s/^maxrepeat.*/$new_maxrepeat/" /etc/security/pwquality.conf
			echo "Modified maxrepeat in /etc/security/pwquality.conf"
		else
			# Add the new maxrepeat line at the end of the file
			echo "$new_maxrepeat" >> /etc/security/pwquality.conf
			echo "Added maxrepeat to /etc/security/pwquality.conf"
		fi
	else
		echo "File /etc/security/pwquality.conf not found."
	fi

	# Configuration lines to add to /etc/pam.d/su
	config_lines="auth required pam_wheel.so use_uid group=admin"

	# Add configuration lines to the top of the file
	echo -e "$config_lines\n$(cat /etc/pam.d/su)" > /etc/pam.d/su

	echo "Configuration to ensure access to the su command is restricted have been made"

	##############Password lockout policies##################

	# Backup the original file
	cp /etc/pam.d/common-auth /etc/pam.d/common-auth.bak

	{
		echo "auth required                   pam_faillock.so preauth audit silent deny=4 fail_interval=900 unlock_time=600"
		echo "auth [success=1 default=ignore] pam_unix.so nullok"
		echo "auth [default=die]              pam_faillock.so authfail audit deny=4 fail_interval=900 unlock_time=600"
		echo "auth sufficient                 pam_faillock.so authsucc audit deny=4 fail_interval=900 unlock_time=600"
		echo "auth requisite                  pam_deny.so"
		echo "auth required                   pam_permit.so"
	} >> /etc/pam.d/common-auth

	# Backup the original file
	cp /etc/pam.d/common-account /etc/pam.d/common-account.bak

	echo "account required                        pam_faillock.so" >> /etc/pam.d/common-account

	##############Password reuse policy##################

	# Backup the original file
	cp /etc/pam.d/common-password /etc/pam.d/common-password.bak

	{
		echo "password requisite pam_pwquality.so retry=3"
		echo "password [success=1 default=ignore] pam_unix.so obscure use_authtok try_first_pass remember=5"
		echo "password requisite pam_deny.so"
		echo "password required pam_permit.so"
	} >> /etc/pam.d/common-password

	#####################Password expiry policy#################

	#Define the destination file
	config_file='/etc/login.defs'

	echo "" >> ${config_file}

	update_config_files 'PASS_MIN_DAYS' 'PASS_MIN_DAYS 1' ${config_file}
	update_config_files 'PASS_MAX_DAYS' 'PASS_MAX_DAYS 365' ${config_file}
	update_config_files 'PASS_WARN_AGE' 'PASS_WARN_AGE 7' ${config_file}

	echo "Password expiry policy updated to PASS_MIN_DAYS 1 & PASS_MAX_DAYS 365 & PASS_WARN_AGE 7"

	#####################Password encryption standards##########

	config_file='/etc/login.defs'

	update_config_files 'ENCRYPT_METHOD' 'ENCRYPT_METHOD yescrypt' ${config_file}

	echo "Password encryption method set to yescrypt"

	####################Inactive password lock################

	#Define the destination file
	config_file='/etc/default/useradd'

	echo "" >> ${config_file}

	update_config_files 'INACTIVE' 'INACTIVE=30' ${config_file}
	echo "Inactive password lock policy updated to 30 days"

	#################Session expiry policy#####################
	# Configuration lines to add to /etc/profile
	config_lines="readonly TMOUT=900 ; export TMOUT"

	# Add configuration lines to the top of the file
	echo "$config_lines" >> /etc/profile

	echo "Configuration added to /etc/profile for shell timeout policy"
	return 0
}

##########################################################################
#  Cleanup Package Manager Cache
##########################################################################
cleanup_cache() {
	if [[ ${OS_FLAVOUR} == "ubuntu" ]]; then
		apt-get clean
		rm -rf /var/lib/apt/lists/*
	fi

	if [[ ${OS_FLAVOUR} == "centos" ]]; then
		yum clean all
		rm -rf /var/cache/yum/*
	fi

	if [[ ${OS_FLAVOUR} == "rhel" ]]; then
		yum clean all
		rm -rf /var/cache/yum/*
	fi

	# Placeholder for supporting other linux OS
	if [[ ${OS_FLAVOUR} == "linux" ]]; then
		test 1 -eq 2
		check_error $? "OS not supported" 1
	fi

	return 0
}

cp /etc/os-release /etc/os-release.bak

OS_FLAVOUR="linux"
get_os
upgrade_packages
harden_sysctl
harden_ssh
harden_boot
harden_password_files
harden_system
remove_services
disable_modules
harden_journald
harden_audit
harden_banner
harden_log
harden_auth
cleanup_cache

mv /etc/os-release.bak /etc/os-release

exit 0
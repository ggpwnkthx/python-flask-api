from packages.ssh.models import Connection
import os

required_kernel_version = "4.10"
required_infiniband_modules = ['mlx4_core', 'mlx4_ib', 'rdma_ucm', 'ib_umad', 'ib_uverbs', 'ib_ipoib']

def bootstrap(password, user = None, host = None):
	ssh = Connection(host, user, password)
	ssh.open()
	
	# Create and provision key pair
	ssh.key()
	# Sanity check the username to help prevent injection hacks
	user = ssh.execute('whoami').results()[-1]['std_out'].replace("\n","")
	# Check if sudo is available
	if ssh.execute('command -v sudo').results()[-1]['std_out'].replace("\n",""):
		if user != "root":
			# Setup passwordless sudo
			ssh.sudo('echo '+user+' ALL = \(root\) NOPASSWD:ALL > /etc/sudoers.d/'+user)
			ssh.sudo('chmod 0440 /etc/sudoers.d/'+user)
	# Set this user as our default
	ssh.set_default_user()
	
	ssh.close()
	return {'results':ssh.results()}

def change_hostname(fqdn = None, host = None):
	hostname = fqdn.split('.')[:1][0]
	domain = '.'.join(fqdn.split('.')[1:])
	
	if not domain:
		return {'status':'error','message':'A fully qualified domain name was not specified.'}
	ssh = Connection(host)
	ssh.open()
	
	# Check current FQDN
	_hostname = ssh.execute("hostname -s").results()[-1]['std_out'].replace("\n","")
	_fqdn = ssh.execute("hostname -f").results()[-1]['std_out'].replace("\n","")
	if len(_fqdn.split('.')[1:]):
		# Replace the FQDN in the hosts file
		ssh.sudo("sed -i \"s/"+_fqdn+"/"+fqdn+"/g\" /etc/hosts")
	# Get the current local IP address
	ip = ssh.execute("echo $(cat /etc/hosts | grep \"[[:space:]]"+_hostname+"$\" | awk '{print $1}')").results()[-1]['std_out'].replace("\n","")
	# Replace the hostname in hosts file and update live hostname (we do both in the same execution to prevent sudo timeout)
	ssh.sudo("sed -i 's/\(^.*[[:space:]]"+_hostname+"$\)/"+ip+"\t"+fqdn+" "+hostname+"/g' /etc/hosts && hostname "+hostname)
	# Set hostname permenently
	ssh.sudo("echo "+hostname+" > /etc/hostname")
	# Set domain name
	ssh.sudo("echo search "+domain+" > /etc/resolvconf/resolv.conf.d/head")
	# Update resolvconf
	ssh.sudo("resolvconf -u")
	
	ssh.close()
	return {'results':ssh.results()}

def get_package_manager(host = None):
	ssh = Connection(host)
	ssh.open()
	
	supported_package_manangers = ['apt', 'yum', 'pip']
	for pm in supported_package_manangers:
		if ssh.execute("command -v "+pm).results()[-1]['std_out'].replace("\n",""):
			ssh.close()
			return {'status':'success', 'result':pm}
	
	ssh.close()
	return {'status':'error', 'results':'No supported package manager found.'}


def check_kernel_version(host = None):
	ssh = Connection(host)
	ssh.open()
	
	check = []
	check.append(required_kernel_version)
	check.append(ssh.execute("uname -r | awk -F '-' '{print $1}").results()[-1]['std_out'].replace("\n",""))
	check.sort()
	
	ssh.close()
	if check[0] == required_kernel_version:
		return {'status':'success'}
	else:
		return {'status':'error','message':'Kernel version is lower than '+required_kernel_version}

def update_kernel_headers(host = None):
	if check_kernel_version(host)['status'] == 'error':
		ssh = Connection(host)
		ssh.open()
		
		# Get the remote system's current kernel type
		kernel_type = ssh.execute("uname -r | awk -F '-' '{print $NF}'").results()[-1]['std_out'].replace("\n","")
		
		# Cross distribution magic
		package_manager = get_package_manager(host)
		
		if package_manager['status'] == 'error':
			ssh.close()
			return package_manager
		else:
			# Find the latest required kernel version using apt-cache (if available) 
			if package_manager == 'apt':
				# Update repo if necesary
				cache = ssh.execute("find -H /var/lib/apt/lists -maxdepth 0 -mtime -1").results()[-1]['std_out'].replace("\n","")
				if not cache:
					ssh.sudo("apt-get update")
				# Find latest headers for the required kernel version
				available_headers = ssh.execute('apt-cache search --names-only "linux-headers-'+required_kernel_version+'.*-'+kernel_type+'" | sort -r').results()[-1]['std_out'].split("\n")
				available_headers.sort()
				use_header = available_headers[-1:][0].split(' ')[0]
				# Install new kernel headers
				ssh.sudo("DEBIAN_FRONTEND=noninteractive apt-get install -y "+use_header)
			if package_manager == 'yum':
				# Add ElRepo
				ssh.sudo('rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org')
				ssh.sudo('rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm')
				# Install fastest-mirror plugin for yum
				ssh.sudo('yum install -y yum-plugin-fastestmirror')
				# Install new kernel headers
				ssh.sudo('yum --enablerepo=elrepo-kernel install -y kernel-ml-headers')
		
		ssh.close()
		return {'results':ssh.results()}
	return {'status':'success'}

def update_kernel_image(host = None):
	if check_kernel_version(host)['status'] == 'error':
		ssh = Connection(host)
		ssh.open()
		
		# Get the remote system's current kernel type
		kernel_type = ssh.execute("uname -r | awk -F '-' '{print $NF}'").results()[-1]['std_out'].replace("\n","")
		
		# Cross distribution magic
		package_manager = get_package_manager(host)
		
		if package_manager['status'] == 'error':
			ssh.close()
			return package_manager
		else:
			# Find the latest required kernel version using apt-cache (if available) 
			if package_manager == 'apt':
				# Update repo if necesary
				cache = ssh.execute("find -H /var/lib/apt/lists -maxdepth 0 -mtime -1").results()[-1]['std_out'].replace("\n","")
				if not cache:
					ssh.sudo("apt-get update")
				# Find latest image for the requried kernel version
				available_images = ssh.execute('apt-cache search --names-only "linux-image-'+required_kernel_version+'.*-'+kernel_type+'" | sort -r').results()[-1]['std_out'].split("\n")
				available_images.sort()
				use_image = available_images[-1:][0].split(' ')[0]
				# Install new kernel image
				ssh.sudo("DEBIAN_FRONTEND=noninteractive apt-get install -y "+use_image)
				# Reboot the system
				ssh.sudo('reboot')
			if package_manager == 'yum':
				# Add ElRepo
				ssh.sudo('rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org')
				ssh.sudo('rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm')
				# Install fastest-mirror plugin for yum
				ssh.sudo('yum install -y yum-plugin-fastestmirror')
				# Install new kernel headers
				ssh.sudo('yum --enablerepo=elrepo-kernel install -y kernel-ml')
				# Set default GRUB option to the new kernel
				ssh.sudo('grub2-set-default 0')
				ssh.sudo('grub2-mkconfig -o /boot/grub2/grub.cfg')
				# Reboot the system
				ssh.sudo('reboot')
		
		ssh.close()
		return {'results':ssh.results()}
	return {'status':'success'}
	
	
def check_infiniband(host = None):
	ssh = Connection(host)
	ssh.open()
	
	# Check for Infinband devices
	if not ssh.execute('lspci | grep InfiniBand').results()[-1]['std_out'].replace("\n",""):
		ssh.close()
		return {'status':'success'}
	else:
		# If devices found, make sure the modules automatically load on boot
		for mod in required_infiniband_modules:
			if not ssh.execute('cat /etc/modules | grep '+mod).results()[-1]['std_out'].replace("\n",""):
				ssh.close()
				return {'status':'error','message':'InfiniBand device found, but some modules are not auto-enabled.'}
	
	ssh.close()
	return {'status':'success'}
				
def enable_infiniband(host = None):
	if check_infiniband(host)['status'] == 'error':
		ssh = Connection(host)
		ssh.open()
		
		# Add any missing modules to /etc/modules
		for mod in required_infiniband_modules:
			ssh.sudo('modprobe '+mod)
			if not ssh.execute('cat /etc/modules | grep '+mod).results()[-1]['std_out'].replace("\n",""):
				ssh.sudo('echo '+mod+' >> /etc/modules')
		
		ssh.close()
		return {'results':ssh.results()}
	return {'status':'success'}
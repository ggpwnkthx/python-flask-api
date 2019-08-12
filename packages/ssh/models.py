from main import app
import time
import os
import paramiko
import logging
import json
from paramiko.ssh_exception import *
from scp import SCPClient
from .cipher import encrypt
from Crypto.PublicKey import RSA
import io
import hashlib

class Connection(object):
	def __init__(self, host = None, user = None, password = None):
		# Where are we connecting to?
		if host == "localhost":
			try:
				host = os.environ['DOCKER_BRIDGE']
			except Exception:
				host = "127.0.0.1"
		if not host:
			raise Exception('No host specified.')
		self.__host = host
			
		# Who are we connecting as?
		if not user:
			try:
				user = os.environ['SSH_USER']
			except Exception:
				pass
		if not user:
			path = "configs/packages/ssh/"+self.__host+"/default"
			if os.path.islink(path):
				user = os.readlink(path)
		if not user:
			raise Exception('No user specified.')
		self.__user = user
		
		# How are we authenticating?
		if not password:
			if not self.is_keyed():
				raise Exception('No password or SSH key specified.')
			else:
				self.__use = 'sshkey'
				self.__sshkey = "configs/packages/ssh/"+self.__host+"/"+self.__user+"/id_rsa"
		else:
			self.__use = 'password'
			self.__password = password
		
		# What are we logging?
		self.__logger = paramiko.util.logging.getLogger()
		self.__hdlr = logging.FileHandler('app.log')
		self.__formatter = logging.Formatter('%(asctime)s %(levelname)s %(message)s')
		self.__hdlr.setFormatter(self.__formatter)
		self.__logger.addHandler(self.__hdlr) 
		self.__logger.setLevel(logging.INFO)
		self.__connector = paramiko.SSHClient()
		self.__connector.set_missing_host_key_policy(paramiko.AutoAddPolicy())
		
		# Variables
		self.__status = ''
		self.__error = ''
		self.__public_key = ''
		self.__results = []
		self.__sudo = ''
		
		# Get or set the Machine Unique ID
		m = hashlib.md5()
		try:
			m.update(os.environ['MUID'])
		except:
			try:
				m.update(app.config['MUID'])
			except:
				f = open('/proc/sys/kernel/random/uuid')
				app.config['MUID'] = f.read()
				m.update(app.config['MUID'])
		self.__MUID = m.hexdigest()
		
		# Set the passphrase for remote encryption
		p = hashlib.md5()
		p.update(app.config['SECRET_KEY'])
		self.__passphrase = p.hexdigest()
		
	def open(self):
		try:
			if self.__use == 'password':
				self.__connector.connect( hostname = self.__host, username = self.__user, password = self.__password )
			elif self.__use == 'sshkey':
				k = paramiko.RSAKey.from_private_key_file(self.__sshkey)
				self.__connector.connect( hostname = self.__host, username = self.__user, pkey = k )
			self.__channel = self.__connector.invoke_shell()
		except AuthenticationException as e:
			self.__status = 'error'
			self.__error = 'Authentication failed for some reason. '+str(e)
		except BadAuthenticationType:
			self.__status = 'error'
			self.__error = 'The server isn\'t allowing the provided authentication type.'
		except BadHostKeyException:
			self.__status = 'error'
			self.__error = 'The host key given by the SSH server did not match what we were expecting.'
		except ChannelException:
			self.__status = 'error'
			self.__error = 'Opening a new channel failed.'
		except NoValidConnectionsError:
			self.__status = 'error'
			self.__error = 'Multiple connection attempts were made and no families succeeded.'
		except PartialAuthentication:
			self.__status = 'error'
			self.__error = 'Partial authentication occured.'
		except PasswordRequiredException:
			self.__status = 'error'
			self.__error = 'A password is needed to unlock a private key file.'
		except ProxyCommandFailure:
			self.__status = 'error'
			self.__error = 'The "ProxyCommand" found in the .ssh/config file returned an error.'
		except SSHException:
			self.__status = 'error'
			self.__error = 'Failures in SSH2 protocol negotiation or logic errors.'
		except Exception as ex:
			self.__status = 'error'
			self.__error = str(ex)
		return self
		
	def close(self):
		if self.__sudo:
			self.execute('rm -r '+self.__sudo)
		self.__connector.close()
		return self
	
	def whoami(self):
		if not self.__whoami:
			self.__whoami = self.execute('whoami').results()[-1]['std_out'].replace("\n","")
		return self.__whoami
	
	def is_keyed(self):
		if os.path.isfile("configs/packages/ssh/"+self.__host+"/"+self.__user+"/id_rsa"):
			return True
		else:
			return False
	
	def get_private_key(self):
		if self.is_keyed():
			f = open("configs/packages/ssh/"+self.__host+"/"+self.__user+"/id_rsa", 'r')
			key = RSA.importKey(f.read())
		else:
			key = RSA.generate(2048)
			if not os.path.isdir("configs/packages/ssh/"+self.__host+"/"+self.__user):
				os.makedirs("configs/packages/ssh/"+self.__host+"/"+self.__user)
			f = open("configs/packages/ssh/"+self.__host+"/"+self.__user+"/id_rsa", 'w')
			f.write(key.exportKey('PEM')+os.linesep)
			f.close()
		return key
		
	def get_public_key(self):
		_use = self.use
		self.use = 'sshkey'
		result = self.execute('cat ~/.shh/authorized_keys | grep '+self.__MUID+'@nufad')
		self.use = _use
		if result['status'] == 'error':
			return self.key().__public_key
		if not result['std_out']:
			return self.key().__public_key
		return result['std_out']
		
	def key(self):
		if self.__status != 'error':
			public = self.get_private_key().publickey().exportKey('OpenSSH')+' '+self.__MUID+'@nufad'+os.linesep
			# Clear out any existing authorized keys based on the NUFAD MUID
			self.execute('cat ~/.ssh/authorized_keys | grep -v '+self.__MUID+'@nufad | tee ~/.ssh/authorized_keys')
			# Create a temp file to stream the new public key to
			temp = self.execute('mktemp').results()[-1]['std_out'].replace("\n","")
			# Stream the new key to the temp file
			self.stream(public, temp)
			# Make sure the .ssh directory exists
			self.execute('mkdir -p ~/.ssh')
			# Append the contents of the temp file to the authorized_key file
			self.execute('cat '+temp+' | tee -a ~/.ssh/authorized_keys')
			self.__public_key = public
		return self
	
	def set_default_user(self):
		if not os.path.isdir("configs/packages/ssh/"+self.__host):
			os.makedirs("configs/packages/ssh/"+self.__host)
		# Sanity check the username to help prevent injection hacks
		user = self.execute('whoami').results()[-1]['std_out'].replace("\n","")
		# Remove any existing default link
		if os.path.exists("configs/packages/ssh/"+self.__host+"/default"):
			os.remove("configs/packages/ssh/"+self.__host+"/default")
		# Create the default link
		os.symlink(user, "configs/packages/ssh/"+self.__host+"/default")
		return self
	
	def execute(self, command):
		if self.__status != 'error':
			result = {}
			result['executed'] = "{}".format( command )
			stdin, stdout, stderr = self.__connector.exec_command(command)
			result['std_out'] = stdout.read()
			try:
				result['json'] = json.loads(stdout.read().replace("\n","").replace("\r","").replace("\t",""))
			except ValueError:
				result['json'] = None
			result['std_error'] = stderr.read()
			self.__results.append(result)
		return self
	
	def sudo(self, command):
		self.execute('whoami')
		if self.results()[-1]['std_out'].replace("\n","") == "root":
			self.execute(command)
		else:
			sudo_error = self.execute('sudo -n true').results()[-1]['std_error']
			if sudo_error == "sudo: a password is required\n":
				if self.execute('command -v openssl').results()[-1]['std_out'].replace("\n",""):
					if not self.__sudo:
						# Force the use of the login password if available to help prevent injection hacks
						if self.__password:
							password = self.__password
						# Encrypt the password we have to use to run sudo
						password = encrypt(self.__passphrase, password.encode("utf-8"))
						# Make a temp file on the remote device and 
						self.__sudo = self.execute('mktemp').results()[-1]['std_out'].replace("\n","")
						# Stream the encrypted password into that file
						self.stream(password+os.linesep, self.__sudo)
					# Use OpenSSH to decrypt the password and pipe the result to sudo
					self.execute('echo $(openssl enc -aes-256-cbc -in '+self.__sudo+' -a -d -salt -pass pass:'+self.__passphrase+') | sudo -S sh -c "'+command+'"')
				else:
					# We don't have a choice but to send the password in plain text.
					# That's fine for the SSH connection, but will be visible in logs.
					self.execute('echo '+self.__password+' | sudo -S sh -c "'+command+'"')
			elif sudo_error.replace("\n","").endswith("sudo: command not found"):
				self.execute(command)
			elif sudo_error:
				# Alert any other errors
				self.__status = 'error'
				self.__error = sudo_error
			else:
				self.execute('sudo sh -c "'+command+'"')
		
		return self
			
	def put(self, source, destination):
		if self.__status != 'error':
			scp = SCPClient(self.__connector.get_transport())
			result = {}
			scp.put(source, recursive=True, remote_path=destination)
			result['status'] = 'success'
			result['message'] = "Put "+source+" in "+self.__user+"@"+self.__host+"/"+destination
			self.__results.append(result)
		return self
	
	def stream(self, content, destination):
		if self.__status != 'error':
			scp = SCPClient(self.__connector.get_transport())
			fl = io.BytesIO()
			fl.write(content)
			fl.seek(0)
			scp.putfo(fl, destination)
			fl.close()
			result = {}
			result['status'] = 'success'
			result['message'] = "Streamed content to "+self.__user+"@"+self.__host+destination
			self.__results.append(result)
		return self
	
	def results(self):
		return self.__results
		
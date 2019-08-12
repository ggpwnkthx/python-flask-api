from .models import *
from core.authentication import User
def get_user(username, **kwargs):
	local_user = AuthMethodLocal.query.filter_by(username=username).first()
	user = User.query.get(int(local_user.uid))
	return user

'''
from main import app
import subprocess
def get_shadow(username):
	user = False
	
	# Read shadow
	process = subprocess.Popen(['sudo','cat',app.config['PACKAGE_AUTH_LOCAL_SHADOW']],stdout=subprocess.PIPE)
	lines, err = process.communicate()
		
	# Parse shadow
	if type(lines) != list:
		lines = lines.splitlines()
		
	if lines:
		for line in lines:
			if line.split(':')[0] == username:
				user = {}
				user['name'] = line.split(':')[0]
				user['no_password'] = False
				user['password'] = {}
				try:
					user['password']['salt'] = "$" + line.split(':')[1].split('$')[1] + "$" + line.split(':')[1].split('$')[2] + "$"
					user['password']['hash'] = line.split(':')[1].split('$')[3]
				except IndexError:
					user['no_password'] = True
				#user['last_change'] = line.split(':')[2]
				#user['min_days'] = line.split(':')[3]
				#user['max_days'] = line.split(':')[4]
				#user['warn'] = line.split(':')[5]
				#user['inactive'] = line.split(':')[6]
				#user['expire'] = line.split(':')[7]
	
	return user
'''

import hashlib, binascii, os
def hash_password(password):
    """Hash a password for storing."""
    salt = hashlib.sha256(os.urandom(60)).hexdigest().encode('ascii')
    pwdhash = hashlib.pbkdf2_hmac('sha512', password.encode('utf-8'), 
                                salt, 100000)
    pwdhash = binascii.hexlify(pwdhash)
    return (salt + pwdhash).decode('ascii')
 
def verify_password(stored_password, provided_password):
    """Verify a stored password against one provided by user"""
    salt = stored_password[:64]
    stored_password = stored_password[64:]
    pwdhash = hashlib.pbkdf2_hmac('sha512', 
                                  provided_password.encode('utf-8'), 
                                  salt.encode('ascii'), 
                                  100000)
    pwdhash = binascii.hexlify(pwdhash).decode('ascii')
    return pwdhash == stored_password
	
import crypt
def is_authenticated(uid, username, password, **kwargs):
	# Check Username
	local_user = AuthMethodLocal.query.get(int(uid))
	if local_user:
		if local_user.username != username:
			return {'status':'error','message':'Username does not match the user id provided.'}
	else:
		return {'status':'error','message':'Username not found.'}
		
	if verify_password(local_user.password, password):
		return {'status':'success'}
	else:
		return {'status':'error','message':'Password incorrect.'}

'''	
	user = get_shadow(username)
	
	if user == False:
		return {'status':'error','message':'Username not found in shadow file.'}
	
	if user['no_password']:
		if password == "":
			return {'status':'success'}
	
	if user['password']:
		if user['password']['salt']:
			if user['password']['salt']+user['password']['hash'] == crypt.crypt(password, user['password']['salt']):
				return {'status':'success'}
			else:
				return {'status':'error','message':'Password hash does not match hash found in shadow file.'}
		else:
			return {'status':'error','message':'Password hash for the username provided not found in shadow file.'}
		return {'status':'error','message':'Huh?'}
	else:
		return {'status':'error','message':'Username not found in shadow file.'}
'''

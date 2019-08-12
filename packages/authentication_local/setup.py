import importlib

def camel(st):
	st = str(st).replace('_', ' ')
	st = ' '.join(''.join([w[0].upper(), w[1:].lower()]) for w in st.split())
	return st.replace(' ', '')

from core.configuration.sql import db
from main import app
from core.logging.api import warning
# Create the tables if they don't exist.
current_tables = db.get_engine(app, 'authentication').table_names()
needed_tables = [u'auth_method_local']
for table in needed_tables:
	if not table in current_tables:
		warning("Creating the "+table+" table in a local SQLite database.")
		class_ = getattr(importlib.import_module('.'.join(__name__.split('.')[:-1])), camel(table))
		if hasattr(class_, '__table__'):
			class_.__table__.create(db.get_engine(app, 'authentication'))
		else:
			class_.create(db.get_engine(app, 'authentication'))

from core.authentication import get_or_add_auth, get_or_add_group
auth_local = get_or_add_auth('.'.join(__name__.split('.')[:-1]))
group_sudoers = get_or_add_group('sudoers')

from core.permissions import get_or_add_permission, allow_group
permission_omni = get_or_add_permission("omnipotent")
if not group_sudoers in permission_omni.groups:
	allow_group(group_sudoers, permission_omni)

# Add nufad local authentication
import os
from .api import register
from core.authentication import add_auth_to_user, add_user_to_group
# Get password
try:
	password = os.environ['NUFAD_PASSWD']
except Exception:
	password = "nufad"
# Register
result = register("nufad",password1=password,password2=password)
if result['status'] == 'success':
	user = result['payload']
	# Give the nufad user authorization to login using authentication_local
	add_auth_to_user(auth_local, user)
	# Add nufad to the sudoers group
	add_user_to_group(user, group_sudoers)
else:
	warning(result['message'])
'''
if os.path.isfile(app.config['PACKAGE_AUTH_LOCAL_GROUP']):
	with open(app.config['PACKAGE_AUTH_LOCAL_GROUP']) as f:
		lines = f.readlines()
		for line in lines:
			if line.split(':')[0] == "sudo":
				for username in line.split(':')[3].split(','):
					result = register(username.rstrip())
					if result['status'] == 'success':
						user = result['payload']
						add_auth_to_user(auth_local, user)
						add_user_to_group(user, group_sudoers)
					else:
						print(result['message'])
'''
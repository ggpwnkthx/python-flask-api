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
needed_tables = [u'permission', u'group_permissions', u'user_permissions']
for table in needed_tables:
	if not table in current_tables:
		warning("Creating the "+table+" table in a local SQLite database.")
		class_ = getattr(importlib.import_module("core.permissions"), camel(table))
		if hasattr(class_, '__table__'):
			class_.__table__.create(db.get_engine(app, 'authentication'))
		else:
			class_.create(db.get_engine(app, 'authentication'))
			
# User with an ID of 0 is considered an Anonymous user.
# An user object is explicitely defined to allow anonymous users to have permissions.
from core.authentication import User
user_anonymous = User.query.get(0)

# Allow anonymous users to use the core.authentication.login API function.
from . import get_or_add_permission, allow_user
permission_login = get_or_add_permission("core.authentication.login")
if not user_anonymous in permission_login.users:
	allow_user(user_anonymous, permission_login)

# Create a permission object that allows a granted user to bypass all security check - similar to a root/administrator account.
get_or_add_permission("omnipotent","Allows users to doing anything.")
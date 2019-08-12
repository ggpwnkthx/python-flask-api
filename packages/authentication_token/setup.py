import importlib
from core.logging.api import info, warning, error

def camel(st):
	st = str(st).replace('_', ' ')
	st = ' '.join(''.join([w[0].upper(), w[1:].lower()]) for w in st.split())
	return st.replace(' ', '')

from core.configuration.sql import db
from main import app
# Create the tables if they don't exist.
current_tables = db.get_engine(app, 'authentication').table_names()
needed_tables = [u'auth_method_token']
for table in needed_tables:
	if not table in current_tables:
		warning("Creating the "+table+" table in a local SQLite database.")
		class_ = getattr(importlib.import_module('.'.join(__name__.split('.')[:-1])), camel(table))
		if hasattr(class_, '__table__'):
			class_.__table__.create(db.get_engine(app, 'authentication'))
		else:
			class_.create(db.get_engine(app, 'authentication'))

from core.authentication import *
auth_token = AuthMethod.query.filter_by(method_class='.'.join(__name__.split('.')[:-1])).first()
if not auth_token:
	warning("Adding the authentication_token authentication method.")
	auth_token = AuthMethod(method_class='.'.join(__name__.split('.')[:-1]))
	db.session.add(auth_token)
	db.session.commit()
	
# TESTING
'''
users = User.query.all()
from . import register
for user in users:
	register(user.get_id())
	enable(user.get_id())
'''
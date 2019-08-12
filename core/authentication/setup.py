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
needed_tables = [u'auth_method', u'user', u'user_auth_methods', u'group', u'user_groups']
for table in needed_tables:
	if not table in current_tables:
		warning("Creating the "+table+" table in a local SQLite database.")
		class_ = getattr(importlib.import_module("core.authentication"), camel(table))
		if hasattr(class_, '__table__'):
			class_.__table__.create(db.get_engine(app, 'authentication'))
		else:
			class_.create(db.get_engine(app, 'authentication'))

from . import add_user
add_user(0, True)
# Use SQLAlchemy as the SQL abstractor.
from flask_sqlalchemy import SQLAlchemy
from main import app
import os

# Instanciate SQLAlchemy
db = SQLAlchemy(app)
# Setup default database
if app.config['SQLALCHEMY_DATABASE_URI']:
	db_filepath = str(app.config['SQLALCHEMY_DATABASE_URI'][10:])
	db_dir = os.path.split(os.path.abspath(db_filepath))[0]

	## Check to make sure the a database file exists.
	if not os.path.exists(db_dir):
		os.makedirs(db_dir)
	if not os.path.isfile(db_filepath):
		### If not, create an empty file.
		open(db_filepath, 'w+').close()

if not app.config['SQLALCHEMY_BINDS']:
	app.config['SQLALCHEMY_BINDS'] = {}

def bind(bind, path):
	db_filepath = str(path[10:])
	db_dir = os.path.split(os.path.abspath(db_filepath))[0]
	if not os.path.exists(db_dir):
		os.makedirs(db_dir)
	if not os.path.isfile(db_filepath):
		### If not, create an empty file.
		open(db_filepath, 'w+').close()
	
	app.config['SQLALCHEMY_BINDS'][bind] = path
	db = SQLAlchemy(app)
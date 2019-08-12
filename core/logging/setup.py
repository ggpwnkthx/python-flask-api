# The purpose of this file is to set up the logging files and provide default formatting.

import logging
from logging.handlers import RotatingFileHandler
from main import app
import os

formatter = logging.Formatter("[%(asctime)s] %(levelname)s - %(message)s")

# Setup info log
if app.config['LOGGING_INFO_FILE']:
	log_filepath = str(app.config['LOGGING_INFO_FILE'])
	log_dir = os.path.split(os.path.abspath(log_filepath))[0]

	## Check to make sure the a database file exists.
	if not os.path.exists(log_dir):
		os.makedirs(log_dir)
	if not os.path.isfile(log_filepath):
		### If not, create an empty file.
		open(log_filepath, 'w+').close()
	info = RotatingFileHandler(log_filepath, maxBytes=10000000, backupCount=5)
	info.setLevel(logging.INFO)
	info.setFormatter(formatter)
	app.logger.addHandler(info)

# Setup warning log
if app.config['LOGGING_WARNING_FILE']:
	log_filepath = str(app.config['LOGGING_WARNING_FILE'])
	log_dir = os.path.split(os.path.abspath(log_filepath))[0]

	## Check to make sure the a database file exists.
	if not os.path.exists(log_dir):
		os.makedirs(log_dir)
	if not os.path.isfile(log_filepath):
		### If not, create an empty file.
		open(log_filepath, 'w+').close()
	warning = RotatingFileHandler(log_filepath, maxBytes=10000000, backupCount=5)
	warning.setLevel(logging.WARNING)
	warning.setFormatter(formatter)
	app.logger.addHandler(warning)

# Setup error log
if app.config['LOGGING_ERROR_FILE']:
	log_filepath = str(app.config['LOGGING_ERROR_FILE'])
	log_dir = os.path.split(os.path.abspath(log_filepath))[0]

	## Check to make sure the a database file exists.
	if not os.path.exists(log_dir):
		os.makedirs(log_dir)
	if not os.path.isfile(log_filepath):
		### If not, create an empty file.
		open(log_filepath, 'w+').close()
	error = RotatingFileHandler(log_filepath, maxBytes=10000000, backupCount=5)
	error.setLevel(logging.ERROR)
	error.setFormatter(formatter)
	app.logger.addHandler(error)

#Format the stdout logging
from flask.logging import default_handler
default_handler.setFormatter(formatter)
# The exposes a very simple API for the logging system.
from main import app
import logging

# Log an informative message
def info(message):
	app.logger.setLevel(logging.INFO)
	app.logger.info(message)

# Log a warning message
def warning(message):
	app.logger.setLevel(logging.WARNING)
	app.logger.warning(message)

# Log an error message
def error(message):
	app.logger.setLevel(logging.ERROR)
	app.logger.error(message)
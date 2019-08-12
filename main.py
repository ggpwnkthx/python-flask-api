# Flask is a basic framework used
from flask import Flask

# Instanciate the app
app = Flask(__name__)
# Load the initial config values
app.config.from_pyfile("configs/app.ini")

# Import all core modules
from core import *
# Import all add-on modules
from packages import *

# Initialize the app
if __name__ == "__main__":
    app.run(host='0.0.0.0')
	
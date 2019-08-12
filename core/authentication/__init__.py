# Keep the authentication database separate from the application's default database.
from main import app
from core.configuration.sql import db, bind
bind('authentication', app.config['CORE_AUTHENTICATION_DATABASE_URI'])

# Load all the appropriate files.
from .models import *
from .protected import *
from .api import *
from .setup import *
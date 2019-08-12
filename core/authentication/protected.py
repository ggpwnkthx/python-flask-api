# The purpose of this file is to define an internally used functions for this module.
# Function names should be self-explanitory.

from core.logging.api import info
from .models import *
from core.configuration.sql import db
def add_auth(class_):
	info("Adding authentication method '"+class_+"'.")
	auth = AuthMethod(method_class=class_)
	db.session.add(auth)
	db.session.commit()
	return auth
def get_auth_by_id(id):
	return AuthMethod.query.get(id)
def get_auth_by_name(name):
	return AuthMethod.query.filter_by(permission_name=name).first()
def get_or_add_auth(class_):
	auth = AuthMethod.query.filter_by(method_class=class_).first()
	if not auth:
		auth = add_auth(class_)
	return auth
def delete_auth(auth):
	info("Deleting authentication method '"+class_+"'.")
	db.session.delete(auth)
	db.session.commit()
def add_auth_to_user(auth, user):
	info("Adding authentication method '"+auth.method_class+"' to user "+str(user.uid)+".")
	user.auth_methods.append(auth)
	db.session.commit()
def remove_auth_from_user(user, auth):
	info("Removing authentication method '"+auth.method_class+"' from user "+str(user.uid)+".")
	user.auth_methods.remove(auth)
	db.session.commit()
def add_user(id = None, active = False):
	user = User.query.get(id)
	if not user:
		user = User(uid=id,is_active=active)
		db.session.add(user)
		db.session.commit()
		info("Added user "+str(user.uid)+".")
	return user
def get_user_by_id(id):
	return User.query.get(id)
def delete_user(user):
	info("Deleting user "+str(user.uid)+".")
	db.session.delete(user)
	db.session.commit()
def add_group(name, description):
	info("Adding group '"+name+"'.")
	group = Group(group_name=name, group_description=description)
	db.session.add(group)
	db.session.commit()
	return group
def get_group_by_id(id):
	return Group.query.get(id)
def get_group_by_name(name):
	return Group.query.filter_by(permission_name=name).first()
def get_or_add_group(name, description = None):
	group = Group.query.filter_by(group_name=name, group_description=description).first()
	if not group:
		group = add_group(name, description)
	return group
def delete_group(group):
	info("Deleting group '"+group.group_name+".")
	db.session.delete(group)
	db.session.commit()
def add_user_to_group(user, group):
	info("Adding user "+str(user.uid)+" to the '"+group.group_name+"' group.")
	group.users.append(user)
	db.session.commit()
def remove_user_from_group(user, group):
	info("Removing user "+str(user.uid)+" from the '"+group.group_name+"' group.")
	group.users.remove(user)
	db.session.commit()

# Login Management
from flask_login import LoginManager
from main import app
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.session_protection = "strong"

@login_manager.user_loader
def load_user(user_id):	
	return User.query.get(int(user_id))

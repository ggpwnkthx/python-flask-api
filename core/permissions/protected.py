from core.logging.api import info
from .models import Permission
from core.configuration.sql import db
def add_permission(name, description):
	permission = Permission(permission_name=name, permission_description=description)
	info("Creating '"+name+"' permission.")
	db.session.add(permission)
	db.session.commit()
	return permission
def get_permission_by_id(id):
	return Permission.query.get(id)
def get_permission_by_name(name):
	return Permission.query.filter_by(permission_name=name).first()
def get_or_add_permission(name, description = None):
	permission = Permission.query.filter_by(permission_name=name).first()
	if not permission:
		permission = add_permission(name, description)
	return permission
def delete_permission(permission):
	info("Deleting '"+permission.permision_name+"' permission.")
	db.session.delete(permission)
	db.session.commit()
def allow_user(user, permission):
	info("Allowing user "+str(user.uid)+" to use '"+permission.permission_name+"'.")
	permission.users.append(user)
	db.session.commit()
def deny_user(user, permission):
	info("Denying user "+str(user.uid)+" to use of '"+permission.permission_name+"'.")
	permission.users.remove(user)
	db.session.commit()
def allow_group(group, permission):
	info("Allowing group '"+group.group_name+"' to use '"+permission.permission_name+"'.")
	permission.groups.append(group)
	db.session.commit()
def deny_group(group, permission):
	info("Denying group '"+group.group_name+"' to use of '"+permission.permission_name+"'.")
	permission.groups.remove(group)
	db.session.commit()

from flask_login import current_user
from core.authentication import AuthMethod, User
def can(permission, user = current_user ):
	# Check if logged in
	if not user.get_id():
		user = User.query.get(0)
	
	# Verify session authenticity
	authenticity = user.is_authenticated()
	if authenticity['status'] == 'error':
		return authenticity
	# Check the user's permission stack
	if isinstance(permission, str) or isinstance(permission, unicode):
		permission = Permission.query.filter_by(permission_name=permission).first()
	if permission:
		if user in permission.users:
			return {'status':'success'}
		if permission.groups:
			for g in permission.groups:
				if user in g.users:
					return {'status':'success'}
	permission_omni = Permission.query.filter_by(permission_name="omnipotent").first()
	if user in permission_omni.users:
		return {'status':'success'}
	if permission_omni.groups:
		for g in permission_omni.groups:
			if user in g.users:
				return {'status':'success'}
	return {'status':'error','message':'You do not have permission to do that.'}

from functools import wraps
from flask import jsonify
def protect(user):
	def wrapper(view_function):
		@wraps(view_function)
		def decorator(*args, **kwargs):
			validation = can(user, view_function.__module__+"."+view_function.__name__)
			if validation['status'] == 'error':
				return jsonify(validation)
			# User is allowed, so let's do it
			return view_function(*args, **kwargs)
		return decorator
	return wrapper
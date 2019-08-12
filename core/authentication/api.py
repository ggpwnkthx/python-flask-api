from .models import AuthMethod	
from flask_login import login_user, login_required, logout_user
from flask import session
import os
import importlib
def login(method, args):
	if isinstance(method, str) or isinstance(method, unicode) :
		method = AuthMethod.query.filter_by(method_class=method).first()
		if not method:
			return {'status':'error', 'message':'Authentication method not found.'}
	class_ = importlib.import_module(method.method_class)
	if class_:
		user = class_.get_user(**args)
		if user:
			if not method in user.auth_methods:
				return {'status':'error','message':'This session\'s authentication method is not, or is no longer, enabled for the current user.'}
			if user.is_active:
				authentication = user.authenticate(method, args)
				if authentication['status'] == 'success':
					if login_user(user):
						session['authenticated_by'] = method.method_class
						session['muid'] = os.environ['MUID']
						return {'status':'success'}
					else:
						return {'status':'error','message':'An unknown error occured while creating the user session.'}
				else:
					return authentication
			else:
				return {'status':'error','message':'User is not activated.'}
		return {'status':'error','message':'No user found with those credentials and/or the method used.'}
	return {'status':'error','message':'Authentication method not found.'}

@login_required
def logout():
	logout_user()
	return {'status':'success'}
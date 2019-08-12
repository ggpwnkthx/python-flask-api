from .models import *
from .protected import *
from core.authentication import User
from core.configuration.sql import db
from core.logging.api import info, warning, error
from pprint import pprint
def register(username, **kwargs):
	local_user = AuthMethodLocal.query.filter_by(username=username).first()
	if local_user:
		return {'status':'error', 'message':'Username already registered.'}
	else:
		try:
			if kwargs['password1'] == kwargs['password2']:
				password = hash_password(kwargs['password1'])
			else:
				return{'status':'error','message':'Passwords do not match'}
		except NameError:
			return{'status':'error','message':'No password supplied.'}
			
		user = None
		try:
			user = User.query.get(int(uid))
			try:
				if not verify_password(user.password,kwargs['password0']):
					return{'status':'error','message':'Current password incorrect.'}
			except NameError:
				return{'status':'error','message':'Current password not supplied.'}
		except NameError:
			user = User(is_active=True)
			db.session.add(user)
			db.session.commit()
			
		local_user = AuthMethodLocal(uid=user.get_id(),username=username,password=password)
		db.session.add(local_user)
		db.session.commit()
		info("Registered '"+username.rstrip()+"' with User ID: "+str(user.get_id()))
		return {'status':'success','payload':user}

from core.configuration.sql import db
from core.authentication import User
from core.logging.api import info, warning, error
from .models import *
from .protected import *

def register(uid, **kwargs):
	token_user = AuthMethodToken.query.filter_by(uid=uid).first()
	if token_user:
		return {'status':'error', 'message':'User already has a token.'}
	else:
		user = User.query.get(int(uid))
		if not user:
			return {'status':'error', 'message':'User does not exist.'}
		
		token = generate_token()
		token_user = AuthMethodToken(uid=user.get_id(),token=token)
		db.session.add(token_user)
		db.session.commit()
		
		info("Token generated: "+str(user.get_id())+"$"+token)
		
		return {'status':'success','payload':user}

def enable(uid):
	user = User.query.get(int(uid))
	if not user:
		return {'status':'error','message':'User does not exist.'}
	return {'status':'success'}
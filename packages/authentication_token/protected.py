from .models import *
from core.authentication import User

def get_user(token, **kwargs):
	token_user = AuthMethodToken.query.filter_by(token=token).first()
	user = User.query.get(int(token_user.uid))
	return user

def is_authenticated(token, **kwargs):
	# Check Username
	token_user = AuthMethodToken.query.filter_by(token=token).first()
	if token_user:
		return {'status':'success'}
	else:
		return {'status':'error','message':'Token does not exist.'}

#from os import urandom
import secrets
def generate_token():
	#token = urandom(24).encode('hex')
	token = secrets.token_hex(24)
	if AuthMethodToken.query.filter_by(token=token).first():
		token = generate_token()
	return token

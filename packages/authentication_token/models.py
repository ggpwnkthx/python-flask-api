from core.configuration.sql import db

class AuthMethodToken(db.Model):
	__bind_key__ = 'authentication'
	uid = db.Column(db.Integer, primary_key=True)
	token = db.Column(db.String(256), unique=True)
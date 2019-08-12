from core.configuration.sql import db

class AuthMethodLocal(db.Model):
	__bind_key__ = 'authentication'
	uid = db.Column(db.Integer, primary_key=True)
	username = db.Column(db.String(256), unique=True)
	password = db.Column(db.String(256), unique=True)
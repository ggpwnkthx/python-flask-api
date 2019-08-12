# The purpose of this file it to define the SQLAlchemy database models.
from core.configuration.sql import db

# Declare the database tables.
UserAuthMethods = db.Table('user_auth_methods',
	db.Column('uid', db.Integer, db.ForeignKey('user.uid')),
	db.Column('amid', db.Integer, db.ForeignKey('auth_method.amid'))
)
UserGroups = db.Table('user_groups',
	db.Column('uid', db.Integer, db.ForeignKey('user.uid')),
	db.Column('gid', db.Integer, db.ForeignKey('group.gid'))
)

from main import app
from flask_login import UserMixin, logout_user
import importlib
import os
from flask import session
class User(UserMixin, db.Model):
	__bind_key__ = 'authentication'
	uid = db.Column(db.Integer, primary_key=True)
	auth_methods = db.relationship('AuthMethod', secondary=UserAuthMethods, backref=db.backref('users_auth_methods', lazy='dynamic'))
	groups = db.relationship('Group', secondary=UserGroups, backref=db.backref('users_groups', lazy='dynamic'))
	is_active = db.Column(db.Boolean, default=False, nullable=False)
	is_anonymous = False
	def is_authenticated(self):
		if self.uid == 0:
			return {'status':'success'}
		# Check if session has matching machine unique identifier
		if not 'muid' in session:
			logout_user()
			return {'status':'error','message':'Machine identifier not set.'}
		if not session['muid'] == app.config['MUID']:
			logout_user()
			return {'status':'error','message':'Machine identifier not not match any this system.'}
		# Check how the session was authenticated
		if not 'authenticated_by' in session:
			logout_user()
			return {'status':'error','message':'Authentication method for the current session not set.'}
		method = AuthMethod.query.filter_by(method_class=session['authenticated_by']).first()
		if not method:
			logout_user()
			return {'status':'error','message':'This session\'s authentication method is not supported.'}
		# Double check that the user is allowed to login that way
		if not method in self.auth_methods:
			logout_user()
			return {'status':'error','message':'This session\'s authentication method is not, or is no longer, enabled for the current user.'}
		return {'status':'success'}
	def authenticate(self, method, variables):
		if method in self.auth_methods:
			if isinstance(method, str):
				method = AuthMethod.query.filter_by(method_class=method).first()
			class_ = importlib.import_module(method.method_class)
			authentication = class_.is_authenticated(self.uid, **variables)
			if authentication['status'] == 'success':
				self.authenticated_by = method
			return authentication
		return {'status':'error','message':'Authentication method is not available for the user provided.'}
	def get_id(self):
		#return unicode(self.uid)
		return self.uid

class AuthMethod(db.Model):
	__bind_key__ = 'authentication'
	amid = db.Column(db.Integer, primary_key=True)
	method_class = db.Column(db.String(256), unique=True)
class Group(db.Model):
	__bind_key__ = 'authentication'
	gid = db.Column(db.Integer, primary_key=True)
	group_name = db.Column(db.String(256), unique=True)
	group_description = db.Column(db.Text(), unique=True)
	users = db.relationship('User', secondary=UserGroups, backref=db.backref('groups_users', lazy='dynamic'))
	
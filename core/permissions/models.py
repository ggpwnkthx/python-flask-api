from core.configuration.sql import db
UserPermissions = db.Table('user_permissions',
	db.Column('uid', db.Integer, db.ForeignKey('user.uid')),
	db.Column('pid', db.Integer, db.ForeignKey('permission.pid'))
)
GroupPermissions = db.Table('group_permissions',
	db.Column('gid', db.Integer, db.ForeignKey('group.gid')),
	db.Column('pid', db.Integer, db.ForeignKey('permission.pid'))
)
class Permission(db.Model):
	__bind_key__ = 'authentication'
	pid = db.Column(db.Integer, primary_key=True)
	permission_name = db.Column(db.String(256), unique=True)
	permission_description = db.Column(db.Text(), unique=True)
	users = db.relationship('User', secondary=UserPermissions, backref=db.backref('permissions_users', lazy='dynamic'))
	groups = db.relationship('Group', secondary=GroupPermissions, backref=db.backref('permissions_groups', lazy='dynamic'))
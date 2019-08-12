from . import protected as perm_logic
from core.authentication import protected as auth_logic
def add(name, description):
	try:
		p = perm_logic.add_permission(name, description)
	except e:
		return {'status':'error','message':str(e)}
	return {'status':'success'}
def get(id = None, name = None):
	if id:
		try:
			p = perm_logic.get_permission_by_id(id)
			result = {'status':'success','payload':{'id':p.pid,'name':p.permision_name,'description':p.permission_description,'users':[],'groups':[]}}
		except e:
			return {'status':'error','message':str(e)}
	if name:
		try:
			p = perm_logic.get_permission_by_name(name)
			result = {'status':'success','payload':{'id':p.pid,'name':p.permision_name,'description':p.permission_description,'users':[],'groups':[]}}
		except e:
			return {'status':'error','message':str(e)}
	return {'status':'error','message':'Name or ID not specified.'}
def delete(id):
	try:
		perm_logic.delete(perm_logic.get_permission_by_id(id))
	except e:
		return {'status':'error','message':str(e)}
	return {'status':'success'}
def allow(permission, user = None, group = None):
	if isnumeric(permission):
		p = perm_logic.get_permission_by_id(permission)
	else:
		p = perm_logic.get_permission_by_id(permission['id'])
	if user_id:
		try:
			if isnumeric(user):
				u = auth_logic.get_user_by_id(user)
			else:
				u = auth_logic.get_user_by_id(user['id'])
			perm_logic.allow_user(u, p)
			result = {'status':'success'}
		except e:
			return {'status':'error','message':str(e)}
	if group_id:
		try:
			if isnumeric(user):
				g = auth_logic.get_group_by_id(group)
			else:
				g = auth_logic.get_group_by_id(group['id'])
			perm_logic.allow_group(u, p)
			result = {'status':'success'}
		except e:
			return {'status':'error','message':str(e)}
	return {'status':'error','message':'User or Group not specified.'}
def deny(permission, user = None, group = None):
	if isnumeric(permission):
		p = perm_logic.get_permission_by_id(permission)
	else:
		p = perm_logic.get_permission_by_id(permission['id'])
	if user_id:
		try:
			if isnumeric(user):
				u = auth_logic.get_user_by_id(user)
			else:
				u = auth_logic.get_user_by_id(user['id'])
			perm_logic.deny_user(u, p)
			result = {'status':'success'}
		except e:
			return {'status':'error','message':str(e)}
	if group_id:
		try:
			if isnumeric(user):
				g = auth_logic.get_group_by_id(group)
			else:
				g = auth_logic.get_group_by_id(group['id'])
			perm_logic.deny_group(u, p)
			result = {'status':'success'}
		except e:
			return {'status':'error','message':str(e)}
	return {'status':'error','message':'User or Group not specified.'}
from .models import Connection
import os
def execute(commands, host = None, user = None, password = None):
	if not host:
		host = "172.17.0.1"
	if host == "localhost":
		host = "172.17.0.1"
	if not user:
		user=os.environ['SSH_USER']
	
	sshkey = "configs/packages/ssh/"+host+"/"+user+"/id_rsa"
	if not password:
		if not os.path.isfile(sshkey):
			return {'status':'failed', 'message':'Private SSH key for '+user+'@'+host+' was not found.'}
		ssh = Connection(host, user, sshkey = sshkey)
	else:
		ssh = Connection(host, user, password = password)
	
	results = {}
	results['status'] = 'success'
	results['payload'] = []
	for command in commands:
		results['payload'].append(ssh.do('execute', command))
	return results
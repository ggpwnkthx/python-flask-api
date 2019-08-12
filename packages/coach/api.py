from .protected import *

def get_steps():
	steps = []
	steps.append('bootstrap')
	steps.append('change_hostname')
	steps.append('update_kernel_headers')
	steps.append('update_kernel_image')
	steps.append('enable_infiniband')
	steps.append('auto_bonding')
	steps.append('auto_ceph')
	steps.append('fabric')
	steps.append('update_hosts')
	steps.append('ceph_deploy')
	steps.append('dnsmasq')
	return {'steps':steps}

def run(step, *args, **kwargs):
	steps = get_steps()
	function = steps['steps'][int(step)]
	results = eval(function)(*args, **kwargs)
	return {'status':'success','results':results,'next':int(step)+1}
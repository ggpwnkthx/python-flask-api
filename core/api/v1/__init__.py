# This is version 1 of the API.
# The purpose of this API is to expose any module's api to the web server
from main import app
from flask_restful import Api, Resource

from pprint import pprint

# Set a URI prefix to avoid request collisions with other modules.
api = Api(app, prefix="/api/v1")

import json
from flask import request, jsonify
from flask_login import current_user
from core import permissions
import traceback
class Execute(Resource):
	# A GET request will show what API functions the current user has permission to use.
	def get(self):
		cat = catalog()
		for method_key, method_details in cat.copy().items():
			for function_key, function_details in method_details.copy().items():
				if permissions.can(method_key+'.'+function_key)['status'] == 'error':
					cat[method_key].pop(function_key)
			if len(method_details) == 0:
				cat.pop(method_key)
		return jsonify(cat)
	
	# A POST request expects a JSON body.
	# The JSON is expected to have either a singular 'action' element,
	# or an 'actions' element that expresses a list of functions to evaluate.
	# Actions will be evaluated in the order in which they are received.
	def post(self):
		results = []
		try:
			body = json.loads(request.data)
			if 'action' in body.keys():
				results.append(evaluate(body['action']))
			if 'actions' in body.keys():
				for action in body['actions']:
					results.append(evaluate(action))
			return jsonify(results)
		except Exception as ex:
			results.append({'status':'error','message':'Malformed request.'})
			return jsonify(results)
			
# This exposes the above class to the Flask-RESTful API
api.add_resource(Execute, '/')

# This validates and evaluates the actions passed from the API request.
import importlib
def evaluate(action):
	results = {}
	list = catalog()
	# Validate module
	if 'module' in action.keys():
		results['module'] = action['module']
		if action['module'] in list.keys():
			# Load module
			try:
				module = importlib.import_module(action['module']+'.api')
			except ImportError as e:
				results['status'] = 'error'
				results['message'] = str(e)
				return results
		else:
			results['status'] = 'error'
			results['message'] = 'Specified module is not supported by this API.'
			return results
	else:
		return {'status':'error', 'message':'No module specified.'}
	
	# Validate function
	if 'function' in action.keys():
		results['function'] = action['function']
		if action['function'] in list[action['module']].keys():
			# Get function
			try:
				function = getattr(module, action['function'])
			except KeyError:
				results['status'] = 'error'
				results['message'] = 'No function specified.'
				return results
			except AttributeError:
				results['status'] = 'error'
				results['message'] = 'That function is not defined in the \''+action['module']+'\' module.'
				return results
		else:
			results['status'] = 'error'
			results['message'] = 'Specified function is not supported by this API.'
			return results
	else:
		results['status'] = 'error'
		results['message'] = 'No function specified.'
		return results
	
	# Validate permission
	permission = action['module']+'.'+action['function']
	validation = permissions.can(permission)
	if validation['status'] == 'error':
		#results.update(validation)
		return results
	
	# Set Arguments
	try:
		arguments = action['arguments']
	except KeyError:
		arguments = {}
		
	# Evaluate
	try:
		if len(arguments) > 0:
			results.update(function(**arguments))
		else:
			results.update(function())
		return results
	except Exception as ex:
		results['status'] = 'error'
		results['error'] = str(type(ex).__name__)
		results['message'] = str(ex)
		results['traceback'] = traceback.format_exc()
		return results

# This returns a complete list of available API functions regardless of the current user's permissions.
def catalog():
	from os.path import basename, isdir, isfile
	import glob
	core_list = glob.glob('./core/*')
	modules = []
	for i in core_list:
		if isdir(i):
			modules.append(i)
	package_list = glob.glob('./packages/*')
	for i in package_list:
		if isdir(i):
			modules.append(i)
	
	import inspect
	import importlib
	list = {}
	for m in modules:
		item = {}
		try:
			mymodule = importlib.import_module('.'.join(m.split('/')[1:])+'.api')
		except ImportError:
			pass
		try:	
			for element_name in dir(mymodule):
				element = getattr(mymodule, element_name)
				if inspect.isclass(element):
					pass
				elif inspect.ismodule(element):
					pass        
				elif hasattr(element, '__call__'):
					if not inspect.isbuiltin(element):                   
						try:
							if element.__module__ == mymodule.__name__:
								data = inspect.getargspec(element)
								item[element_name] = []
								if data.args:
									for a in data.args:
										item[element_name].append(a)
								if isinstance(data.varargs, str):
									item[element_name].append('*'+data.varargs)
								if isinstance(data.keywords, str):
									item[element_name].append('**'+data.keywords)
						except:
							pass
				qualname = '.'.join(mymodule.__name__.split('.')[:-1])
				list[qualname] = item
		except UnboundLocalError:
			pass
	
	return list
# The purpose of this file is to automatically load all the core modules.

# Look at all the ./core sub-directories and create a list of modules to load later.
from os.path import dirname, basename, isdir, isfile
import glob
relative = dirname(__file__)
dir_list = glob.glob(relative+"/*")
modules = []
for i in dir_list:
	if isdir(i):
		modules.append(i)

# Load the default config.ini file from the module directory.
# If a config.ini file is found in the ./configs/[module name] directory, load that as well - existing config values will be overwritten.
# If a [module name].ini file is found in the ./configs directory, load that as well - existing config values will be overwritten.
import main
for m in modules:
	if isdir(m):
		config = [m+"/config.ini", "./configs"+m[1:]+"/config.ini", "./configs"+m[1:]+".ini"]
		for c in config:
			if isfile(c):
				main.app.config.from_pyfile(c)

# The core modules require being loaded in a particular order.
order = ['configuration', 'logging', 'api', 'authentication']
for m in order[::-1]:
	if relative+'/'+m in modules:
		modules.insert(0, modules.pop(modules.index(relative+'/'+m)))

# Import the ordered list of core modules.
__all__ = [ basename(m) for m in modules if isdir(m) ]
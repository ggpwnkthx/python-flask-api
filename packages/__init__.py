from os.path import dirname, basename, isdir, isfile
import glob
modules = glob.glob(dirname(__file__)+"/*")
__all__ = [ basename(m) for m in modules if isdir(m) ]

import main
for m in modules:
	if isdir(m):
		config = [m+"/config.ini", "./configs"+m[1:]+"/config.ini", "./configs"+m[1:]+".ini"]
		for c in config:
			if isfile(c):
				main.app.config.from_pyfile(c)
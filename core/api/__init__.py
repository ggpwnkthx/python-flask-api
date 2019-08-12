# It is expected that the API for this product may change in the future.
# It is important that we do not break systems that rely on previous version of the API.
# So we'll load all the API version found in this directory.

from os.path import dirname, basename, isdir, isfile
import glob
modules = glob.glob(dirname(__file__)+"/*")
import importlib
for mod in [ basename(m) for m in modules if isdir(m) ]:
	importlib.import_module(__name__+"."+mod)
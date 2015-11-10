from __future__ import division
import os
import subprocess as sp
import xml.etree.ElementTree as ET
import multiprocessing as mp
#import DyMat

# TODO: Add in option for different result file output
# TODO: Need to add in error checking for calls (possibly use in tests)

class Simulator(object):
	"""Compilation and simulation of a modelica model.

	The suffix is applied to the init file names written and read by the
	simulator.  This can be changed after construction and thereafter changes
	calls to `write_init`, `update_pars` and `simulate`.
	"""
	def __init__(self, fn, model=None, suffix=None):
		self.fn = fn
		if model is None:
			self.model = os.path.splitext(os.path.split(self.fn)[1])[0]
		else:
			self.model = model
		self.suffix = suffix
		self.makefile_fn = self.model + '.makefile'
		self.init_fn = self.model + '_init.xml'
		self.init_et = None
	
	def get_init_out_fn(self):
		if self.suffix is None:
			return self.init_fn
		else:
			return self.model + '_init_' + self.suffix + '.xml'
	
	def compile_model(self, n_proc=0, libs=['Modelica', 'SolarTherm'], args=[]):
		"""Compile modelica model in .mo file."""
		sp.call(['omc', '-s', '-q', '-n='+str(n_proc)]
			+ args
			+ ['-i='+self.model, self.fn]
			+ libs)

	def compile_sim(self, n_jobs=(1 + mp.cpu_count()//2), args=[]):
		"""Compile model source code into a simulation executable."""
		sp.call(['make', '-j', str(n_jobs), '-f', self.makefile_fn] + args)

	def load_init(self):
		"""Load in init XML."""
		self.init_et = ET.parse(self.init_fn)

	def write_init(self):
		"""Write new init XML with optional suffix."""
		self.init_et.write(self.get_init_out_fn())

	def clear_init(self):
		"""Clear init XML."""
		self.init_et = None

	def update_et_pars(self, par_n, par_v):
		"""Update parameter values in internal XML.

		The values of parameters will fail to change in the simulation if they
		are final (protected).  This can happen indirectly if a final parameter
		derives its value from a non-final changed parameter.
		"""
		root = self.init_et.getroot()

		for i, n in enumerate(par_n):
			root.find('*ScalarVariable[@name=\''+n+'\']/*[@start]').attrib['start'] = par_v[i]

	def update_pars(self, par_n, par_v):
		"""Update parameters values in XML and write results to file."""
		if self.init_et is None:
			self.load_init()
		
		self.update_et_pars(par_n, par_v)
		self.write_init()

	def simulate(self, start='0', stop='86400', step='60', solver='rungekutta', args=[]):
		"""Run simulation."""
		sim_args = [
			'-override', 'startTime='+str(start)+',stopTime='+str(stop)
				+',stepSize='+str(step),
			'-s', solver,
			'-f', self.get_init_out_fn(),
			]
		sp.call(['./'+self.model] + sim_args + args)
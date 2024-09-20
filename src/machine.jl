

function simplifyState(s::MachineState)
	# prevent any chance of eventual overflow of the rotation state
	# the stepper can go around and around indefinitely but the integer cannot
	s.r = s.r % stepsPerRevolutionR
end

const stepsPerRevolutionR::Int = 200

mutable struct MachineStateSteps
	# all in stepper steps
	x::Int	# x axis
	y::Int	# y axis
	z::Int	# z axis (head in/out)
	r::Int	# roll (nozzle rotation axis)
	p::Int	# pitch (head pitch axis)
end

mutable struct MachineStateOptical
	# all in stepper steps
	x::Float64	# x axis, normalised
	y::Float64	# y axis, normalised
	z::Bool		# z axis, extended=true retracted=false
	r::Float64	# roll, radians (nozzle rotation axis)
	p::Bool		# pitch (head pitch axis)
end

function simplifyState(s::MachineState)
	# prevent any chance of eventual overflow of the rotation state
	# the stepper can go around and around indefinitely but the integer cannot
	s.r = s.r % stepsPerRevolutionR
end

function Base.+(a::MachineStateSteps, b::MachineStateOptical)
	# more natural conversion function
end
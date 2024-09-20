import Base.+	# so we can extend it

mutable struct MachineState
	# all in stepper steps
	home::ComplexF64 	# where the home position is with respect to the datum 	# TODO do I want to temporarily forget about this frame of reference stuff and make this more comprehensible?
	z::Float64			# z axis position
	r::Float64			# roll, radians (nozzle rotation axis)
	p::Float64			# pitch, radians (head pitch axis)
	v::Bool				# vacuum #? — does this belong here?
end

struct ArbitraryRotation
	# rotation about arbitrary ("virtual") axis
	angle::Float64				# rad
	virtualCentre::ComplexF64	# mm
	ArbitraryRotation(angle, virtualCentre=0.0+0.0j) = new(angle, virtualCentre) 
end

mutable struct CompoundMovement
	
	xy::ComplexF64				# mm
	r::Float64					# rad
	
	CompoundMovement(xy::ComplexF64, r::Float64=0.0) = new(xy, r)
	
	function CompoundMovement(ar::ArbitraryRotation)
		# nozzle axis is the datum
		# convert rotation to something achievable
		# basically we just do the rotation anyway, predict where the virtual
		# centre of rotation will end up, and then move the PCB by the same
		# amount to "catch" the virtual centre of rotation (so it appears not
		# to have moved at all)
		correctiveTranslation = ar.virtualCentre*(1-cis(ar.angle))
		new(correctiveTranslation, ar.angle)
	end

end

function simplifyState(s::MachineState)
	# prevent any chance of eventual overflow of the rotation state
	# the stepper can go around and around indefinitely but the integer cannot
	s.r = s.r % stepsPerRevolutionR
end

function +(m1::CompoundMovement, m2::CompoundMovement)
	return CompoundMovement(
		m1.xy + m2.xy,
		m1.angle + m2.angle
	)
end

function +(ms::MachineState, cm::CompoundMovement)
	return MachineState(
		ms.home + cm.xy,
		ms.z,
		ms.r + cm.r,
		ms.p,
		ms.v
	)
end


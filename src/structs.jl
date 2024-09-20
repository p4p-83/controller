mutable struct MachineState
	# all in stepper steps
	home::ComplexF64 	# where the home position is with respect to the datum
	z::Float64			# z axis position
	r::Float64			# roll, radians (nozzle rotation axis)
	p::Float64			# pitch, radians (head pitch axis)
	v::Bool				# vacuum #? — does this belong here?
end

# struct NominalTranslation
# 	xy::ComplexF64				# mm
# end

struct NominalRotation
	# rotation about arbitrary ("virtual") axis
	angle::Float64				# rad
	virtualCentre::ComplexF64	# mm
	NominalRotation(angle, virtualCentre=0.0+0.0j) = new(angle, virtualCentre) 
end

mutable struct CompoundMovement
	
	xy::ComplexF64				# mm
	r::Float64					# rad
	
	CompoundMovement(xy::ComplexF64, r::Float64=0.0) = new(xy, r)
	
	function CompoundMovement(nr::NominalRotation)
		# nozzle axis is the datum
		# convert rotation to something achievable
		correctiveTranslation = n.virtualCentre*(1-cis(n.angle))
		new(correctiveTranslation, n.angle)
	end

	# function CompoundMovement(nt::NominalTranslation)
	# 	new(nt.xy, 0.0)
	# end

end

function simplifyState(s::MachineState)
	# prevent any chance of eventual overflow of the rotation state
	# the stepper can go around and around indefinitely but the integer cannot
	s.r = s.r % stepsPerRevolutionR
end

import Base.+
function +(m1::CompoundMovement, m2::CompoundMovement)
	return CompoundMovement(
		m1.xy + m2.xy,
		m1.angle + m2.angle
	)
end

function +(ms::MachineState, cm::CompoundMovement)
	ms.xy += cm.xy
	ms.r += cm.r
end


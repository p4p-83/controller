# motion.jl
# adapts movement descriptions —> movement instructions —> gcodes
# and then dispatches them

# performs bounds checking and manages work coordinates to keep numbers known

# note I was kind of planning to write this in a way that would let in-progress moves
# be cancelled mid-way-through
# but then I didn't, 'cause that's kind of hard and I have little time left with this project

using Base.Threads, LibSerialPort
import PiGPIO							# TODO prompt the user to run `sudo pigpiod` before running this  

const coneLimitPin::Int = 0				# TODO wiring
const headHomePin::Int = 1		 		# TODO wiring

# instances
const piGpioInstance = PiGPIO.Pi()
const gantryIo::LibSerialPort.SerialPort = open("/dev/ttyUSB0", 115200)
const headIo::LibSerialPort.SerialPort = open("/dev/ttyACM0", 115200)

# set switches up preemptively
PiGPIO.set_mode(piGpioInstance, coneLimitPin, PiGPIO.INPUT)
PiGPIO.set_mode(piGpioInstance, headHomePin, PiGPIO.INPUT)
# PiGPIO.set_pull_up_down(piGpioInstance, coneLimitPin, PiGPIO.PUD_UP) # TODO review
# PiGPIO.set_pull_up_down(piGpioInstance, headHomePin, PiGPIO.PUD_UP) # TODO review

###################
# TYPES TO REPRESENT MOVEMENTS

@enum StartupManoeuvres begin
	homeHead
	homeGantry
end

@enum HeadManoeuvres begin
	lower
	raise
	pick
	place
end

struct ComponentMotion
	dx::Float64		# µm
	dy::Float64		# µm
	dr::Float64		#! in revolutions (i.e. 0.25 would represent 90°)

	ComponentMotion(;dx=0, dy=0, dr=0) = new(dx, dy, dr)

	function ComponentMotion(ucm::UncalibratedComponentMotion)
		global calibrations_cameraScale_µm_norm, calibrations_downwardCameraDatum_norm

		targets_norm::Vector{Float64} = float.([ucm.targetx, ucm.targety])
		deltas_norm::Vector{Float64} = targets_norm .- float.(calibrations_downwardCameraDatum_norm)
		deltas_µm::Vector{Float64} = deltas_norm .* calibrations_cameraScale_µm_norm

		new(deltas_µm[1], deltas_µm[2], ucm.dr)

	end

	function ComponentMotion(am::UncalibratedArbitraryMotion)
		global calibrations_cameraScale_µm_norm, calibrations_downwardCameraDatum_norm
		
		nominalTranslation_norm = float.(am.target) .- float.(calibrations_downwardCameraDatum_norm)
		centreOfRotation_norm = float.(am.centreOfRotation) .- float.(calibrations_downwardCameraDatum_norm)
		rotation_rad = am.rotation

		rotate(p, θ) = [cos(θ) -sin(θ) ; sin(θ) cos(θ)] * p
		centreOfRotationAfterRotationAboutDatum_norm = rotate(centreOfRotation_norm, rotation_rad)
		correctiveTranslation_norm = centreOfRotation_norm .- centreOfRotationAfterRotationAboutDatum_norm

		translation_norm = nominalTranslation_norm .+ correctiveTranslation_norm

		deltas_µm = translation_norm .* calibrations_cameraScale_µm_norm

		new(deltas_µm[1], deltas_µm[2], rotation_rad/2π)

	end

end

struct UncalibratedComponentMotion

	targetx::FI16	# normalised
	targety::FI16	# normalised
	dr::Float64		#! revolutions

	# from normalised types
	UncalibratedComponentMotion(; targetx::FI16=0., targety::FI16=0., dr=0.) = new(targetx, targety, dr)

	# from rescaled types
	UncalibratedComponentMotion(; targetx::Int16=Int16(0), targety::Int16=Int16(0), dr=0.) = new(reinterpret(FI16, targetx), reinterpret(FI16, targety), dr)
	
	# # from all other types
	# UncalibratedComponentMotion(; targetx=0., targety=0., dr=0.) = new(targetx, targety, dr)

end

mutable struct UncalibratedArbitraryMotion
	# stores information about a virtual centre of rotation
	target::Vector{FI16}				# in normalised image units [-0.5, 0.5) 
	rotation::Float64					#! in radians
	centreOfRotation::Vector{FI16}		# in normalised image units
	UncalibratedArbitraryMotion(; target::Vector{FI16}=[0.,0.], rotation=0., centreOfRotation::Vector{FI16}=[0.,0.]) = new(target, rotation, centreOfRotation)
end

Movement = Union{StartupManoeuvres, HeadManoeuvres, UncalibratedComponentMotion, ComponentMotion, Nothing}

@enum VacuumStates suck nosuck

###################
# MOVEMENT COORDINATION
# movement is multithreaded

nextMovement::Union{ComponentMotion, Nothing} = nothing
nextMovementBeginLock = ReentrantLock()

###################
# MOVEMENT CONTROL
# accessed externally

# public method to actually make a movement
# takes affect as soon as any in-progress movement finishes
# silently overwrites any previously-set pending move — you can only have one pending move
function setMovement(m::Movement)
	@lock nextMovementBeginLock nextMovement = m
end

function setHeadHoldingTorque(state::Bool)
	global headIo
	write(headIo, "\$1=$(state ? "255" : "254")\r")
	rawHeadMovement(r=0.01, hduration=0.1)
end

function setVacuum(s::VacuumStates)
	global headIo
	write(headIo, s == suck ? "M8\r" : "M9\r")
end

###################
# MOVEMENT EXECUTION
# managed internally

# state
datumFromHomeX::Float64 = 0.		# gantry, limit switch homing
datumFromHomeY::Float64 = 0.		# gantry, limit switch homing
headFromUprightU::Float64 = 0.		# head, operator homed TODO think this through a bit more
headFromRetractedV::Float64 = 0.	# head, limit switch homed
headTouchoffV::Float64 = 0.			# SOFT LIMIT used to track the last touch-off
headRotation::Float64 = 0.			# no real home; just need the current pos.

const head90degRotationU::Float64 = 5.5	# head, U axis movement corresponding to 90 degrees
const headMaxExtensionV::Float64 = 1.8	# head, hard limit on head extension

function rawGantryMovement(; dx=0, dy=0)
	global datumFromHomeX, datumFromHomeY, gantryIo

	gantryFeedrate = 10		# √(x^2 + y^2) units per second
	
	# TODO measure and set these
	# mostly here to prevent head crashes, but they also prevent a certain spastic bug in the gantry controller from manifesting
	gantryBoundsMinX = 100
	gantryBoundsMaxX = 300
	gantryBoundsMinY = 100
	gantryBoundsMaxY = 300

	isInBounds(x, y) = (gantryBoundsMinX <= x <= gantryBoundsMaxX) &&
	                   (gantryBoundsMinY <= y <= gantryBoundsMaxY)
	isCurrentlyInBounds = isInBounds(datumFromHomeX, datumFromHomeY)

	# next positions
	nextDatumFromHomeX = datumFromHomeX + dx
	nextDatumFromHomeY = datumFromHomeY + dy

	# cannot leave bounds if already in bounds
	if isCurrentlyInBounds
		clamp!(nextDatumFromHomeX, gantryBoundsMinX, gantryBoundsMaxX)
		clamp!(nextDatumFromHomeY, gantryBoundsMinY, gantryBoundsMaxY)
	end

	dxAchieved = nextDatumFromHomeX - datumFromHomeX
	dyAchieved = nextDatumFromHomeY - datumFromHomeY

	datumFromHomeX = nextDatumFromHomeX
	datumFromHomeY = nextDatumFromHomeY

	# dispatch movement
	write(gantryIo, "G1 X$datumFromHomeX Y$datumFromHomeY\n")

	# block for movement duration
	distance = sqrt(sum(abs2, [dxAchieved, dyAchieved]))
	duration = distance / gantryFeedrate
	sleep(duration)

end

function rawHeadMovement(; u=nothing, v=nothing, r=nothing, hduration=1)
	global headIo

	gearRatio = 11 / 69.8 # TODO is this right

	headGcodeString = "G1"
	if !isnothing(u) headGcodeString *= " X$u" end
	if !isnothing(v) headGcodeString *= " Y$(v-gearRatio*u)" end	# TODO is gear ratio adjustment in the right direction?
	if !isnothing(r) headGcodeString *= " Z$r" end
	headGcodeString *= " F$(60/hduration)\r"			# inverse time feed rate is specified in min⁻¹

	write(headIo, headGcodeString)	
	sleep(hduration)

end

# internal routines to do these things (and block execution as the motion completes)
# let Julia's dynamic dispatch paradigm do the hard work for us

# incremental head lowering with polling of nozzle cone
function touchoffHead()
	global headFromRetractedV, headTouchoffV, piGpioInstance

	extensionPerStep = 0.4
	stepTime = 0.1 			# seconds

	for v in range(headFromRetractedV, headMaxExtensionV, step=extensionPerStep)

		rawHeadMovement(v=v, hduration=stepTime)				# make a step
		headTouchoffV = v										# save position as touch-off location in case we break	
		if PiGPIO.read(piGpioInstance, coneLimitPin) break end	# stop if we've arrived

	end

end

function executeHomeHead()
	global headIo, piGpioInstance, headFromUprightU, headFromRetractedV, headRotation, headTouchoffV
	
	# note that the actual machine home will be in some random location — who knows where… TODO is this okay?
	
	write(headIo, "G93\r")	# G93 inverse time mode — homing & touchoff need this
	write(headIo, "G91\r")	# G91 incremental distance mode (relative coords, because we don't necessarily know where we are in absolute coords)
	
	# assume U has been homed optically by the operator

	# bring the head V axis home
	extensionPerStep = -0.1	# TODO must match mechanical homing tolerance range
	stepTime = 0.1
	while PiGPIO.read(piGpioInstance, headHomePin)
		rawHeadMovement(v=extensionPerStep, hduration=stepTime)
	end

	# there is no relevant home for the nozzle rotation R axis, so don't worry about it
	# it'll just be zeroed in whatever position it's already in

	# update current position on the machine
	write(headIo, "G90\r")					# G90 absolute distance mode
	write(headIo, "G10 L20 P1 X0 Y0 Z0\r")	# G10 L20 P1 rewrite G54 work coordinates to be X0 Y0 Z0 in current location
	write(headIo, "G54\r")					# G54 use work coordinate system (the one we just configured)

	# update the current position in our counters
	headFromUprightU = 0.
	headFromRetractedV = 0.
	headRotation = 0.

	# touch off to calculate and store max extension
	touchoffHead()

	# move to upright position
	rawHeadMovement(v=0, hduration=2)
	rawHeadMovement(u=head90degRotationU, hduration=2)
	rawHeadMovement(v=headTouchoffV, hduration=2)

end

# send homing command
function executeHomeGantry()
	global gantryIo
	write(gantryIo, "G28\n")
	sleep(8) 					# TODO review
end

function executeMovement(m::StartupManoeuvres)
	# two quite different options for a StartupManoeuvre — delegate to more specific functions
	if m == homeHead return executeHomeHead()
	elseif m == homeHead return executeHomeGantry()
	else @error "Unimplemented"
	end
end

function executeMovement(m::HeadManoeuvres)
	global headTouchoffV

	if m == lower
		rawHeadMovement(v=0, hduration=1)					# retract
		setCompositingMode(CompositingModes.FROZEN)
		rawHeadMovement(u=0, hduration=1)					# point downwards
		touchoffHead()										# extend until contact with component
	
	elseif m == raise
		rawHeadMovement(v=0, hduration=1)					# retract (lift)
		rawHeadMovement(u=head90degRotationU, hduration=1) 	# lift back up
		setCompositingMode(CompositingModes.NORMAL)
		rawHeadMovement(v=headTouchoffV, hduration=1) 		# re-extend symmetrically to put into plane of focus
	
	elseif m == pick
		# re-use the above
		executeMovement(lower)
		setVacuum(suck)
		executeMovement(raise)
	
	elseif m == place
		# re-use the above
		executeMovement(lower)
		setVacuum(nosuck)
		executeMovement(raise)

	else
		@error "Unimplemented"

	end

end

function executeMovement(m::UncalibratedComponentMotion)
	executeMovement(ComponentMotion(m))
end

function executeMovement(m::ComponentMotion)
	global datumFromHomeX, datumFromHomeY, headRotation

	tasks = [
		@task rawGantryMovement(dx=m.dx, dy=m.dy)
		@task rawHeadMovement(r=(headRotation += m.dr), hduration=(0.5*dr))	# TODO revise duration (feed rate) calculation
		# TODO I probably should prevent wind-up on headRotation…
	]

	schedule.(tasks)
	wait.(tasks)

end

function executeMovement(m::Nothing)
	# nothing to do
	# (sounds too much like the Canvas to-do page…)
end

# main loop for this
function movementsThread() while true
	global nextMovementBeginLock, nextMovement

	executeMovement(@lock nextMovementBeginLock nextMovement)
	sleep(0.1)

end end

# run in background
# @spawn movementsThread()
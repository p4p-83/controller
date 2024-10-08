# motion.jl
# adapts movement descriptions —> movement instructions —> gcodes
# and then dispatches them

# performs bounds checking and manages work coordinates to keep numbers known

# note I was kind of planning to write this in a way that would let in-progress moves
# be cancelled mid-way-through
# but then I didn't, 'cause that's kind of hard and I have little time left with this project

using Base.Threads, LibSerialPort

# set switches up preemptively
include("gpio.jl")
const coneLimitPin::Int = 27
const headHomePin::Int = 17
setGpio(coneLimitPin, dir=INPUT, pull=PULL_DOWN)
setGpio(headHomePin, dir=INPUT, pull=PULL_DOWN)

const CONE_LIMIT_NOT_DEPRESSED = true
const CONE_LIMIT_DEPRESSED = false

const V_HOMING_NOT_DEPRESSED = true
const V_HOMING_DEPRESSED = false

# instances
const gantryIo::LibSerialPort.SerialPort = open("/dev/ttyUSB0", 115200)
const headIo::LibSerialPort.SerialPort = open("/dev/ttyACM0", 115200)
# const gantryIo = open("/dev/null", "w+")	#! so that Sam can test from home without crashing things
# const headIo = open("/dev/null", "w+")

###################
# CALIBRATION FUNCTIONS

function normedPixelsToMicrometres(xy::Vector{FI16})::Vector{Float64}
	global calibrations_cameraScale_µm_norm, calibrations_downwardCameraDatum_norm
	return @. (float(xy) - float(calibrations_downwardCameraDatum_norm)) * calibrations_cameraScale_µm_norm
end

function micrometresToNormedPixels(dxdy::Vector{Float64})::Vector{FI16}
	global calibrations_cameraScale_µm_norm, calibrations_downwardCameraDatum_norm
	return @. FI16(dxdy/calibrations_cameraScale_µm_norm) + calibrations_downwardCameraDatum_norm
end

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

struct UncalibratedComponentMotion

	targetx::FI16	# normalised
	targety::FI16	# normalised
	dr::Float64		#! revolutions

	# from normalised types
	UncalibratedComponentMotion(; targetx::FI16=0., targety::FI16=0., dr=0.) = new(targetx, targety, dr)

	# from rescaled types
	UncalibratedComponentMotion(; targetx::Int16=Int16(0), targety::Int16=Int16(0), dr=0.) = new(reinterpret(FI16, targetx), reinterpret(FI16, targety), dr)

	# from James's janky rescaled types
	# `inexact error` would mean an overflow
	UncalibratedComponentMotion(; targetx::Int32=Int32(0), targety::Int32=Int32(0), dr=0.) = new(reinterpret(FI16, Int16(targetx)), reinterpret(FI16, Int16(targety)), dr)
	
	# # from all other types
	# UncalibratedComponentMotion(; targetx=0., targety=0., dr=0.) = new(targetx, targety, dr)

end

struct ComponentMotion
	dx::Float64		# µm
	dy::Float64		# µm
	dr::Float64		#! in revolutions (i.e. 0.25 would represent 90°)

	ComponentMotion(;dx=0, dy=0, dr=0) = new(dx, dy, dr)

	function ComponentMotion(ucm::UncalibratedComponentMotion)
		deltas_µm = normedPixelsToMicrometres([ucm.targetx, ucm.targety])
		new(deltas_µm[1], deltas_µm[2], ucm.dr)
	end

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
	@info "$(state ? "enabling" : "disabling") head holding torque"
	write(headIo, "\$1=$(state ? "255" : "1")\r")
	rawHeadMovement(r=(state ? 0.1 : 0.2), hduration=0.1)

	if state
		@info "enabling head holding torque"
		write(headIo, "\$1=255\r")
		sleep(0.1)	# sleep is critical
		rawHeadMovement(r=0.2, hduration=0.4)
	else
		@info "disabling head holding torque"
		write(headIo, "\$1=10\r")
		sleep(0.1)
		rawHeadMovement(r=-0.2, hduration=0.4)
	end
end

function setVacuum(s::VacuumStates)
	global headIo
	write(headIo, s == suck ? "M8\r" : "M9\r")
end

###################
# MOVEMENT EXECUTION
# managed internally

# state
datumFromHomeX::Float64 = 0.		# µm; gantry, limit switch homing
datumFromHomeY::Float64 = 0.		# µm; gantry, limit switch homing
headFromUprightU::Float64 = 0.		# head, operator homed TODO think this through a bit more
headFromRetractedV::Float64 = 0.	# head, limit switch homed
headTouchoffV::Float64 = 0.			# SOFT LIMIT used to track the last touch-off
headRotation::Fixed{Int64, 16} = 0.	# revolutions; no real home, just need the current pos.	# BUG (or a chance of one) — I changed this to Fixed without testing :)

const head90degRotationU::Float64 = 5.5	# head, U axis movement corresponding to 90 degrees
const headMaxExtensionV::Float64 = -1.9	# head, hard limit on head extension

function rawGantryMovement(; dx=0, dy=0)
	global datumFromHomeX, datumFromHomeY, gantryIo

	gantryFeedrate = 10000			# √(dx^2 + dy^2) units per second
	
	# TODO measure and set these
	# mostly here to prevent head crashes, but they also prevent a certain spastic bug in the gantry controller from manifesting
	# gantryBoundsMinX = 100
	# gantryBoundsMaxX = 300
	# gantryBoundsMinY = 100
	# gantryBoundsMaxY = 300

	# isInBounds(x, y) = (gantryBoundsMinX <= x <= gantryBoundsMaxX) &&
	                #    (gantryBoundsMinY <= y <= gantryBoundsMaxY)
	# isCurrentlyInBounds = isInBounds(datumFromHomeX, datumFromHomeY)

	# next positions
	nextDatumFromHomeX = datumFromHomeX + float.(dx)
	nextDatumFromHomeY = datumFromHomeY + float.(dy)

	# cannot leave bounds if already in bounds
	# if isCurrentlyInBounds
	# 	clamp!(nextDatumFromHomeX, gantryBoundsMinX, gantryBoundsMaxX)
	# 	clamp!(nextDatumFromHomeY, gantryBoundsMinY, gantryBoundsMaxY)
	# end

	# x bounds check
	if (nextDatumFromHomeX < 0) nextDatumFromHomeX = 0. end
	if (nextDatumFromHomeX > 265e3) nextDatumFromHomeX = 265e3 end

	# y bounds check
	if (nextDatumFromHomeY < 0) nextDatumFromHomeY = 0. end
	if (nextDatumFromHomeY > 180e3) nextDatumFromHomeY = 180e3 end
	if ((datumFromHomeY > 55e3) && (nextDatumFromHomeY < 55e3)) nextDatumFromHomeY = 55e3 end


	dxAchieved = nextDatumFromHomeX - datumFromHomeX
	dyAchieved = nextDatumFromHomeY - datumFromHomeY

	datumFromHomeX = nextDatumFromHomeX
	datumFromHomeY = nextDatumFromHomeY

	@info "moving gantry to ($datumFromHomeX, $datumFromHomeY)"

	# dispatch movement
	write(gantryIo, "G1 X$datumFromHomeX Y$datumFromHomeY\n")

	# block for movement duration
	distance = sqrt(sum(abs2, [dxAchieved, dyAchieved]))
	duration = distance / gantryFeedrate
	sleep(duration)

end

function rawHeadMovement(; u=nothing, v=nothing, r=nothing, hduration=1)
	global headIo, headFromUprightU, headFromRetractedV, headRotation

	@info "rawHeadMovement u=$u v=$v r=$r hduration=$hduration"

	# gearRatio = 11 / 69.8 							# TODO is this right?
	gearRatio = 0.15		 							# TODO is this right?

	headGcodeString =  "G1"

	if !isnothing(u)
		headGcodeString *= " X$u"
		headFromUprightU = u
	end

	if !isnothing(v)
		headFromRetractedV = v
	end

	targetV = headFromRetractedV + gearRatio*headFromUprightU
	headGcodeString *= " Y$targetV"

	if !isnothing(r)
		headGcodeString *= " Z$(float(r))"
		headRotation = r
	end

	headGcodeString *= " F$(60/hduration)\r"		# inverse time feed rate is specified in min⁻¹

	@info "moving head to $headFromUprightU $headFromRetractedV $(float(headRotation))"
	write(headIo, headGcodeString)
	sleep(hduration)

end

# internal routines to do these things (and block execution as the motion completes)
# let Julia's dynamic dispatch paradigm do the hard work for us

# incremental head lowering with polling of nozzle cone
function touchoffHead()
	global headFromRetractedV, headTouchoffV, piGpioInstance

	extensionPerStep = -0.05
	stepTime = 0.1 			# seconds

	for v in range(headFromRetractedV, headMaxExtensionV, step=extensionPerStep)

		rawHeadMovement(v=v, hduration=stepTime)				# make a step
		headTouchoffV = v										# save position as touch-off location in case we break	
		sleep(0.05)
		if readGpio(coneLimitPin) == CONE_LIMIT_DEPRESSED break end						# stop if we've arrived

	end

end

function executeHomeHead()
	global headIo, piGpioInstance, headFromUprightU, headFromRetractedV, headRotation, headTouchoffV
	
	# note that the actual machine home will be in some random location — who knows where… TODO is this okay?
	
	write(headIo, "G93\r")	# G93 inverse time mode — homing & touchoff need this
	write(headIo, "G91\r")	# G91 incremental distance mode (relative coords, because we don't necessarily know where we are in absolute coords)
	
	# assume U has been homed optically by the operator

	# bring the head V axis home
	extensionPerStep = 0.05	# TODO must match mechanical homing tolerance range
	stepTime = 0.1

	for _ in 1:(2÷abs(extensionPerStep))
		# limit the travel
		sleep(0.05)
		if readGpio(headHomePin) == V_HOMING_DEPRESSED break end # TODO assumes NC switch w/ pull up
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
	elseif m == homeGantry return executeHomeGantry()
	else @error "Unimplemented"
	end
end

function executeMovement(m::HeadManoeuvres)
	global headTouchoffV

	if m == lower
		rawHeadMovement(v=0, hduration=1)					# retract
		setCompositingMode(Vision.CompositingModes.FROZEN)
		rawHeadMovement(u=0, hduration=1)					# point downwards
		touchoffHead()										# extend until contact with component
	
	elseif m == raise
		rawHeadMovement(v=0, hduration=1)					# retract (lift)
		rawHeadMovement(u=head90degRotationU, hduration=1) 	# lift back up
		setCompositingMode(Vision.CompositingModes.NORMAL)
		rawHeadMovement(v=headTouchoffV, hduration=1) 		# re-extend symmetrically to put into plane of focus
	
	elseif m == pick
		# re-use the above
		executeMovement(lower)
		setVacuum(suck)
		sleep(0.5)
		executeMovement(raise)
	
	elseif m == place
		# re-use the above
		executeMovement(lower)
		setVacuum(nosuck)
		sleep(0.5)
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
	
	@info "excuting movement"

	tasks = [
		@task rawGantryMovement(dx=m.dx, dy=m.dy)
		@task rawHeadMovement(r=(headRotation += m.dr), hduration=(clamp(0.5*abs(m.dr), 0.1, 1)))	# TODO revise duration (feed rate) calculation
	]

	schedule.(tasks)
	@info "waiting"
	wait.(tasks)
	@info "done waiting"

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
# // @spawn movementsThread()
# gave up on this — easier to just call the movements directly and block whatever thread is running them directly
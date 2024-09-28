using Base.Threads, LibSerialPort
import PiGPIO		# TODO prompt the user to run `sudo pigpiod` before running this  

const coneLimitPin::Int = 0	# TODO

# instances
const piGpioInstance = PiGPIO.Pi()
const gantryIo::LibSerialPort.SerialPort = open("/dev/ttyUSB0", 115200)
const headIo::LibSerialPort.SerialPort = open("/dev/ttyACM0", 115200)

###################
# TYPES TO REPRESENT MOVEMENTS

@enum StartupManoeuvres begin
	homeHead
	homeGantry
end

@enum HeadManoeuvres begin
	pick
	place
end

struct ComponentMotion
	dx::Float64
	dy::Float64
	dr::Float64
end

Movement = Union{StartupManoeuvres, HeadManoeuvres, ComponentMotion, Nothing}

###################
# MOVEMENT COORDINATION
# movement is multithreaded

movementInProgressLock = ReentrantLock()

nextMovement::Union{ComponentMotion, Nothing} = nothing
nextMovementBeginLock = ReentrantLock()

###################
# MOVEMENT CONTROL
# accessed externally

# public method to actually make a movement
# takes affect immediately
function setMovement(m::Movement)
	# TODO
end

function setHeadHoldingTorque()
	global headIo
	write(headIo, "\$1=255\r")
end

function awaitMovement()
	lock(movementInProgressLock)
	unlock(movementInProgressLock)
end

###################
# MOVEMENT EXECUTION
# managed internally

# driver code to send the required gcode
# everything should have been bounds checked and accounted for by this point — all points relative to home coordinates
function sendMovementGcodes(; x=nothing, y=nothing, f1=600, u=nothing, v=nothing, r=nothing, th=1)

	# create strings
	gantryString = "G1"
	if !isnothing(x) gantryString *= " X$x" end
	if !isnothing(y) gantryString *= " Y$y" end
	gantryString *= " F$f1\n"	# TODO no support for feed rates on this controller
	
	headString = "G1"
	if !isnothing(u) headString *= " X$u" end
	if !isnothing(v) headString *= " Y$v" end
	if !isnothing(r) headString *= " Z$r" end
	headString *= " F$th\r"		# TODO need to make sure this is in inverse time mode! (G93)

	# dispatch
	println(gantryString)
	println(headString)

end

# state
datumFromHomeX::Float64 = 0.		# gantry, limit switch homing
datumFromHomeY::Float64 = 0.		# gantry, limit switch homing
headFromUprightU::Float64 = 0.		# head, operator homed TODO think this through a bit more
headFromRetractedV::Float64 = 0.	# head, limit switch homed
headTouchoffV::Float64 = 0.			# SOFT LIMIT used to track the last touch-off
headRotation::Float64 = 0.			# no real home; just need the current pos.

const head90degRotationU::Float64 = 5.5	# head, U axis movement corresponding to 90 degrees
const headMaxExtensionV::Float64 = 1.8	# head, hard limit on head extension

# internal routines to do these things (and block execution as the motion completes)
# let Julia's dynamic dispatch paradigm do the hard work for us

# incremental head lowering with polling of nozzle cone
function touchoffHead()
	global headFromRetractedV, headTouchoffV

	extensionPerStep = 0.4
	stepTime = 0.1 			# seconds

	for v in range(headFromRetractedV, headMaxExtensionV, step=extensionPerStep)

		# make a step
		sendMovementGcodes(v=v, th=(60/stepTime))	# inverse time is in min⁻¹
		sleep(stepTime)
		headTouchoffV = v
		if PiGPIO.read(piGpioInstance, coneLimitPin) break end	# TODO requires PiGPIO.set_mode(p::Pi, pin::Int, mode)

	end

end

function executeHomeHead()
	global headIo
	write(headIo, "G28\r") 	# G28 home	# TODO is this even possible — I don't have limits on the other axes! Do I need to do this from the Pi too?
	write(headIo, "G93\r")	# G93 inverse time mode — touchoff needs this TODO can I find a more appropriate place for this?
	touchoffHead()
	# TODO review necessity of further moves
	# sendMovementGcodes(u=????? no clue) TODO send help
end

# send homing command
function executeHomeGantry()
	global gantryIo
	write(gantryIo, "G28\n")
end

function executeMovement(m::StartupManoeuvres)
	# two quite different options for a StartupManoeuvre — delegate to more specific functions
	if m == homeHead return executeHomeHead()
	elseif m == homeHead return executeHomeGantry()
	else @error "Unimplemented"
	end
end

function executeMovement(m::HeadManoeuvres)
	# TODO
	# pretty much already got the code
	# just switch on m == pick, m == place for vacuum
	# also need to estimate the times
	#? could G93 "Inverse Time" be useful? https://www.cnccookbook.com/feed-rate-mode-g-codes-g93-g94-and-g95/
	#* need to do incremental head lowering with polling of nozzle cone! —> touchoffHead()
end

function executeMovement(m::ComponentMotion)
	# TODO
	# fairly simple, hopefully
	# just make the move and estimate the time
end

function executeMovement(m::Nothing)
	# stop errors
	# sleep(0.1)	# ensure the thread yields to Julia's green threading
end

# main loop for this

function movementsThread() while true

	@lock movementInProgressLock executeMovement(@lock nextMovementBeginLock nextMovement)
	sleep(0.1)

end end

@spawn movementsThread

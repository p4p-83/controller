using Base.Threads

###################
# MOVEMENT TYPES

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

function awaitMovement()
	lock(movementInProgressLock)
	unlock(movementInProgressLock)
end

###################
# MOVEMENT EXECUTION
# managed internally

# driver code to send the required gcode
# everything should have been bounds checked and accounted for by this point — all points relative to home coordinates
function sendMovementGcodes(; x=nothing, y=nothing, f1=600, u=nothing, v=nothing, r=nothing, f2=100)

	# create strings
	gantryString = "G1"
	if !isnothing(x) gantryString *= " X$x" end
	if !isnothing(y) gantryString *= " Y$y" end
	gantryString *= " F$f1\r"
	
	headString = "G1"
	if !isnothing(u) headString *= " X$u" end
	if !isnothing(v) headString *= " Y$v" end
	if !isnothing(r) headString *= " Z$r" end
	headString *= " F$f2\r"

	# dispatch
	println(gantryString)
	println(headString)

end

# internal routines to do these things (and block execution as the motion completes)
# let Julia's dynamic dispatch paradigm do the hard work for us

function executeHomeHead()
	# TODO
	# send homing command
	# touch off nozzle cone for z height (can I make the assumption that the present gantry position is fine?)
end

function executeHomeGantry()
	# TODO
	# send homing command
end

function executeMovement(m::StartupManoeuvres)
	# two quite different options for a StartupManoeuvre — 
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
	#* need to do incremental head lowering with polling of nozzle cone!
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

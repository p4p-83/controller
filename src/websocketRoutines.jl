using HTTP.WebSockets, ProtoBuf

########
# PRIVATE HELPER METHODS

function sendMessageToFrontend(socket::WebSocket, message::pnp.v1.Message)
	encoder = ProtoEncoder(IOBuffer())
	encode(encoder, message)
	if position(encoder.io) != 0
		buffer = take!(data)
		WebSockets.send(socket, buffer)
	end
end

########
# PRIVATE LOGIC
# actions to perform when messages with a specific tag arrive from the front-end

# HEARTBEAT
function handleWsHeartbeat(socket::WebSocket)
	sendMessageToFrontend(socket, pnp.v1.Message( pnp.v1.var"Message.Tags".HEARTBEAT, nothing ) )
end

# CALIBRATE_DELTAS
function handleWsCalibrateDeltas(payload)
	global calibrations_cameraScale_µm_norm

	if payload.name !== :calibration
		# println("Missing calibration!", payload)
		return
	end

	println("Target deltas: ", payload[].target)
	println("Real deltas: ", payload[].real)

	println("Current calibration is $(calibrations_cameraScale_µm_norm)")

	r = [payload[].real.x, payload[].real.y]
	t = [payload[].target.x, payload[].target.y]

	@. calibrations_cameraScale_µm_norm /= 1 - (r / t)

	println("Calibrated to $(calibration)")

end

# TARGET_DELTAS
function handleWsGantryMovementRequest(socket, payload)
	global calibration

	if payload.name !== :deltas
		# guard
		# println("Missing deltas!", payload)
		return
	end
	
	# println("Deltas: ", payload[])

	# println("Gantry currently at $(gantry.position)")
	# println("Calibration is currently $(calibration)")

	executeMovement(UncalibratedComponentMotion(targetx=payload[].x, targety=payload[].y))

	# acknowledge movement
	sendMessageToFrontend(socket, pnp.v1.Message(
		pnp.v1.var"Message.Tags".MOVED_DELTAS,
		OneOf(
			:deltas,
			pnp.v1.var"Message.Deltas"(payload[].x, payload[].y)
		)
	))

end

# OPERATE_HEAD
function handleWsHeadMovementRequest(payload)
	
	if payload.name !== :headOperation
		println("Missing head operation!", payload)
		return
	end

	operation = payload[].operation

	# support for normal operations
	if operation == pnp.v1.var"Message.HeadOperation.Operation".PICK
		executeMovement(pick)
	
	elseif operation == pnp.v1.var"Message.HeadOperation.Operation".PLACE
		executeMovement(place)

	# support for manual overrides
	elseif operation == pnp.v1.var"Message.HeadOperation.Operation".ENGAGE_VACUUM
		setVacuum(suck)
	
	elseif operation == pnp.v1.var"Message.HeadOperation.Operation".DISENGAGE_VACUUM
		setVacuum(nosuck)
	
	elseif operation == pnp.v1.var"Message.HeadOperation.Operation".LOWER_HEAD
		executeMovement(lower)
	
	elseif operation == pnp.v1.var"Message.HeadOperation.Operation".RAISE_HEAD
		executeMovement(raise)

	else
		@error "Unimplemented"
	
	end

end

# ROTATE_NOZZLE
function handleWsNozzleRotationRequest(payload)

	if payload.name !== :nozzleRotation
		println("Missing nozzle rotation!", payload)
		return
	end

	executeMovement(ComponentMotion(
		dr=(-payload[].degrees/360)
	))

end

# STEP_GANTRY
function handleWsHomingRequest(payload)

	if payload.name !== :step
		println("Missing step!", payload)
		return
	end

	if direction == pnp.v1.var"Message.Step.Direction".ZERO
		exectuteMovement(homeGantry)
	end
	
end

########
# PUBLIC-PRIVATE DELEGATION

function handleFrontEndCommand(socket::WebSocket, data::Any)
	println("Non-UInt8[] data received: ", data)
end

function handleFrontEndCommand(socket::WebSocket, data::AbstractArray{UInt8})

	decoder = ProtoDecoder(IOBuffer(data))
	message = decode(decoder, pnp.v1.Message)

	if isnothing(message) return end

	Tags = pnp.v1.var"Message.Tags"
	tag::Tags = message.tag
	payload = message.payload

	if tag == Tags.HEARTBEAT 				handleWsHeartbeat(socket)
	elseif tag == Tags.CALIBRATE_DELTAS		handleWsCalibrateDeltas(payload)
	elseif tag == Tags.TARGET_DELTAS 		handleWsGantryMovementRequest(socket, payload)
	elseif tag == Tags.OPERATE_HEAD			handleWsHeadMovementRequest(payload)
	elseif tag == Tags.ROTATE_NOZZLE		handleWsNozzleRotationRequest(payload)
	elseif tag == Tags.STEP_GANTRY			handleWsHomingRequest(payload)
	else 									@error "Unimplemented"
	end

end

# function handleFrontEndCommandDuringInteractiveStartup(socket::WebSocket, data::AbstractArray{UInt8})

# 	decoder = ProtoDecoder(IOBuffer(data))
# 	message = decode(decoder, pnp.v1.Message)

# 	if isnothing(message) return end

# 	Tags = pnp.v1.var"Message.Tags"
# 	tag::Tags = message.tag
# 	payload = message.payload

# 	if tag == Tags.TARGET_DELTAS

# 		if payload.name !== :deltas
# 			return
# 		end

# 		interactiveStartupNoteLatestClickTarget(reinterpret(FI16, payload[].x), reinterpret(FI16, payload[].y))

# 		# leave on screen?
# 		# sendMessageToFrontend(socket, pnp.v1.Message(
# 		# 	pnp.v1.var"Message.Tags".MOVED_DELTAS,
# 		# 	OneOf(
# 		# 		:deltas,
# 		# 		pnp.v1.var"Message.Deltas"(payload[].x, payload[].y)
# 		# 	)
# 		# ))

# 	end

# end

function sendCentroidsToFrontend(socket)
	
	snapPositions = [pnp.v1.var"Message.Position"(reinterpret.(Int16, r)...) for r in Vision.getCentroids(1)]

	sendMessageToFrontend(socket, pnp.v1.Message(
		pnp.v1.var"Message.Tags".TARGET_POSITIONS,
		OneOf(
			:positions,
			# pnp.v1.var"Message.Positions"(randomPositions)
			pnp.v1.var"Message.Positions"(snapPositions)
		)
	))

end

########
# PUBLIC METHODS

sendCentroidsDownSockets::Bool = false
sendCentroidsDownSocketsLock::ReentrantLock = ReentrantLock()

frontendCommandHandler::Function = handleFrontEndCommand
frontendCommandHandlerLock::ReentrantLock = ReentrantLock() 

# useful for interactive startup
# call with (nothing) to reset / restore default
function overrideFrontendCommandHandler(overrideFn::Union{Function, Nothing})
	lock(frontendCommandHandlerLock)
	
	if isnothing(overrideFn) frontendCommandHandler = handleFrontEndCommand
	else frontendCommandHandler = overrideFn
	end
	
	unlock(frontendCommandHandlerLock)
end

function enableDisableCentroidSending(enable::Bool)
	global sendCentroidsDownSockets, sendCentroidsDownSocketsLock
	@lock sendCentroidsDownSocketsLock sendCentroidsDownSockets = enable
end

function handleWebSocketConnection(socket)
	global sendCentroidsDownSocketsLock, sendCentroidsDownSockets
	global frontendCommandHandlerLock, frontendCommandHandler
	
	isSocketAlive::Bool = true
	isSocketAliveLock::ReentrantLock = ReentrantLock()

	@spawn while @lock isSocketAliveLock isSocketAlive
		# local socket, isSocketAlive, isSocketAliveLock
		scds = @lock sendCentroidsDownSocketsLock sendCentroidsDownSockets
		if scds sendCentroidsToFrontend(socket) end
		sleep(0.5)
	end
	
	# keeps iterating until socket closes
	for data in socket
		fech = @lock frontendCommandHandlerLock frontendCommandHandler
		fech(socket, data)
	end

	# kill the process — socket closed
	@lock isSocketAliveLock isSocketAlive = false

end
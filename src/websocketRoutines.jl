using Base.Threads, HTTP.WebSockets, ProtoBuf

mutable struct Calibration
	x::Float32
	y::Float32
end

# Assume that you can see 8x 10mm squares on the video feed.
# This means that [0, 65536] maps into [0mm, 80mm].
# Therefore, to denormalise into millimetres, we must multiply received deltas by (80 mm / 65536).
# To normalise into micrometres, we multiply this factor by (1000 um / 1 mm).
# Therefore, a reasonable starting calibration is (80000 um / 65536).
# calibration default: uh, they're empirical values
calibration = Calibration(-1.0508553, 1.0789665)

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
function handleWsCalibrateDeltas(message.payload)
	global calibration

	if payload.name !== :calibration
		# println("Missing calibration!", payload)
		return
	end

	println("Target deltas: ", payload[].target)
	println("Real deltas: ", payload[].real)

	println("Current calibration is $(calibration)")

	calibration.x = calibration.x / (1 - (payload[].real.x / payload[].target.x))
	calibration.y = calibration.y / (1 - (payload[].real.y / payload[].target.y))

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

	executeMovement(ComponentMotion(
		dx=(payload[].x * calibration.x),
		dy=(payload[].y * calibration.y)
	))

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
function handleWsHeadMovementRequest(message.payload)
	
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
function handleWsNozzleRotationRequest(message.payload)

	if payload.name !== :nozzleRotation
		println("Missing nozzle rotation!", payload)
		return
	end

	executeMovement(ComponentMotion(
		dr=(-payload[].degrees/360)
	))

end

# STEP_GANTRY
function handleWsHomingRequest(message.payload)

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

	if tag == Tags.HEARTBEAT 				handleWsHeartbeat(socket)
	elseif tag == Tags.CALIBRATE_DELTAS		handleWsCalibrateDeltas(message.payload)
	elseif tag == Tags.TARGET_DELTAS 		handleWsGantryMovementRequest(socket, message.payload)
	elseif tag == Tags.OPERATE_HEAD			handleWsHeadMovementRequest(message.payload)
	elseif tag == Tags.ROTATE_NOZZLE		handleWsNozzleRotationRequest(message.payload)
	elseif tag == Tags.STEP_GANTRY			handleWsHomingRequest(message.payload)
	else 									@error "Unimplemented"
	end

end

function sendCentroidsToFrontend(socket)
	
	snapPositions = [pnp.v1.var"Message.Position"(r[1], r[2]) for r in Vision.getCentroidsNorm(1)]

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

function enableDisableCentroidSending(enable::Bool)
	@lock sendCentroidsDownSocketsLock sendCentroidsDownSockets = enable
end

function handleWebSocketConnection(socket)
	global sendCentroidsDownSockets, sendCentroidsDownSocketsLock
	
	isSocketAlive::Bool = true
	isSocketAliveLock::ReentrantLock = ReentrantLock()

	@spawn while @lock isSocketAliveLock isSocketAlive
		if @lock sendCentroidsDownSocketsLock sendCentroidsDownSockets sendCentroidsToFrontend(socket) end
		sleep(0.5)
	end
	
	# keeps iterating until socket closes
	for data in socket
		handleFrontEndCommand(socket, data)
	end

	# kill the process — socket closed
	@lock isSocketAliveLock isSocketAlive = false

end
using Crayons.Box

downwardCameraDatum::Vector{FI16} = [0., 0.]
downwardCameraDatumLock::ReentrantLock = ReentrantLock()

upwardCameraDatum::Vector{FI16} = [0., 0.]
upwardCameraDatumLock::ReentrantLock = ReentrantLock()

# helper fn
# a bit awkward having it here, but … what do
# run out of refactoring time
function onlyIfTargetDeltas(fn::Function, socket, data)

	@info "onlyIfTargetDeltas"
	
	decoder = ProtoDecoder(IOBuffer(data))
	message = decode(decoder, pnp.v1.Message)

	if isnothing(message) return end

	Tags = pnp.v1.var"Message.Tags"
	tag::Tags.T = message.tag
	payload = message.payload

	if tag == Tags.TARGET_DELTAS

		if payload.name !== :deltas
			return
		end

		x = reinterpret(FI16, Int16(payload[].x))
		y = reinterpret(FI16, Int16(payload[].y))
		@info "got target deltas $x $y"
		fn(x, y)

		# leave on screen?
		# sendMessageToFrontend(socket, pnp.v1.Message(
		# 	pnp.v1.var"Message.Tags".MOVED_DELTAS,
		# 	OneOf(
		# 		:deltas,
		# 		pnp.v1.var"Message.Deltas"(payload[].x, payload[].y)
		# 	)
		# ))

	end

end

function upwardCameraFECHOverrideFn(x::FI16, y::FI16)
	global upwardCameraDatumLock, upwardCameraDatum
	lock(upwardCameraDatumLock)
	upwardCameraDatum .= [x, y]
	unlock(upwardCameraDatumLock)
end

function downwardCameraFECHOverrideFn(x::FI16, y::FI16)
	global downwardCameraDatumLock, downwardCameraDatum
	lock(downwardCameraDatumLock)
	downwardCameraDatum .= [x, y]
	unlock(downwardCameraDatumLock)
end

function interactiveStartup()
	global upwardCameraDatumLock, upwardCameraDatum
	global downwardCameraDatumLock, downwardCameraDatum
	global calibrations_downwardCameraDatum_norm, calibrations_upwardCameraDatumWrtDownwardCameraDatum_norm
	global headTouchoffV # TODO should not be here but is… hacky last-minute things

	#* --> preparation

	println("""
	Welcome to the interactive startup for the controller.
	""")

	@spawn WebSockets.listen(handleWebSocketConnection, "0.0.0.0", 8080)
	beginVision()
	# redirect_stdio(stdout=devnull, stderr=devnull) do; beginVision end

	#* --> all things off

	# digitally disable the head holding torque
	setHeadHoldingTorque(false)

	# have the user manually disable the gantry
	println("""
	Please ensure the gantry is unlocked (using the switch on the gantry driver PCB). You should be able to push the head around by hand with minimal resistance.

	Press enter when you have done this.
	""")

	# await user confirmation
	readline()

	#* --> stand head at 90°

	# TODO make some sort of guide to help with this…
	println("""
	You're now free to move things out of the way as needed to load your PCB.

	After loading, please move the head manually to a comfortable working area above the PCB.

	Press enter when you have done both of these things.
	""")

	readline()

	println("""
	Please stand the nozzle up at exactly 90°, allowing the nozzle to hover slightly over the board.

	Press enter when you have done this. (The holding torque will come on for the head to keep it where you put it.)
	""")

	readline()

	setHeadHoldingTorque(true)
	touchoffHead()
	rawHeadMovement(v=headTouchoffV+0.05)

	#* --> align over reference mark

	println("""
	Holding torque is now enabled, so you no longer need to keep the nozzle at 90° manually.

	Please align the nozzle over a reference mark (of your choosing) on your PCB. We'll use this reference mark to remove camera offsets for an accurate placement preview.

	Let go of the head after doing this. After this alignment step, you will have done all of the manual head alignment necessary: be careful to avoid moving or disturbing the head from this point onwards.
		
	Press enter when you have done this. (The nozzle will then lift into its upright position, so make sure you remember what your reference mark is!)
	""")

	readline()

	#* ---> bring to camera

	executeMovement(homeHead)

	#* ---> have user click upwards feed

	println("""
	The nozzle has been lifted to the head.

	Please load up the /place page on the web interface (as opened earlier).

	You should see an image of the nozzle. Please click the centre of the nozzle as accurately as possible.

	You get multiple attempts (so you can use the circle to visualise the accuracy). Press enter when you're happy to lock it in.
	""")

	Vision.setCompositingMode(Vision.CompositingModes.ONLYUP)

	overrideFrontendCommandHandler() do socket, data
		@info "overriden upward FECH"
		onlyIfTargetDeltas(upwardCameraFECHOverrideFn, socket, data)
	end

	readline()

	overrideFrontendCommandHandler(nothing)

	#* ---> have user click downwards feed

	println("""
	You've now confirmed the nozzle location on one camera feed.

	In a second, the downwards camera feed will be shown on the screen. We'll now align this camera feed.

	Please identify the reference mark that you selected before (the point over which the nozzle was aligned).

	Same as before, you can click as many times as you need. Press enter when you're satisfied.
	""")

	Vision.setCompositingMode(Vision.CompositingModes.ONLYDOWN)

	overrideFrontendCommandHandler() do socket, data
		@info "overriden downward FECH"
		onlyIfTargetDeltas(downwardCameraFECHOverrideFn, socket, data)
	end

	readline()

	overrideFrontendCommandHandler(nothing)
	Vision.setCompositingMode(Vision.CompositingModes.NORMAL)

	#* ---> power on & home the gantry

	println("""
	You've now finished aligning the head. The next step is to home the gantry.

	Before homing the gantry, make sure there is adequate clearance for the second camera behind the machine!

	Also note that sometimes the gantry will home itself after you flick the switch — don't panic if it moves on its own accord here; that's fine.

	Please flick the switch on the gantry controller to re-enable holding torque (and motion). Press enter when you've done this.
	""")


	readline()

	println("""
	Homing the gantry…
	""")

	executeMovement(homeGantry)

	#* ---> calibrations prompt (but otherwise done)

	println("""
	The gantry is now homed in. That's all the setup needed for the mechanical and optical parts.

	Note that if you experience issues while placing parts with the gantry moving too far, not far enough, or even in the wrong direction, you can (re)calibrate the movements using the /calibrate page. (But you shouldn't have to worry about this if your're using a standard-height PCB with the normal clips.)
	""")

	#* ---> deal with new calibration data
	calibrations_downwardCameraDatum_norm .= downwardCameraDatum
	calibrations_upwardCameraDatumWrtDownwardCameraDatum_norm .= upwardCameraDatum .- downwardCameraDatum
	Vision.setCompositingOffsets(calibrations_upwardCameraDatumWrtDownwardCameraDatum_norm)
	Vision.setNozzleOffsets(calibrations_downwardCameraDatum_norm)

	println("""
	Ready to go.
	Please use /place in the web browser to populate your PCB!
	""")

end
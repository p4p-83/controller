function interactiveStartup()

#* --> preparation

WebSockets.listen(handleWebSocketConnection, "0.0.0.0", "8080")

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

# TODO cache clicks

readline()

#* ---> have user click downwards feed

println("""
You've now confirmed the nozzle location on one camera feed.

In a second, the downwards camera feed will be shown on the screen. We'll now align this camera feed.

Please identify the reference mark that you selected before (the point over which the nozzle was aligned).

Same as before, you can click as many times as you need. Press enter when you're satisfied.
""")

# TODO cache clicks

readline()

#* ---> power on & home the gantry

println("""
You've now finished aligning the head. The next step is to home the gantry.

Before homing the gantry, make sure there is adequate clearance for the second camera to protrude behind the machine!

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

end
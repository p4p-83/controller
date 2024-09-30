# really crude wrapper around the Raspberry Pi `pinctrl` CLI
# I can't find a proper GPIO library that works on the Pi 5
# most of the common ones only seem to have support up to the Pi 4
# (Have tried PiGPIO.jl, BaremetalPi.jl, WiringPi)

function readGpio(pin::Int)::Bool
	
	# pinNum::Vector{Cint} = [0]
	# formatTemplate = "%d: %"
	# @ccall sscanf(read(`pinctrl get $pin`)::Ptr{Cchar}, "%d: "::Ptr{Cchar}, number::Ptr{Cint})::Cint

	info = read(`pinctrl get $pin`, String)

	# sample output:
	# shell> pinctrl
	#  0: ip    pu | hi // ID_SDA/GPIO0 = input
	#  1: ip    pu | hi // ID_SCL/GPIO1 = input
	#  2: no    pu | -- // GPIO2 = none
	#  3: no    pu | -- // GPIO3 = none

	pinConfirmation, temp = split(info, ": ")
	keys, _ = split(temp, " //")

	# keys takes format e.g. "op dh pd | hi"
	#                         1234567890123

	outputInputKey = keys[1:2]
	driveHighLow = keys[4:5]
	pullUpDown = keys[7:8]
	stateHighLow = keys[12:13]

	if stateHighLow == "hi"
		return true
	elseif stateHighLow == "lo"
		return false
	else
		@error "Failed to read pin (got '$(strip(info))')"
		# maybe you specified an invalid pin
		# maybe the pin is configured to have mode NONE — look for a "no" in the info string
		# maybe you lack permissions to read GPIO (must be a member of gpio user group)
		# also possible that pinctrl was updated and its format was changed
	end

end

@enum GpioDirModes INPUT OUTPUT
@enum GpioPullModes PULL_UP PULL_DOWN PULL_NONE
@enum GpioDriveModes DRIVE_HIGH DRIVE_LOW

function setGpio(pin::Int; dir::Union{GpioDirModes, Nothing}=nothing, pull::Union{GpioPullModes, Nothing}=nothing, drive::Union{GpioDriveModes, Nothing}=nothing)

	command = Cmd([
		"pinctrl"
		"set"
		"$pin"

	])

	commandTokens = ["pinctrl", "set", "$pin"]
	
	# use pinctrl tokens
	# run shell> `pinctrl help` to see list of these
	if dir == INPUT push!(commandTokens, "ip") end
	if dir == OUTPUT push!(commandTokens, "op") end
	if pull == PULL_UP push!(commandTokens, "pu") end
	if pull == PULL_DOWN push!(commandTokens, "pd") end
	if pull == PULL_NONE push!(commandTokens, "pn") end
	if drive == DRIVE_HIGH push!(commandTokens, "dh") end
	if drive == DRIVE_LOW push!(commandTokens, "dl") end

	# invoke pinctrl and throw error if one is suspected
	response = read(Cmd(commandTokens), String)
	if response != "" @error response end

end

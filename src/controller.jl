module Controller

using FixedPointNumbers, Base.Threads
FI16 = Fixed{Int16, 16}

# header code
include("proto/pnp/v1/pnp.jl")

# import submodules
include("vision/vision.jl")
using .Vision

# calibrations at top level
calibrations_defaultScale_µm_remappedpx::Vector{Float64} = [-1.0508553, 1.0789665]
	# µm per remappedpx, where a remapped px assumes that the image is 2^16 pixels wide…

calibrations_cameraScale_µm_norm = calibrations_defaultScale_µm_remappedpx .* 2^16
	# µm per n, where the normalised dimension assumes the image extends from -0.5 to 0.499...

calibrations_downwardCameraDatum_norm::Vector{FI16} = [0., 0.]
	# normalised location of the downward camera datum

calibrations_upwardCameraDatumWrtDownwardCameraDatum_norm::Vector{FI16} = [0., 0.]
	# normalised displacment (upward camera datum) - (downward camera datum) to correct for misalignment

# body code
include("motion.jl")
include("algorithms.jl")
include("websocketRoutines.jl")
include("interactiveStartup.jl")

# intended use of Controller: call Controller.interactiveStartup() as part of the wider interactive startup process
beginController() = interactiveStartup()

end # module Controller
module Controller

using HTTP.WebSockets, ProtoBuf, Crayons.Box

# header code
include("proto/pnp/v1/pnp.jl")

# import submodules
include("vision/vision.jl")
using .Vision

# body code
include("motion.jl")
include("websocketRoutines.jl")
include("interactiveStartup.jl")

# intended use of Controller: call Controller.interactiveStartup() as part of the wider interactive startup process
beginController() = interactiveStartup()

end # module Controller
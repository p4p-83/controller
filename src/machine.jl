include("structs.jl")
include("algorithms.jl")

#! too many data structures too early
#! TODO just figure out the logic first

struct PastPresentFuture
	movementStart::MachineState
	movementSimulated::MachineState
	movementEnd::MachineState
end

function simulationTimestep(ppf)



end
include("controller.jl")
import .Controller

using Crayons.Box, DataFrames
function printCentroidsToStdOut()

	leads, pads = Controller.Vision.getCentroids()

	println("\n\n\nLeads" |> BOLD |> GREEN_FG)
	display(DataFrame(leads))
	println("\nPads" |> BOLD |> GREEN_FG)
	display(DataFrame(pads))
	println()

end

#* start
Controller.beginController()

#* keep alive
while true 
	sleep(2)
	# printCentroidsToStdOut()
end

#* stop
Controller.endController()

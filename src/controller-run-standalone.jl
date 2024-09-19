include("controller.jl")
import .Controller

#* start
Controller.beginController()

#* keep alive
while true 
	sleep(10)
end

#* stop
Controller.endController()

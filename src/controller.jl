module Controller

using HTTP.WebSockets, ProtoBuf, LibSerialPort
using Crayons.Box

include("proto/pnp/v1/pnp.jl")

include("vision/vision.jl")
using .Vision

const gearRatio::Float64 = 11 / 69.8

mutable struct Position
    x::Int32
    y::Int32
end

mutable struct Gantry
    port::SerialPort
    position::Position
end

mutable struct Calibration
    x::Float32
    y::Float32
    z::Float32
end

function usageNotes()
    println("""

    ╒═══════════════════════════════════════════════════════════════════════════╕
    │ starting $(" controller.jl " |> YELLOW_BG |> WHITE_FG)                                                  │
    │                                                                           │
    │ This is the master file for the physical pick and place machine.          │
    │                                                                           │
    │ Note that this application is multithreaded, and you currently have       │
    │ $("$(n=Threads.nthreads()) thread$(n==1 ? "" : "s")"|>BOLD|>YELLOW_FG) allocated to Julia. Julia can handle the task switching within   │
    │ the threads allocated to it and thus function with virtually any number   │
    │ of OS threads (as I understand it), but for the best possible performance │
    │ you should probably ensure that this number of OS-allocated threads is    │
    │ sensible. You can change this with $("export JULIA_NUM_THREADS=2" |> ITALICS) from        │
    │ the shell.                                                                │
    │                                                                           │
    │ You can also run this code from the REPL, but there are unlikely to be    │
    │ any net benefits to gain from doing this (you'll have to pay particular   │
    │ attention to closing all opened resources. However, if you do choose to   │
    │ use the REPL, it will adopt the number of threads $("export"|>ITALICS)ed, or if         │
    │ connected to VS Code will follow the $("\"julia.NumThreads\": 2" |> ITALICS) setting        │
    │ in the host machine's VS Code settings.json.                              │
    │                                                                           │
    └───────────────────────────────────────────────────────────────────────────┘
    """)
end

# function generate_random_positions(max_length::Int=35)
#     length = rand(1:max_length)
#     positions = Vector{pnp.v1.var"Message.Position"}(undef, length)
#     for i in 1:length
#         positions[i] = pnp.v1.var"Message.Position"(rand(UInt16), rand(UInt16))
#     end
#     return positions
# end

function getSnapMarkerPositions(maxLength::Int=250)
    padCoordsList = Vision.getCentroidsNorm(1)[1:min(end, maxLength)]
    positions = [pnp.v1.var"Message.Position"(r[1], r[2]) for r in padCoordsList]
    return positions
end

function step_to_centre(socket::WebSocket, encoder::ProtoEncoder, deltas)
    while deltas[1] != 0 || deltas[2] != 0
        step = Int16[0, 0]

        for i in 1:2
            if deltas[i] > 0
                actual_step = min(1000, deltas[i])
                deltas[i] -= actual_step
                step[i] = actual_step
            elseif deltas[i] < 0
                actual_step = min(1000, -deltas[i])
                deltas[i] += actual_step
                step[i] = -actual_step
            end
        end

        println("Stepped: ", step)
        encode(encoder, pnp.v1.Message(
            pnp.v1.var"Message.Tags".MOVED_DELTAS,
            OneOf(
                :deltas,
                pnp.v1.var"Message.Deltas"(step[1], step[2])
            )
        ))
        send_message(socket, encoder.io)
    end
end

function send_message(socket::WebSocket, data::IOBuffer)
    buffer = take!(data)
    println("Generated message: ", buffer)
    WebSockets.send(socket, buffer)
end

function process_message(socket::WebSocket, data::Any, gantry::Gantry)
    println("Non-UInt8[] data received: ", data)
    return nothing
end

# Assume that you can see 8x 10mm squares on the video feed.
# This means that [0, 65536] maps into [0mm, 80mm].
# Therefore, to denormalise into millimetres, we must multiply received deltas by (80 mm / 65536).
# To normalise into micrometres, we multiply this factor by (1000 um / 1 mm).
# Therefore, a reasonable starting calibration is (80000 um / 65536).
calibration = Calibration((80000 / 65536), (80000 / 65536), 0)

function process_message(socket::WebSocket, data::AbstractArray{UInt8}, gantry::Gantry)
    decoder = ProtoDecoder(IOBuffer(data))
    message = decode(decoder, pnp.v1.Message)

    if isnothing(message)
        println("Received message")
        return nothing
    else
        println("Received message: ", message)
    end

    encoder = ProtoEncoder(IOBuffer())

    if message.tag == pnp.v1.var"Message.Tags".HEARTBEAT
        encode(encoder, pnp.v1.Message(
            pnp.v1.var"Message.Tags".HEARTBEAT,
            nothing
        ))
        send_message(socket, encoder.io)

        # randomPositions = generate_random_positions()
        snapPositions = getSnapMarkerPositions()
        encode(encoder, pnp.v1.Message(
            pnp.v1.var"Message.Tags".TARGET_POSITIONS,
            OneOf(
                :positions,
                # pnp.v1.var"Message.Positions"(randomPositions)
                pnp.v1.var"Message.Positions"(snapPositions)
            )
        ))

    elseif message.tag == pnp.v1.var"Message.Tags".TARGET_DELTAS
        payload = message.payload

        if payload.name !== :deltas
            println("Missing deltas!", payload)
        else
            println("Deltas: ", payload[])

            println("Gantry currently at $(gantry.position)")
            println("Calibration is currently $(calibration)")

            gantry.position = Position(trunc(Int, payload[].x * calibration.x), trunc(Int, payload[].y * calibration.y))

            write(gantry.port, "G0 X$(gantry.position.x) Y$(gantry.position.y)\n")
            println("Moved gantry by $(gantry.position)")

            step_to_centre(socket, encoder, [payload[].x, payload[].y])
        end

    elseif message.tag == pnp.v1.var"Message.Tags".CALIBRATE_DELTAS
        payload = message.payload

        if payload.name !== :calibration
            println("Missing calibration!", payload)
        else
            println("Target deltas: ", payload[].target)
            println("Real deltas: ", payload[].real)

            println("Current calibration is $(calibration)")

            calibration.x = calibration.x / (1 - (payload[].real.x / payload[].target.x))
            calibration.y = calibration.y / (1 - (payload[].real.y / payload[].target.y))

            println("Calibrated to $(calibration)")
        end

    elseif message.tag == pnp.v1.var"Message.Tags".STEP_GANTRY
        payload = message.payload

        if payload.name !== :step
            println("Missing step!", payload)
        else
            direction = payload[].direction

            println("Gantry currently at $(gantry.position)")

            if direction == pnp.v1.var"Message.Step.Direction".ZERO
                write(gantry.port, "G28\n")
                gantry.position = Position(0, 0)
            end

            println("Moved gantry to $(gantry.position)")

        end

    end

    if position(encoder.io) != 0
        send_message(socket, encoder.io)
    end

end

gantry::Union{Nothing,Gantry} = nothing
headIo::Union{Nothing,LibSerialPort.SerialPort} = nothing

function headSequence()
    global headIo

    pushNozzleOut() = write(headIo, "G1 Y-1.85 F600\r")
    pullNozzleIn() = write(headIo, "G1 Y1.85 F600\r")
    # must move nozzle axis in tandem as it is coupled to the head axis
    rotateHeadDown(distance) = write(headIo, "G1 Y-$(distance*gearRatio) X-$distance F2000\r")
    rotateHeadUp(distance) = write(headIo, "G1 Y$(distance*gearRatio) X$distance F2000\r")

    function dispatchSequence()
        # all gets sent at once and queued by the head

        rotateHeadDown(5.5)
        pushNozzleOut()
        pullNozzleIn()

        rotateHeadUp(5.5)
        pushNozzleOut()
        pullNozzleIn()

    end

    setFreezeFramed(true)

    # send all of the commands in advance
    dispatchSequence()

    sleep(5)

    setFreezeFramed(false)

    sleep(2)

end

function headSequenceOnRepeat()
    while true
        headSequence()
    end
end

function openAndHandleWebsocket()
    WebSockets.listen("0.0.0.0", 8080) do socket
        println("Client connected")

        for data in socket
            println()
            println("Received data: ", data)

            process_message(socket, data, gantry)
        end

    end
end

function beginGantry()
    global gantry
    gantry = Gantry(open("/dev/ttyUSB0", 115200), Position(0, 0))
    write(gantry.port, "G28\n") # home
    write(gantry.port, "G91\n") # put into relative coordinates
end

function beginHead()
    global headIo
    headIo = open("/dev/ttyACM0", 115200)
    write(headIo, "G91\r") # put into relative coordinates
end

function beginController()
    beginHead()
    usageNotes()
    beginVision()
    beginGantry()
    # Threads.@spawn headSequenceOnRepeat()
    Threads.@spawn openAndHandleWebsocket()
end

function endController()
    global gantry, headIo
    close(gantry.port)
    close(headIo)
end

end # module Controller
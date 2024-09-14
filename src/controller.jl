using HTTP.WebSockets
using ProtoBuf
using LibSerialPort

include("proto/pnp/v1/pnp.jl")

##

mutable struct Position
    x::Int32
    y::Int32
    z::Int32
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

function Base.:+(a::Position, b::Position)
    return Position(a.x + b.x, a.y + b.y, a.z + b.z)
end

##

function generate_random_positions(max_length::Int=35)
    length = rand(1:max_length)
    positions = Vector{pnp.v1.var"Message.Position"}(undef, length)
    for i in 1:length
        positions[i] = pnp.v1.var"Message.Position"(rand(UInt16), rand(UInt16))
    end
    return positions
end

##

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

##

function send_message(socket::WebSocket, data::IOBuffer)
    buffer = take!(data)
    println("Generated message: ", buffer)
    WebSockets.send(socket, buffer)
end

##

function process_message(socket::WebSocket, data::Any, gantry::Gantry)
    println("Non-UInt8[] data received: ", data)
    return nothing
end

function process_message(socket::WebSocket, data::AbstractArray{UInt8}, gantry::Gantry)
    decoder = ProtoDecoder(IOBuffer(data))
    message = decode(decoder, pnp.v1.Message)

    # Assume that you can see 8x 10mm squares on the video feed.
    # This means that [0, 65536] maps into [0mm, 80mm].
    # Therefore, to denormalise into millimetres, we must multiply received deltas by (80 mm / 65536).
    # To normalise into micrometres, we multiply this factor by (1000 um / 1 mm).
    # Therefore, a reasonable starting calibration is (80000 um / 65536).
    let calibration = Calibration((80000 / 65536), (80000 / 65536), 0)

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

            randomPositions = generate_random_positions()
            encode(encoder, pnp.v1.Message(
                pnp.v1.var"Message.Tags".TARGET_POSITIONS,
                OneOf(
                    :positions,
                    pnp.v1.var"Message.Positions"(randomPositions)
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

                gantry.position += Position(trunc(Int, payload[].x * calibration.x), trunc(Int, payload[].y * calibration.y), 0)
                if gantry.position.x < 0
                    gantry.position.x = 0
                end
                if gantry.position.y < 0
                    gantry.position.y = 0
                end

                write(gantry.port, "G0 X$(gantry.position.x) Y$(gantry.position.y) Z$(gantry.position.z)\n")
                println("Moved gantry to $(gantry.position)")

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
                    gantry.position = Position(0, 0, 0)
                end

                println("Moved gantry to $(gantry.position)")

            end

        end

        if position(encoder.io) != 0
            send_message(socket, encoder.io)
        end

    end

end

##

gantry = Gantry(
    open("/dev/ttyUSB0", 115200),
    Position(0, 0, 0)
)

write(gantry.port, "G28\n")

##

WebSockets.listen("0.0.0.0", 8080) do socket
    println("Client connected")

    for data in socket
        println()
        println("Received data: ", data)

        process_message(socket, data, gantry)
    end

end

##

close(gantry.port)

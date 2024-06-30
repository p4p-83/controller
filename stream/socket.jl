using HTTP.WebSockets
using ProtoBuf

include("../client/src/proto/pnp/v1/pnp_pb.jl")

function send_message(socket::WebSocket, data::IOBuffer)
    buffer = take!(data)
    println("Generated message: ", buffer)
    WebSockets.send(socket, buffer)
end

function process_message(socket::WebSocket, data::Any)
    println("Non-UInt8[] data received: ", data)
    return nothing
end

function process_message(socket::WebSocket, data::AbstractArray{UInt8})
    decoder = ProtoDecoder(IOBuffer(data))

    message = decode(decoder, Message)

    if isnothing(message)
        println("Received message")
        return nothing
    else
        println("Received message: ", message)
    end

    encoder = ProtoEncoder(IOBuffer())

    if message.tag == var"Message.MessageTags".HEARTBEAT
        encode(encoder, Message(var"Message.MessageTags".HEARTBEAT, nothing))

    elseif message.tag == var"Message.MessageTags".TARGET_DELTAS
        println("Deltas: ", message.deltas)

        deltas = [message.deltas.x, message.deltas.y]

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
            encode(encoder, Message(var"Message.MessageTags".MOVED_DELTAS, var"Message.Deltas"(step[1], step[2])))
            send_message(socket, encoder.io)
        end

    end

    if position(encoder.io) != 0
        send_message(socket, encoder.io)
    end

end

WebSockets.listen("0.0.0.0", 8080) do socket
    println("Client connected")

    for data in socket
        println()
        println("Received data: ", data)

        process_message(socket, data)
    end

end
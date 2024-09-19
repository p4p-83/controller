# `controller`

> [!NOTE]
> Refer to [`p4p.jamesnzl.xyz/learn`](https://p4p.jamesnzl.xyz/learn) for full details.

This repository contains the command and control for our pick-and-place machine, and acts as the conduit between the [`p4p-83/gantry`](https://github.com/p4p-83/gantry), [`p4p-83/vision`](https://github.com/p4p-83/vision), and the [`p4p-83/interface`](https://github.com/p4p-83/interface).

## Usage

Firstly, clone this repository. Set up [SSH Agent Forwarding](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/using-ssh-agent-forwarding) on the Raspberry Pi if needed.

```sh
git submodule update --init
julia src/controller.jl
```

## Interfaces

### WebRTC

- WebRTC is used for the real-time low-latency video streaming from MediaMTX on the Raspberry Pi to the web interface.

### WebSocket

- A WebSocket is used for the real-time low-latency full-duplex data channel between the Raspberry Pi and the web interface.

#### Protocol Buffers

- [Protocol buffers](https://protobuf.dev/overview/) are used for data exchange.
- See [`p4p-83/protobufs`](https://github.com/p4p-83/protobufs) for the `.proto` definition(s).

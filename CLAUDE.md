# CLAUDE.md

## Project Overview

This repository contains Odin language ports of JACK example clients,
demonstrating audio programming with the JACK Audio Connection Kit. The
codebase includes example audio clients that generate, process, and capture
audio using JACK's real-time audio API.

## Build System

The project uses a simple Makefile-based build system:

- **Build a program**: `make <program_name>` (e.g., `make simple_client`)
- **Clean builds**: `make clean`
- **Help**: `make help` (shows available programs)
- **Available programs**: `simple_client`, `midisine`, `capture_client`, `sndfile_example`

Individual programs can also be built directly with:

```
odin build <program_name>.odin -file
```

## Architecture

### Core Components

1. **JACK Bindings** (`jack/jack.odin`):
   - Foreign function interface to JACK audio API
   - Provides Odin-idiomatic wrappers around C JACK functions
   - Key functions: `client_open`, `get_ports`, `port_register`, `connect`,
     `activate`
   - Port discovery with flags: `{.IsInput, .IsPhysical}` for ports to write
     to, and `{.IsOutput, .IsPhysical}` for ports to read from.

2. **libsndfile Bindings** (`sndfile/sndfile.odin`):
   - Audio file I/O operations
   - Supports WAV, AIFF, and other audio formats
   - Used by `capture_client` for recording audio to disk

3. **Example Clients**:
   - **simple_client**: Generates stereo sine wave output
   - **midisine**: MIDI-triggered sine wave generator
   - **capture_client**: Records from physical audio inputs to WAV file
   - **sndfile_example**: Demonstrates audio file operations

### Common Patterns

- **Process Callback**: Real-time audio processing using `proc "c"` calling convention
- **Port Management**: Register ports, connect to physical I/O, handle buffer data
- **Thread Safety**: Use atomic operations and synchronization primitives for
  shared data
- **Memory Management**: Manual memory management with `make()`, `delete()`,
  and `defer` cleanup

### Key Data Structures

- `JackClient`: Main JACK client handle
- `JackPort`: Audio/MIDI port representation
- `NFrames`: Audio buffer size type
- `ThreadInfo`: Shared state between real-time and disk threads (in capture_client)
- `RingBuffer`: Thread-safe circular buffer for audio data

## Prerequisites

- JACK development libraries: `sudo apt install libjack-jackd2-dev` (Ubuntu)
- Running JACK server or PipeWire (common on modern Linux distributions)
- Odin compiler

## Common Development Tasks

When working with audio clients:

1. **Finding Physical Ports**: Use `jack.get_ports(client, nil, nil,
   {.IsOutput, .IsPhysical})` for devices to read from (input devices),
   `{.IsOutput, .IsPhysical}` for devices to write to (input devices). The
   naming can be a bit counter-intuitive, but the tags .IsInput/.IsOutput are
   from the point of view of the port itself: if it's output, it means the port
   is outputting audio data, if it's input, the port can receive audio data.
2. **Port Connection**: Connect client ports to physical ports using
   `jack.connect(client, source_port, destination_port)`
3. **Real-time Processing**: Implement `process` callback with `"c"` calling
   convention for real-time audio processing
4. **Error Handling**: Check return values from JACK functions and handle
   client shutdown gracefully

## Testing

Run built programs directly (e.g., `./simple_client`).
Assume JACK server is always running.

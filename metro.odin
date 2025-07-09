package main

import "base:runtime"
import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
import jack "jack"

SIGINT :: 2

MetroData :: struct {
    output_port:     ^jack.JackPort,
    sample_rate:     jack.NFrames,

    // Metronome settings
    frequency:       f64,
    amplitude:       f32,
    duration:        f64, // in seconds
    attack:          f64, // attack time as percentage
    decay:           f64, // decay time as percentage
    bpm:             f64,
    transport_aware: bool,

    // State
    beat_counter:    u64,
    frames_per_beat: jack.NFrames,
    frames_to_beat:  jack.NFrames,
    tone_length:     jack.NFrames,

    // Tone generation
    wave_offset:     f64,
    should_exit:     bool,
}

global_data: ^MetroData

signal_handler :: proc "c" (sig: i32) {
    context = runtime.default_context()
    fmt.println("\nMetronome stopped")
    if global_data != nil {
        global_data.should_exit = true
    }
    os.exit(0)
}

/*
 * Metronome Process Callback
 *
 * This callback is called by JACK in real-time to generate audio samples for each beat.
 * The metronome operates in cycles, where each cycle consists of:
 * 1. A tone period (attack + sustain + decay)
 * 2. A silence period until the next beat
 *
 * ENVELOPE STRUCTURE:
 *
 * The tone envelope follows this pattern over the tone duration:
 *
 *     Amplitude
 *         ^
 *         |    _______
 *         |   /       \
 *         |  /         \
 *         | /           \
 *         |/             \___
 *         +--+-----+-----+---+---> Time
 *         0  |     |     |   |
 *            |     |     |   tone_length
 *            |     |     |
 *            |     |     +-- Decay phase starts (1.0 - decay)
 *            |     +-------- Sustain phase
 *            +-------------- Attack phase ends (attack)
 *
 * TIMING BREAKDOWN:
 *
 * Beat Period:  |<-------- frames_per_beat -------->|
 * Tone:         |<-- tone_length -->|
 * Silence:                          |<-- silence -->|
 *
 * Attack:       |<-attack->|
 * Sustain:                 |<-sustain->|
 * Decay:                             |<-decay->|
 *
 * Where:
 * - attack = tone_length * data.attack
 * - decay = tone_length * data.decay
 * - sustain = tone_length - attack - decay
 *
 * The envelope multiplier is calculated as:
 * - Attack phase: linear ramp from 0 to 1
 * - Sustain phase: constant at 1.0
 * - Decay phase: linear ramp from 1 to 0
 * - Silence phase: 0 (no tone generated)
 */
process :: proc "c" (nframes: jack.NFrames, arg: rawptr) -> i32 {
    data := cast(^MetroData)arg

    if data.should_exit {
        return 0
    }

    out := cast([^]f32)jack.port_get_buffer(data.output_port, nframes)

    for i in 0 ..< nframes {
        if data.frames_to_beat == 0 {
            // Start of a new beat
            data.beat_counter += 1
            data.frames_to_beat = data.frames_per_beat
            data.wave_offset = 0.0
        }

        // Generate tone sample
        sample: f32 = 0.0

        if data.frames_to_beat > (data.frames_per_beat - data.tone_length) {
            // We're in the tone period
            tone_frame :=
                data.tone_length -
                (data.frames_to_beat - (data.frames_per_beat - data.tone_length))
            tone_progress := f64(tone_frame) / f64(data.tone_length)

            // Calculate envelope
            envelope: f32 = 1.0
            if tone_progress < data.attack {
                // Attack phase
                envelope = f32(tone_progress / data.attack)
            } else if tone_progress > (1.0 - data.decay) {
                // Decay phase
                decay_progress := (tone_progress - (1.0 - data.decay)) / data.decay
                envelope = f32(1.0 - decay_progress)
            }

            // Generate sine wave
            sine_value := math.sin(
                2.0 *
                math.PI *
                data.frequency *
                data.wave_offset /
                f64(data.sample_rate),
            )
            sample = f32(sine_value) * data.amplitude * envelope

            data.wave_offset += 1.0
        }

        out[i] = sample
        data.frames_to_beat -= 1
    }

    return 0
}

sample_rate_callback :: proc "c" (nframes: jack.NFrames, arg: rawptr) -> i32 {
    context = runtime.default_context()
    data := cast(^MetroData)arg

    data.sample_rate = nframes
    data.frames_per_beat = jack.NFrames(f64(data.sample_rate) * 60.0 / data.bpm)
    data.tone_length = jack.NFrames(f64(data.sample_rate) * data.duration)

    fmt.printf("Sample rate: %d Hz\n", data.sample_rate)
    fmt.printf("Frames per beat: %d\n", data.frames_per_beat)
    fmt.printf("Tone length: %d frames\n", data.tone_length)

    return 0
}

shutdown :: proc "c" (arg: rawptr) {
    context = runtime.default_context()
    fmt.println("JACK server shutdown")
    os.exit(1)
}

print_usage :: proc() {
    fmt.println("Usage: metro [options] -b BPM")
    fmt.println("Options:")
    fmt.println("  -f, --frequency FREQ   Set tone frequency in Hz (default: 880)")
    fmt.println("  -A, --amplitude AMP    Set amplitude 0-1 (default: 0.5)")
    fmt.println(
        "  -D, --duration MS      Set tone duration in milliseconds (default: 100)",
    )
    fmt.println("  -a, --attack PERCENT   Set attack time as percentage (default: 1.0)")
    fmt.println("  -d, --decay PERCENT    Set decay time as percentage (default: 10.0)")
    fmt.println("  -b, --bpm BPM          Set beats per minute (required)")
    fmt.println("  -t, --transport        Enable transport-aware mode")
    fmt.println("  -h, --help             Show this help")
}

main :: proc() {
    data := MetroData {
        frequency       = 880.0,
        amplitude       = 0.5,
        duration        = 0.1, // 100ms
        attack          = 0.01, // 1%
        decay           = 0.1, // 10%
        bpm             = 0.0,
        transport_aware = false,
        beat_counter    = 0,
        frames_to_beat  = 0,
    }

    // Parse command line arguments
    args := os.args[1:]
    i := 0

    for i < len(args) {
        arg := args[i]

        if arg == "-h" || arg == "--help" {
            print_usage()
            return
        } else if arg == "-f" || arg == "--frequency" {
            if i + 1 >= len(args) {
                fmt.eprintln("Error: -f/--frequency requires a value")
                os.exit(1)
            }
            freq, ok := strconv.parse_f64(args[i + 1])
            if !ok || freq <= 0 {
                fmt.eprintln("Error: Invalid frequency value")
                os.exit(1)
            }
            data.frequency = freq
            i += 1
        } else if arg == "-A" || arg == "--amplitude" {
            if i + 1 >= len(args) {
                fmt.eprintln("Error: -A/--amplitude requires a value")
                os.exit(1)
            }
            amp, ok := strconv.parse_f32(args[i + 1])
            if !ok || amp < 0 || amp > 1 {
                fmt.eprintln("Error: Amplitude must be between 0 and 1")
                os.exit(1)
            }
            data.amplitude = amp
            i += 1
        } else if arg == "-D" || arg == "--duration" {
            if i + 1 >= len(args) {
                fmt.eprintln("Error: -D/--duration requires a value")
                os.exit(1)
            }
            dur, ok := strconv.parse_f64(args[i + 1])
            if !ok || dur <= 0 {
                fmt.eprintln("Error: Invalid duration value")
                os.exit(1)
            }
            data.duration = dur / 1000.0 // Convert ms to seconds
            i += 1
        } else if arg == "-a" || arg == "--attack" {
            if i + 1 >= len(args) {
                fmt.eprintln("Error: -a/--attack requires a value")
                os.exit(1)
            }
            att, ok := strconv.parse_f64(args[i + 1])
            if !ok || att < 0 || att > 100 {
                fmt.eprintln("Error: Attack must be between 0 and 100 percent")
                os.exit(1)
            }
            data.attack = att / 100.0
            i += 1
        } else if arg == "-d" || arg == "--decay" {
            if i + 1 >= len(args) {
                fmt.eprintln("Error: -d/--decay requires a value")
                os.exit(1)
            }
            dec, ok := strconv.parse_f64(args[i + 1])
            if !ok || dec < 0 || dec > 100 {
                fmt.eprintln("Error: Decay must be between 0 and 100 percent")
                os.exit(1)
            }
            data.decay = dec / 100.0
            i += 1
        } else if arg == "-b" || arg == "--bpm" {
            if i + 1 >= len(args) {
                fmt.eprintln("Error: -b/--bpm requires a value")
                os.exit(1)
            }
            bpm, ok := strconv.parse_f64(args[i + 1])
            if !ok || bpm <= 0 {
                fmt.eprintln("Error: Invalid BPM value")
                os.exit(1)
            }
            data.bpm = bpm
            i += 1
        } else if arg == "-t" || arg == "--transport" {
            data.transport_aware = true
        } else {
            fmt.eprintln("Error: Unknown option:", arg)
            print_usage()
            os.exit(1)
        }

        i += 1
    }

    if data.bpm == 0.0 {
        fmt.eprintln("Error: BPM is required (-b/--bpm)")
        print_usage()
        os.exit(1)
    }

    // Set up signal handler
    global_data = &data
    libc.signal(SIGINT, signal_handler)

    // Open JACK client
    client_name := "metro"
    client_name_cstring := strings.clone_to_cstring(client_name)
    defer delete(client_name_cstring)

    client, status := jack.client_open(client_name_cstring)
    if client == nil {
        fmt.eprintln("Error: Could not open JACK client")
        os.exit(1)
    }
    defer jack.client_close(client)

    // Get sample rate and calculate timing
    data.sample_rate = jack.get_sample_rate(client)
    data.frames_per_beat = jack.NFrames(f64(data.sample_rate) * 60.0 / data.bpm)
    data.tone_length = jack.NFrames(f64(data.sample_rate) * data.duration)
    data.frames_to_beat = data.frames_per_beat

    // Set process callback
    if jack.set_process_callback(client, process, &data) != 0 {
        fmt.eprintln("Error: Could not set process callback")
        os.exit(1)
    }

    // Set sample rate callback
    if jack.set_sample_rate_callback(client, sample_rate_callback, &data) != 0 {
        fmt.eprintln("Error: Could not set sample rate callback")
        os.exit(1)
    }

    // Set shutdown callback
    jack.on_shutdown(client, shutdown, &data)

    // Register audio output port
    data.output_port = jack.audio_port_register(client, "output", {.IsOutput}, 0)
    if data.output_port == nil {
        fmt.eprintln("Error: Could not register audio output port")
        os.exit(1)
    }

    // connect the ports -- cannot be done before the client is activated
    // note: we connect this program output port to jack's physical input ports
    {
        receiving_ports := jack.get_ports(client, nil, nil, {.IsInput, .IsPhysical})
        defer delete(receiving_ports)

        if len(receiving_ports) == 0 {
            fmt.println("There are no physical ports available, exiting...")
            os.exit(1)
        }

        // Connect to the first two:
        if (jack.connect(
                   client,
                   jack.port_name(data.output_port),
                   receiving_ports[0],
               ) !=
               0) {
            fmt.println("Failed to connect ports")
        }
        if (jack.connect(
                   client,
                   jack.port_name(data.output_port),
                   receiving_ports[1],
               ) !=
               0) {
            fmt.printfln("Failed to connect ports")
        }
    }

    // Activate client
    if jack.activate(client) != 0 {
        fmt.eprintln("Error: Could not activate client")
        os.exit(1)
    }

    fmt.printf("Metronome started: %.1f BPM, %.1f Hz tone\n", data.bpm, data.frequency)
    fmt.printf(
        "Duration: %.0f ms, Attack: %.1f%%, Decay: %.1f%%\n",
        data.duration * 1000,
        data.attack * 100,
        data.decay * 100,
    )
    fmt.println("Press Ctrl+C to stop...")

    // Keep the program running
    for !data.should_exit {
        time.sleep(100 * time.Millisecond)
    }
}


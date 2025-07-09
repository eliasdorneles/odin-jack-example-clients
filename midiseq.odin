package main

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
import jack "jack"

Note :: struct {
    note_on_time:  jack.NFrames,
    note_off_time: jack.NFrames,
    midi_note:     u8,
}

AppData :: struct {
    output_port: ^jack.JackPort,
    notes:       [dynamic]Note,
    loop_nsamp:  jack.NFrames,
    loop_index:  jack.NFrames,
}

process :: proc "c" (nframes: jack.NFrames, arg: rawptr) -> i32 {
    context = runtime.default_context()
    data := cast(^AppData)arg

    port_buffer := jack.port_get_buffer(data.output_port, nframes)
    jack.midi_clear_buffer(port_buffer)

    for i in 0 ..< nframes {
        for note in data.notes {
            // Check for note on event
            if data.loop_index == note.note_on_time {
                event_buffer := jack.midi_event_reserve(port_buffer, i, 3)
                if event_buffer != nil {
                    event_buffer[0] = 0x90 // Note on, channel 1
                    event_buffer[1] = note.midi_note
                    event_buffer[2] = 64 // Velocity
                }
            }

            // Check for note off event
            if data.loop_index == note.note_off_time {
                event_buffer := jack.midi_event_reserve(port_buffer, i, 3)
                if event_buffer != nil {
                    event_buffer[0] = 0x80 // Note off, channel 1
                    event_buffer[1] = note.midi_note
                    event_buffer[2] = 64 // Velocity
                }
            }
        }

        data.loop_index += 1
        if data.loop_index >= data.loop_nsamp {
            data.loop_index = 0
        }
    }

    return 0
}

shutdown :: proc "c" (arg: rawptr) {
    context = runtime.default_context()
    fmt.println("JACK server shutdown")
    os.exit(1)
}

main :: proc() {
    if len(os.args) < 4 {
        fmt.eprintln(
            "Usage: midiseq <client_name> <loop_nsamp> <note_on_time> <note> [<note_off_time> <note_on_time> <note> ...]",
        )
        fmt.eprintln("Example: midiseq Sequencer 24000 0 60 8000 12000 63 8000")
        os.exit(1)
    }

    client_name := os.args[1]

    loop_nsamp_str := os.args[2]
    loop_nsamp, ok := strconv.parse_uint(loop_nsamp_str, 10)
    if !ok {
        fmt.eprintln("Error: loop_nsamp must be a valid number")
        os.exit(1)
    }

    data := AppData {
        loop_nsamp = jack.NFrames(loop_nsamp),
        loop_index = 0,
    }

    // Parse notes from command line
    i := 3
    for i < len(os.args) {
        if i + 2 >= len(os.args) {
            fmt.eprintln("Error: incomplete note specification")
            os.exit(1)
        }

        note_on_time_str := os.args[i]
        note_str := os.args[i + 1]
        note_off_time_str := os.args[i + 2]

        note_on_time, ok1 := strconv.parse_uint(note_on_time_str, 10)
        midi_note, ok2 := strconv.parse_uint(note_str, 10)
        note_off_time, ok3 := strconv.parse_uint(note_off_time_str, 10)

        if !ok1 || !ok2 || !ok3 {
            fmt.eprintln("Error: note parameters must be valid numbers")
            os.exit(1)
        }

        if midi_note > 127 {
            fmt.eprintln("Error: MIDI note must be between 0 and 127")
            os.exit(1)
        }

        note := Note {
            note_on_time  = jack.NFrames(note_on_time),
            note_off_time = jack.NFrames(note_off_time),
            midi_note     = u8(midi_note),
        }

        append(&data.notes, note)
        i += 3
    }

    // Open JACK client
    client_name_cstring := strings.clone_to_cstring(client_name)
    defer delete(client_name_cstring)
    client, status := jack.client_open(client_name_cstring)
    if client == nil {
        fmt.eprintln("Error: Could not open JACK client")
        os.exit(1)
    }
    defer jack.client_close(client)

    // Set process callback
    if jack.set_process_callback(client, process, &data) != 0 {
        fmt.eprintln("Error: Could not set process callback")
        os.exit(1)
    }

    // Set shutdown callback
    jack.on_shutdown(client, shutdown, &data)

    // Register MIDI output port
    data.output_port = jack.midi_port_register(client, "midi_out", {.IsOutput}, 0)
    if data.output_port == nil {
        fmt.eprintln("Error: Could not register MIDI output port")
        os.exit(1)
    }

    // Activate client
    if jack.activate(client) != 0 {
        fmt.eprintln("Error: Could not activate client")
        os.exit(1)
    }

    fmt.printf(
        "MIDI sequencer '%s' running with %d notes in %d sample loop\n",
        client_name,
        len(data.notes),
        loop_nsamp,
    )
    fmt.println("Press Ctrl+C to exit...")

    // Keep the program running
    for {
        time.sleep(100 * time.Millisecond)
    }
}


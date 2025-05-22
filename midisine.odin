package jack_midisine

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:math"
import "core:os"
import "core:time"
import "jack"

audio_output_port: ^jack.JackPort
midi_input_port: ^jack.JackPort

// This will store values per each MIDI note that we'll use later to generate
// the sine wave.
// The values here will represent the necessary increments for each sample in
// order to generate the desired frequency for the currently playing note.
note_freqs: [128]f32

left_phase: c.int
right_phase: c.int

ramp: f32 = 0.0
note_on: f32 = 0.0
note: u8 = 0

process :: proc "c" (nframes: jack.NFrames, data: rawptr) -> i32 {
	out := (cast([^]f32)jack.port_get_buffer(audio_output_port, nframes))[0:nframes]
	volume :: 0.2

    context = runtime.default_context()

	port_buf := jack.port_get_buffer(midi_input_port, nframes)

	event_count := jack.midi_get_event_count(port_buf)
	if (event_count > 0) {
		fmt.println("event_count = ", event_count)
	}

	event_index: u32 = 0

	// load the first event...
	in_event, loaded := jack.midi_event_get(port_buf, 0)
	// ...and then iterate over all frames
	for i in 0 ..< len(out) {
		if (in_event.time == u32(i) && event_index < event_count) {
			event_data := in_event.buffer
			if (event_data[0] == 0x90) {
				// note on event
				note = event_data[1]
				note_on = 1.0
				// TODO: handle velocity from event_data[2]
			} else if (event_data[0] == 0x80) {
				// note off event
				note = event_data[1]
				note_on = 0.0
			}
			fmt.printf("    note %d %s\n", note, ("on" if (note_on > 0) else "off"))
			event_index += 1
			if (event_index < event_count) {
				// load the next event
				in_event, loaded = jack.midi_event_get(port_buf, event_index)
			}
		}
		ramp += note_freqs[note]
		ramp = ramp - 2.0 if (ramp > 1.0) else ramp

		out[i] = note_on * math.sin(2 * math.PI * ramp)
	}

	return 0
}

calc_note_freqs :: proc "c" (sample_rate: u32) {
	for i in 0 ..< len(note_freqs) {
		note_freqs[i] = 440.0 / 16.0 * math.pow(2.0, (f32(i) - 9.0) / 12.0) / f32(sample_rate)
	}
}

sample_rate_callback :: proc "c" (nframes: jack.NFrames, data: rawptr) -> i32 {
	calc_note_freqs(nframes)
	return 0
}

main :: proc() {
	client, status := jack.client_open("midisine")
	if client == nil {
		fmt.printfln("Failed to open client, status=%s", status)
		os.exit(1)
	}
	defer {
		jack.client_close(client)
		fmt.println("Client closed")
		os.exit(0)
	}

	calc_note_freqs(jack.get_sample_rate())

	jack.set_process_callback(client, process, nil)

	jack.set_sample_rate_callback(client, sample_rate_callback, nil)

	midi_input_port = jack.midi_port_register(client, "midi_in", {.IsInput}, 0)
	audio_output_port = jack.audio_port_register(client, "audio_out", {.IsOutput}, 0)

	if (midi_input_port == nil || audio_output_port == nil) {
		fmt.println("Failed to create ports")
		os.exit(1)
	}

	// from here on, JACK will start calling the process callback
	if jack.activate(client) != 0 {
		fmt.println("Failed to activate client")
		jack.client_close(client)
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

		if (jack.connect(client, jack.port_name(audio_output_port), receiving_ports[0]) != 0) {
			fmt.println("Failed to connect ports")
		}
		if (jack.connect(client, jack.port_name(audio_output_port), receiving_ports[1]) != 0) {
			fmt.printfln("Failed to connect ports")
		}
	}

	fmt.println("Hit Ctrl-C to quit...")
	for do time.sleep(time.Second)
}

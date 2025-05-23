package jack_simple_client

import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:math"
import "core:os"
import "core:time"
import "jack"

output_port1: ^jack.JackPort
output_port2: ^jack.JackPort

TABLE_SIZE :: 200
sine_table: [TABLE_SIZE]f32

left_phase: c.int
right_phase: c.int

process :: proc "c" (nframes: jack.NFrames, data: rawptr) -> i32 {
	out1 := (cast([^]f32)jack.port_get_buffer(output_port1, nframes))[0:nframes]
	out2 := (cast([^]f32)jack.port_get_buffer(output_port2, nframes))[0:nframes]
	volume :: 0.2

	for i in 0 ..< nframes {
		out1[i] = volume * sine_table[left_phase]
		out2[i] = volume * sine_table[right_phase]
		left_phase += 1
		right_phase += 3
		if left_phase >= TABLE_SIZE {
			left_phase -= TABLE_SIZE
		}
		if right_phase >= TABLE_SIZE {
			right_phase -= TABLE_SIZE
		}
	}

	return 0
}

main :: proc() {
	// Fill the table with sine values
	for i in 0 ..< len(sine_table) {
		sine_table[i] = math.sin_f32(f32(i) / f32(TABLE_SIZE) * 2 * math.PI)
	}

	client, status := jack.client_open("simple_client")
	if client == nil {
		fmt.printfln("Failed to open client, status=%s", status)
		os.exit(1)
	}
	defer {
		jack.client_close(client)
		fmt.println("Client closed")
		os.exit(0)
	}

	jack.set_process_callback(client, process, nil)

	// register two output ports
	output_port1 = jack.audio_port_register(client, "output1", {.IsOutput}, 0)
	output_port2 = jack.audio_port_register(client, "output2", {.IsOutput}, 0)

	if (output_port1 == nil || output_port2 == nil) {
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
	// note: we connect this program output ports to jack's physical input ports
	{
		input_ports := jack.get_ports(client, nil, nil, {.IsInput, .IsPhysical})
		defer delete(input_ports)

		if len(input_ports) == 0 {
			fmt.println("There are no physical ports available, exiting...")
			os.exit(1)
		}

		if (jack.connect(client, jack.port_name(output_port1), input_ports[0]) != 0) {
			fmt.println("Failed to connect ports")
		}
		if (jack.connect(client, jack.port_name(output_port2), input_ports[1]) != 0) {
			fmt.printfln("Failed to connect ports")
		}
	}

	fmt.println("Hit Ctrl-C to quit...")
	for do time.sleep(time.Second)
}

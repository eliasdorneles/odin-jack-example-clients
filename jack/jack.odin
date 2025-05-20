package jack_bindings

import "core:c"
import "core:strings"

foreign import lib "system:jack"

// Constants
DEFAULT_AUDIO_TYPE :: "32 bit float mono audio"
DEFAULT_MIDI_TYPE :: "8 bit raw midi"

Status :: enum c.int {
	// Docs: https://jackaudio.org/api/types_8h.html#aaf80297bce18297403b99e3d320ac8a8
	Failure       = 1, // Overall operation failed.
	InvalidOption = 2, // The operation contained an invalid or unsupported option.
	NameNotUnique = 4,
	ServerStarted = 8,
	ServerFailed  = 16, // Unable to connect to the JACK server.
	ServerError   = 32, // Communication error with the JACK server.
	NoSuchClient  = 64,
	LoadFailure   = 128, // Unable to load internal client
	InitFailure   = 256, // Unable to initialize client
	ShmFailure    = 512, // Unable to access shared memory
	VersionError  = 1024,
	BackendError  = 2048,
	ClientZombie  = 4096,
}

Options :: enum c.int {
	// Docs: https://jackaudio.org/api/types_8h.html#a396617de2ef101891c51346f408a375e
	NullOption    = 0,
	NoStartServer = 1,
	UseExactName  = 2,
	ServerName    = 4,
	LoadName      = 8,
	LoadInit      = 16,
	SessionID     = 32,
}

PortFlag :: enum c.int {
	// NOTE: this enum is used as a bit_set, so it doesn't need the API values
	// e.g. 1, 2, 4, 8, ... to be defined here, they're calculated by transmuting
	// the bitset into an int
	// Docs: https://jackaudio.org/api/types_8h.html#acbcada380e9dfdd5bff1296e7156f478
	IsInput, // 1
	IsOutput, // 2,
	IsPhysical, // 4,
	CanMonitor, // 8,
	IsTerminal, // 16,
}
PortFlags :: distinct bit_set[PortFlag;c.int]

JackClient :: struct {
	// opaque type -- same as jack_client_t in the C API
}
JackPort :: struct {
	// opaque type -- same as jack_port_t in the C API
}

// Jack MIDI Event (from midiport.h)
MidiData :: u8
MidiEvent :: struct {
	time:   NFrames, /**< Sample index at which event is valid */
	size:   c.size_t, /**< Number of bytes of data in \a buffer */
	buffer: [^]MidiData, /**< Raw MIDI data */
}

// Basic type aliases
NFrames :: u32 // jack_nframes_t in the C API

// Callback prototypes
JackProcessCallback :: proc "c" (_: NFrames, _: rawptr) -> i32
JackSampleRateCallback :: proc "c" (_: NFrames, _: rawptr) -> i32
JackBufferSizeCallback :: proc "c" (_: NFrames, _: rawptr) -> i32

// Here we expose the C API functions that are good-enough to expose as-is
// Reference docs: https://jackaudio.org/api/jack_8h.html
@(default_calling_convention = "c", link_prefix = "jack_")
foreign lib {
	get_version_string :: proc() -> cstring ---
	client_close :: proc(client: ^JackClient) -> i32 ---
	get_client_name :: proc(client: ^JackClient) -> cstring ---
	get_sample_rate :: proc() -> NFrames ---

	set_process_callback :: proc(client: ^JackClient, process_callback: JackProcessCallback, arg: rawptr) -> i32 ---
	set_sample_rate_callback :: proc(client: ^JackClient, srate_callback: JackSampleRateCallback, arg: rawptr) -> i32 ---

	port_unregister :: proc(client: ^JackClient, port: ^JackPort) -> i32 ---

	activate :: proc(client: ^JackClient) -> i32 ---
	deactivate :: proc(client: ^JackClient) -> i32 ---

	connect :: proc(client: ^JackClient, source_port: cstring, destination_port: cstring) -> i32 ---
	port_name :: proc(port: ^JackPort) -> cstring ---

	port_get_buffer :: proc(port: ^JackPort, nframes: NFrames) -> rawptr ---

	// from midiport.h
	midi_get_event_count :: proc(port_buffer: rawptr) -> u32 ---
}


// Here we import functions that we'd rather use through a nice wrapper
// function that will provide better API ergonomics
@(default_calling_convention = "c")
foreign lib {

	@(private = "file")
	jack_client_open :: proc(client_name: cstring, options: Options, status: ^Status) -> ^JackClient ---

	@(private = "file")
	jack_port_register :: proc(client: ^JackClient, port_name: cstring, port_type: cstring, flags: c.ulong, buffer_size: c.ulong) -> ^JackPort ---

	@(private = "file")
	jack_get_ports :: proc(client: ^JackClient, port_name_pattern: cstring, type_name_pattern: cstring, flags: c.ulong) -> [^]cstring ---

	@(private = "file")
	jack_midi_event_get :: proc(event: ^MidiEvent, port_buffer: rawptr, event_index: u32) -> i32 ---

	/*
     * This function is to be used on memory returned by
     * jack_port_get_connections, jack_port_get_all_connections, jack_get_ports
     * and jack_get_internal_client_name functions.
	*/
	@(private = "file")
	jack_free :: proc(ptr: rawptr) ---
}


// Utility functions used by the wrappers
@(private = "file")
_port_flags_ulong_value :: proc(flags: PortFlags) -> c.ulong {
	return c.ulong(transmute(c.int)flags)
}

@(private = "file")
_build_cstring_dynamic_array_from_multipointer :: proc(
	cstring_mp: [^]cstring,
) -> [dynamic]cstring {
	result: [dynamic]cstring
	if cstring_mp == nil do return result
	for i := 0; cstring_mp[i] != nil; i += 1 {
		append(
			&result,
			strings.unsafe_string_to_cstring(strings.clone_from_cstring(cstring_mp[i])),
		)
	}
	return result
}

// API Wrappers around the native C JACK API calls that make for a better API
client_open :: proc(
	client_name: cstring,
	options: Options = Options.NullOption,
) -> (
	^JackClient,
	Status,
) {
	status: Status
	client := jack_client_open(client_name, options, &status)
	return client, status
}

port_register :: proc(
	client: ^JackClient,
	port_name: cstring,
	port_type: cstring,
	flags: PortFlags,
	buffer_size: u64,
) -> ^JackPort {
	return jack_port_register(
		client,
		port_name,
		port_type,
		_port_flags_ulong_value(flags),
		buffer_size,
	)
}

audio_port_register :: proc(
	client: ^JackClient,
	port_name: cstring,
	flags: PortFlags,
	buffer_size: u64,
) -> ^JackPort {
	return port_register(client, port_name, DEFAULT_AUDIO_TYPE, flags, buffer_size)
}

midi_port_register :: proc(
	client: ^JackClient,
	port_name: cstring,
	flags: PortFlags,
	buffer_size: u64,
) -> ^JackPort {
	return port_register(client, port_name, DEFAULT_MIDI_TYPE, flags, buffer_size)
}

get_ports :: proc(
	client: ^JackClient,
	port_name_pattern: cstring = nil,
	type_name_pattern: cstring = nil,
	flags: PortFlags = {},
) -> [dynamic]cstring {
	jack_result := jack_get_ports(
		client,
		port_name_pattern,
		type_name_pattern,
		_port_flags_ulong_value(flags),
	)
	defer jack_free(jack_result)

	return _build_cstring_dynamic_array_from_multipointer(jack_result)
}

midi_event_get :: proc "c" (port_buffer: rawptr, event_index: u32) -> (MidiEvent, bool) {
	event: MidiEvent
	if (jack_midi_event_get(&event, port_buffer, event_index) == 0) {
		return event, true
	}
	return event, false
}

package jack_capture_client

import "base:runtime"
import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import "jack"
import sf "sndfile"

ThreadInfo :: struct {
    sf:          ^sf.SNDFILE, // sndfile stream
    duration:    jack.NFrames, // duration in frames
    rb_size:     jack.NFrames, // ring buffer size (num of samples, per channel)
    client:      ^jack.JackClient, // JACK client
    channels:    u32, // number of channels
    bitdepth:    int, // bit depth
    path:        cstring, // file path

    // Here we are using atomic types instead of the volatile trick
    // used in the original C code
    // XXX: are there Odin-specific types or do we have to use the libc.atomic_... ones??
    can_capture: libc.atomic_bool,
    can_process: libc.atomic_bool,
}

// JACK data
SAMPLE_SIZE :: size_of(f32)
nports: u32
sink_ports: []^jack.JackPort
input_samples: []^f32

// synchronization stuffz
disk_thread_lock: sync.Mutex
data_ready: sync.Cond
shared_rb: ^jack.RingBuffer

overruns: u32

/*
 * The process callback for this JACK application is called in a
 * special realtime thread once for each audio cycle.
 * It will read the audio data from the JACK ports and write it to the
 * ringbuffer.
 */
process :: proc "c" (nframes: jack.NFrames, data: rawptr) -> i32 {
    context = runtime.default_context()
    thread_info := cast(^ThreadInfo)data
    if !sync.atomic_load_explicit(&thread_info^.can_process, .Acquire) {
        return 0
    }
    if !sync.atomic_load_explicit(&thread_info^.can_capture, .Acquire) {
        return 0
    }

    for chn: u32 = 0; chn < nports; chn += 1 {
        input_samples[chn] = cast(^f32)jack.port_get_buffer(sink_ports[chn], nframes)
    }

    // Sndfile requires interleaved data.  It is simpler here to
    // just queue interleaved samples to a single ringbuffer.
    for i: u32 = 0; i < nframes; i += 1 {
        for chn: u32 = 0; chn < nports; chn += 1 {
            written_bytes := jack.ringbuffer_write(
                shared_rb,
                cast([^]u8)mem.ptr_offset(input_samples[chn], i),
                SAMPLE_SIZE,
            )
            if (written_bytes < SAMPLE_SIZE) {
                overruns += 1
            }
        }
    }

    // Tell the disk thread there is work to do.  If it is already running, the
    // lock will not be available.  We can't wait here in the process() thread,
    // but we don't need to signal in that case, because the disk thread will
    // read all the data queued before waiting again.
    if (sync.mutex_try_lock(&disk_thread_lock)) {
        sync.cond_signal(&data_ready)
        sync.mutex_unlock(&disk_thread_lock)
    }

    return 0
}

EIO :: 5

total_captured_frames: jack.NFrames = 0

write_sndfile_thread :: proc(t: ^thread.Thread) {
    thread_info := cast(^ThreadInfo)t.data
    samples_per_frame: jack.NFrames = thread_info^.channels
    bytes_per_frame := samples_per_frame * SAMPLE_SIZE
    framebuf: [dynamic]u8

    resize(&framebuf, bytes_per_frame)
    defer delete(framebuf)

    // here we need to lock on the disk_thread_lock mutex
    if sync.mutex_guard(&disk_thread_lock) {
        for {
            // Write the data one frame at a time.  This is inefficient, but
            // makes things simpler, because we can then just send interleaved
            // data to the buffer in process() callback.
            // Here, 1 frame == 2 floats (1 for each channel)
            can_capture := sync.atomic_load_explicit(&thread_info^.can_capture, .Acquire)
            for (can_capture &&
                    (jack.ringbuffer_read_space(shared_rb) >= bytes_per_frame)) {
                jack.ringbuffer_read(shared_rb, raw_data(framebuf), bytes_per_frame)

                if (sf.writef_float(thread_info^.sf, cast(^f32)raw_data(framebuf), 1) !=
                       1) {
                    fmt.eprintln("Cannot write sndfile:", sf.strerror(thread_info^.sf))
                    return
                }
                //
                total_captured_frames += 1
                if (total_captured_frames >= thread_info^.duration) {
                    fmt.println("Write to disk thread finished")
                    return
                }
            }

            /* wait until process() signals more data */
            sync.cond_wait(&data_ready, &disk_thread_lock)
        }
    }
}

jack_shutdown :: proc "c" (_: rawptr) {
    context = runtime.default_context()
    fmt.eprintln("JACK shut down, exiting ...")
    os.exit(1)
}


/*
 * This function sets up the disk thread.  It opens the SNDFILE stream
 * with the given parameters and starts the disk thread.
 */
setup_write_sndfile_thread :: proc(thread_info: ^ThreadInfo) -> ^thread.Thread {
    sf_info: sf.SF_INFO

    sf_info.samplerate = jack.get_sample_rate(thread_info^.client)
    fmt.println("-> samplerate = ", sf_info.samplerate)
    sf_info.channels = thread_info^.channels
    fmt.println("-> channels = ", sf_info.channels)

    sf_info.format = sf.FORMAT_WAV | sf.FORMAT_PCM_32
    thread_info^.sf = sf.open(thread_info^.path, .WRITE, &sf_info)
    if (thread_info^.sf == nil) {
        fmt.eprintf("Cannot open sndfile for writing: %s\n", sf.strerror(nil))
        jack.client_close(thread_info^.client)
        os.exit(1)
    }

    thread_info^.duration *= sf_info.samplerate // from seconds to frames
    fmt.println("-> duration in frames = ", thread_info^.duration)

    // now we're ready to create the disk thread
    t := thread.create(write_sndfile_thread)
    t.data = thread_info
    thread.start(t)
    return t
}


CliArgs :: struct {
    verbose:     bool,
    buf_size:    u32,
    output_path: string,
    duration:    u32,
    ports:       []string,
}

main :: proc() {
    // TODO: implement actual argument parsing -- hardcoding them for now
    args := CliArgs {
        verbose     = false,
        buf_size    = 16384, // ring buffer size
        output_path = "wave_out.wav",
        duration    = 3,
        ports       = {}, // Will be populated with physical ports
    }

    fmt.println("CLI args:", args)

    client, status := jack.client_open("simple_client")
    if client == nil {
        fmt.eprintfln("Failed to open client, status=%s", status)
        os.exit(1)
    }

    // Here we get first two physical output ports, to record from them
    source_ports := jack.get_ports(client, nil, nil, {.IsOutput, .IsPhysical})
    defer delete(source_ports)

    if len(source_ports) == 0 {
        fmt.eprintln("No physical output ports found")
        jack.client_close(client)
        os.exit(1)
    }

    // Use first one or two physical outputs, if available
    num_ports := min(len(source_ports), 2)
    args.ports = make([]string, num_ports)
    for i in 0..<num_ports {
        args.ports[i] = strings.clone_from_cstring(source_ports[i])
    }

    fmt.println("Will record from:")
    for port, i in args.ports {
        fmt.printf("  %d: %s\n", i, port)
    }

    nports = u32(len(args.ports))
    thread_info := ThreadInfo {
        rb_size  = args.buf_size,
        channels = u32(len(args.ports)),
        duration = args.duration,
        path     = strings.clone_to_cstring(args.output_path),
    }
    thread_info.client = client

    disk_thread := setup_write_sndfile_thread(&thread_info)

    jack.set_process_callback(client, process, &thread_info)
    jack.on_shutdown(client, jack_shutdown, &thread_info)


    // from here on, JACK will start calling the process callback
    if jack.activate(client) != 0 {
        fmt.eprintln("Failed to activate client")
        jack.client_close(client)
        os.exit(1)
    }

    // now, let's set up the JACK ports and connects them to the sources
    // note: we cannot do before the client is activated
    sink_ports = make([]^jack.JackPort, nports)
    input_samples = make([]^f32, nports)
    shared_rb = jack.ringbuffer_create(nports * SAMPLE_SIZE * args.buf_size)
    mem.set(shared_rb^.buf, 0, int(shared_rb^.size))

    // first, we create all sink ports, i.e. the ports we'll write to...
    for i in 0 ..< nports {
        port_name := strings.clone_to_cstring(fmt.aprintf("input%d", i + 1))
        sink_ports[i] = jack.audio_port_register(client, port_name, {.IsInput}, 0)
        if sink_ports[i] == nil {
            fmt.eprintln("Cannot register input port:", port_name)
            jack.client_close(client)
            os.exit(1)
        }
    }

    // then, we connect the user-provided source ports to the sink ports
    for i in 0 ..< nports {
        if (jack.connect(
                   client,
                   strings.clone_to_cstring(args.ports[i]),
                   jack.port_name(sink_ports[i]),
               ) !=
               0) {
            fmt.eprintfln("Failed to connect ports")
            jack.client_close(client)
            os.exit(1)
        }
    }
    fmt.println("Ready to start recording now")

    // XXX: couldn't we replace these two atomic variables by only one??
    sync.atomic_store_explicit(&thread_info.can_process, true, .Release)
    sync.atomic_store_explicit(&thread_info.can_capture, true, .Release)

    // ... wait for the disk thread to finish writing until the user-specified duration
    thread.join(disk_thread)

    // then, let's close the file and say good-bye!
    sf.close(thread_info.sf)

    if (overruns > 0) {
        fmt.eprintf("JACK failed with %d overruns\n", overruns)
        fmt.eprintf("  try a bigger buffer than -B %d\n", args.buf_size)
    }

    jack.client_close(client)
    jack.ringbuffer_free(shared_rb)

    fmt.println("Finished")
}

package sndfile_example

import "core:c"
import "core:fmt"
import "core:math"
import "core:os"
import sf "sndfile"

TABLE_SIZE :: 200
sine_table: [TABLE_SIZE]f32

main :: proc() {
	// Fill the table with sine values
	for i in 0 ..< len(sine_table) {
		sine_table[i] = math.sin_f32(f32(i) / f32(TABLE_SIZE) * 2 * math.PI)
	}

	// Global params
	volume: f32 = 0.3
	samplerate: i32 = 44100
	nchannels: i32 = 2
	duration: i32 = 3 // seconds
	outfile: cstring = "out_sndfile_test.wav"


	// Here we build the SF_INFO struct, which configures the output WAV file
	sf_info: sf.SF_INFO
	sf_info.samplerate = samplerate
	sf_info.channels = nchannels
	sf_info.format = sf.FORMAT_WAV | sf.FORMAT_PCM_32

	sf_file := sf.open(outfile, .WRITE, &sf_info)
	if (sf_file == nil) {
		fmt.printf("Cannot open sndfile %s for writing: %s\n", outfile, sf.strerror(nil))
		os.exit(1)
	}

	nframes := samplerate * duration

	buffer_size :: 1024
	buffer: [buffer_size]f32
	left_phase := 0
	right_phase := 0

	// Now, we'll proceed by generating the audio samples and writing them to the WAV file
	needed_iterations := nframes / (buffer_size / nchannels)
	for _ in 1 ..= needed_iterations {
		// First, we fill the buffer with interleaved left and right channel samples...
		for buf_index := 0; buf_index < buffer_size - 1; buf_index += 2 {
			left_phase += 1
			if (left_phase >= TABLE_SIZE) {
				left_phase -= TABLE_SIZE
			}
			// we use a different phase for the right channel, to have a different note:
			right_phase += 2
			if (right_phase >= TABLE_SIZE) {
				right_phase -= TABLE_SIZE
			}
			buffer[buf_index] = volume * sine_table[left_phase]
			buffer[buf_index + 1] = volume * sine_table[right_phase]
		}

		// Then, we write the buffer to the output file -- note that we divide
		// buffer_size by nchannels to get the correct number of frames
		frames_to_write: sf.sf_count_t = i64(buffer_size / nchannels)
		sf.writef(sf_file, cast(^f32)&buffer, frames_to_write)
	}

	sf.close(sf_file)
	fmt.printf("Wrote %d frames to %s\n", nframes, outfile)
}

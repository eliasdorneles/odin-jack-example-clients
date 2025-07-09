# Odin JACK Audio Examples

Real-time audio programming examples using the [JACK Audio Connection
Kit](https://jackaudio.org/) and the [Odin programming
language](https://odin-lang.org).

These are ports of the official JACK example clients, demonstrating audio
generation, MIDI processing, and audio capture.

## Quick Start

### Prerequisites

1. **Install JACK development libraries:**
   ```bash
   # Ubuntu/Debian
   sudo apt install libjack-jackd2-dev
   
   # Fedora/RHEL
   sudo dnf install jack-audio-connection-kit-devel
   ```

2. **Audio server:** You need either JACK or PipeWire running. Most modern
   Linux distributions run PipeWire by default, which provides JACK
   compatibility.

3. **Odin compiler:** Download from [odin-lang.org](https://odin-lang.org)

### Building and Running

```bash
# Build all programs
make all

# Or build individual programs
make simple_client
make midisine
make capture_client
make midiseq

# Run a program
./simple_client
```

## Available Programs

### `simple_client`
Generates a stereo sine wave output to test your audio setup.
```bash
./simple_client
```

### `midisine` 
MIDI-triggered sine wave synthesizer. Connect a MIDI controller to hear notes.
```bash
./midisine
```

**Note:** This Odin version includes a full ADSR envelope (Attack, Decay, Sustain, Release) with smooth legato transitions, unlike the original C version which has no envelope.

### `capture_client`
Records audio from your microphone/line input to a WAV file.
```bash
./capture_client output.wav
```

### `midiseq`
A MIDI sequencer that loops a programmed sequence of notes.
```bash
# Play C4 at start, D#4 at quarter point in a half-second loop
./midiseq Sequencer 24000 0 60 8000 12000 63 8000
```

**Arguments:** `<client_name> <loop_samples> <note_on_time> <note> <note_off_time> ...`
- `loop_samples`: Loop length in samples (24000 ≈ 0.5s at 48kHz)
- `note_on_time`: When to start the note (in samples)
- `note`: MIDI note number (60 = C4, 63 = D#4)
- `note_off_time`: When to stop the note (in samples)

**To hear sound:** `midiseq` outputs MIDI events, not audio. Connect it to a
synthesizer using `qjackctl` or some other connection tool. You can use
`./midisine` as the synthesizer - just connect `midiseq:midi_out` to
`midisine:midi_in`.

Press Ctrl+C to stop (all notes will be turned off cleanly).

### `metro`
An audio metronome with configurable timing and tone characteristics.
```bash
# Simple 120 BPM metronome
./metro -b 120

# Custom metronome: 100 BPM, 440Hz tone, 200ms duration
./metro -b 100 -f 440 -D 200 -A 0.8
```

**Options:**
- `-b, --bpm BPM`: Beats per minute (required)
- `-f, --frequency FREQ`: Tone frequency in Hz (default: 880)
- `-A, --amplitude AMP`: Amplitude 0-1 (default: 0.5)
- `-D, --duration MS`: Tone duration in milliseconds (default: 100)
- `-a, --attack PERCENT`: Attack time as percentage (default: 1.0)
- `-d, --decay PERCENT`: Decay time as percentage (default: 10.0)


## Getting Help

- Use `make help` to see available build targets
- Check the [JACK documentation](https://jackaudio.org/api/) for audio
  programming concepts
- See `CLAUDE.md` for development details

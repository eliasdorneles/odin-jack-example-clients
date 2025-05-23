package sndfile

import "core:c"

foreign import lib "system:libsndfile.so"


/* Major formats. */
FORMAT_WAV :: 0x010000 /* Microsoft WAV format (little endian default). */
FORMAT_AIFF :: 0x020000 /* Apple/SGI AIFF format (big endian). */
FORMAT_AU :: 0x030000 /* Sun/NeXT AU format (big endian). */
FORMAT_RAW :: 0x040000 /* RAW PCM data. */
FORMAT_PAF :: 0x050000 /* Ensoniq PARIS file format. */
FORMAT_SVX :: 0x060000 /* Amiga IFF / SVX8 / SV16 format. */
FORMAT_NIST :: 0x070000 /* Sphere NIST format. */
FORMAT_VOC :: 0x080000 /* VOC files. */
FORMAT_IRCAM :: 0x0A0000 /* Berkeley/IRCAM/CARL */
FORMAT_W64 :: 0x0B0000 /* Sonic Foundry's 64 bit RIFF/WAV */
FORMAT_MAT4 :: 0x0C0000 /* Matlab (tm) V4.2 / GNU Octave 2.0 */
FORMAT_MAT5 :: 0x0D0000 /* Matlab (tm) V5.0 / GNU Octave 2.1 */
FORMAT_PVF :: 0x0E0000 /* Portable Voice Format */
FORMAT_XI :: 0x0F0000 /* Fasttracker 2 Extended Instrument */
FORMAT_HTK :: 0x100000 /* HMM Tool Kit format */
FORMAT_SDS :: 0x110000 /* Midi Sample Dump Standard */
FORMAT_AVR :: 0x120000 /* Audio Visual Research */
FORMAT_WAVEX :: 0x130000 /* MS WAVE with WAVEFORMATEX */
FORMAT_SD2 :: 0x160000 /* Sound Designer 2 */
FORMAT_FLAC :: 0x170000 /* FLAC lossless file format */
FORMAT_CAF :: 0x180000 /* Core Audio File format */
FORMAT_WVE :: 0x190000 /* Psion WVE format */
FORMAT_OGG :: 0x200000 /* Xiph OGG container */
FORMAT_MPC2K :: 0x210000 /* Akai MPC 2000 sampler */
FORMAT_RF64 :: 0x220000 /* RF64 WAV file */
FORMAT_MPEG :: 0x230000 /* MPEG-1/2 audio stream */

/* Subtypes from here on. */

FORMAT_PCM_S8 :: 0x0001 /* Signed 8 bit data */
FORMAT_PCM_16 :: 0x0002 /* Signed 16 bit data */
FORMAT_PCM_24 :: 0x0003 /* Signed 24 bit data */
FORMAT_PCM_32 :: 0x0004 /* Signed 32 bit data */

FORMAT_PCM_U8 :: 0x0005 /* Unsigned 8 bit data (WAV and RAW only) */

FORMAT_FLOAT :: 0x0006 /* 32 bit float data */
FORMAT_DOUBLE :: 0x0007 /* 64 bit float data */

FORMAT_ULAW :: 0x0010 /* U-Law encoded. */
FORMAT_ALAW :: 0x0011 /* A-Law encoded. */
FORMAT_IMA_ADPCM :: 0x0012 /* IMA ADPCM. */
FORMAT_MS_ADPCM :: 0x0013 /* Microsoft ADPCM. */

FORMAT_GSM610 :: 0x0020 /* GSM 6.10 encoding. */
FORMAT_VOX_ADPCM :: 0x0021 /* OKI / Dialogix ADPCM */

FORMAT_NMS_ADPCM_16 :: 0x0022 /* 16kbs NMS G721-variant encoding. */
FORMAT_NMS_ADPCM_24 :: 0x0023 /* 24kbs NMS G721-variant encoding. */
FORMAT_NMS_ADPCM_32 :: 0x0024 /* 32kbs NMS G721-variant encoding. */

FORMAT_G721_32 :: 0x0030 /* 32kbs G721 ADPCM encoding. */
FORMAT_G723_24 :: 0x0031 /* 24kbs G723 ADPCM encoding. */
FORMAT_G723_40 :: 0x0032 /* 40kbs G723 ADPCM encoding. */

FORMAT_DWVW_12 :: 0x0040 /* 12 bit Delta Width Variable Word encoding. */
FORMAT_DWVW_16 :: 0x0041 /* 16 bit Delta Width Variable Word encoding. */
FORMAT_DWVW_24 :: 0x0042 /* 24 bit Delta Width Variable Word encoding. */
FORMAT_DWVW_N :: 0x0043 /* N bit Delta Width Variable Word encoding. */

FORMAT_DPCM_8 :: 0x0050 /* 8 bit differential PCM (XI only) */
FORMAT_DPCM_16 :: 0x0051 /* 16 bit differential PCM (XI only) */

FORMAT_VORBIS :: 0x0060 /* Xiph Vorbis encoding. */
FORMAT_OPUS :: 0x0064 /* Xiph/Skype Opus encoding. */

FORMAT_ALAC_16 :: 0x0070 /* Apple Lossless Audio Codec (16 bit). */
FORMAT_ALAC_20 :: 0x0071 /* Apple Lossless Audio Codec (20 bit). */
FORMAT_ALAC_24 :: 0x0072 /* Apple Lossless Audio Codec (24 bit). */
FORMAT_ALAC_32 :: 0x0073 /* Apple Lossless Audio Codec (32 bit). */

FORMAT_MPEG_LAYER_I :: 0x0080 /* MPEG-1 Audio Layer I */
FORMAT_MPEG_LAYER_II :: 0x0081 /* MPEG-1 Audio Layer II */
FORMAT_MPEG_LAYER_III :: 0x0082 /* MPEG-2 Audio Layer III */

/* Endian-ness options. */

ENDIAN_FILE :: 0x00000000 /* Default file endian-ness. */
ENDIAN_LITTLE :: 0x10000000 /* Force little endian-ness. */
ENDIAN_BIG :: 0x20000000 /* Force big endian-ness. */
ENDIAN_CPU :: 0x30000000 /* Force CPU endian-ness. */

FORMAT_SUBMASK :: 0x0000FFFF
FORMAT_TYPEMASK :: 0x0FFF0000
FORMAT_ENDMASK :: 0x30000000


sf_count_t :: i64

SF_INFO :: struct {
	frames:     sf_count_t,
	samplerate: u32,
	channels:   u32,
	format:     u32,
	sections:   u32,
	seekable:   u32,
}

SF_FORMAT_INFO :: struct {
	format:    i32,
	name:      cstring,
	extension: cstring,
}

SNDFILE :: struct {
}

Mode :: enum {
	READ  = 0x10,
	WRITE = 0x20,
	RDWR  = 0x30,
}

@(default_calling_convention = "c", link_prefix = "sf_")
foreign lib {
	open :: proc(path: cstring, mode: Mode, sfinfo: ^SF_INFO) -> ^SNDFILE ---
	close :: proc(sndfile: ^SNDFILE) -> i32 ---

	error :: proc(sndfile: ^SNDFILE) -> i32 ---
	error_number :: proc(errnum: i32) -> cstring ---
	strerror :: proc(sndfile: ^SNDFILE) -> cstring ---

	// Functions for reading and writing the data chunk in terms of frames.
	readf_short :: proc(sndfile: ^SNDFILE, ptr: ^i16, frames: sf_count_t) -> sf_count_t ---
	writef_short :: proc(sndfile: ^SNDFILE, ptr: ^i16, frames: sf_count_t) -> sf_count_t ---
	readf_int :: proc(sndfile: ^SNDFILE, ptr: ^i32, frames: sf_count_t) -> sf_count_t ---
	writef_int :: proc(sndfile: ^SNDFILE, ptr: ^i32, frames: sf_count_t) -> sf_count_t ---
	readf_float :: proc(sndfile: ^SNDFILE, ptr: ^f32, frames: sf_count_t) -> sf_count_t ---
	writef_float :: proc(sndfile: ^SNDFILE, ptr: ^f32, frames: sf_count_t) -> sf_count_t ---
	readf_double :: proc(sndfile: ^SNDFILE, ptr: ^f64, frames: sf_count_t) -> sf_count_t ---
	writef_double :: proc(sndfile: ^SNDFILE, ptr: ^f64, frames: sf_count_t) -> sf_count_t ---

	// Functions for reading and writing the data chunk in terms of items.
	read_short :: proc(sndfile: ^SNDFILE, ptr: ^i16, items: sf_count_t) -> sf_count_t ---
	write_short :: proc(sndfile: ^SNDFILE, ptr: ^i16, items: sf_count_t) -> sf_count_t ---
	read_int :: proc(sndfile: ^SNDFILE, ptr: ^i32, items: sf_count_t) -> sf_count_t ---
	write_int :: proc(sndfile: ^SNDFILE, ptr: ^i32, items: sf_count_t) -> sf_count_t ---
	read_float :: proc(sndfile: ^SNDFILE, ptr: ^f32, items: sf_count_t) -> sf_count_t ---
	write_float :: proc(sndfile: ^SNDFILE, ptr: ^f32, items: sf_count_t) -> sf_count_t ---
	read_double :: proc(sndfile: ^SNDFILE, ptr: ^f64, items: sf_count_t) -> sf_count_t ---
	write_double :: proc(sndfile: ^SNDFILE, ptr: ^f64, items: sf_count_t) -> sf_count_t ---

	write_sync :: proc(sndfile: ^SNDFILE) ---

	format_check :: proc(info: ^SF_INFO) -> i32 ---
}

readf :: proc {
	readf_short,
	readf_int,
	readf_float,
	readf_double,
}
writef :: proc {
	writef_short,
	writef_int,
	writef_float,
	writef_double,
}
read :: proc {
	read_short,
	read_int,
	read_float,
	read_double,
}
write :: proc {
	write_short,
	write_int,
	write_float,
	write_double,
}

# Odin + JACK code examples

This is a port of some example clients from [JACK example
clients](https://github.com/jackaudio/jack-example-tools/tree/main/example-clients)
to [Odin](https://odin-lang.org).

## How to run

First, install the JACK development libraries.
In Ubuntu, you can do this by: `sudo apt install libjack-jackd2-dev`.

You need to be running either JACK or Pipewire. You're quite possibly already
running Pipewire, as it's enabled by default in many major Linux distributions.

To build a program, run `make` followed by the program name -- e.g. `make simple_client`.

Once it's compiled, just run the binary created for it -- e.g. `./simple_client`.

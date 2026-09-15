#!/usr/bin/env python3
"""Generate the plugin's .wav files from scratch. Pure stdlib.

Run:  python3 scripts/gen-sounds.py [name ...]
Writes into ../sounds/ relative to this file. With names, only those.

Everything here is synthesized, so it's all yours to redistribute. Swap any
file for a real recording and the plugin picks it up by filename.
"""

import math
import os
import random
import struct
import wave

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, os.pardir, "sounds")


def write(name, samples):
    path = os.path.join(OUT, name + ".wav")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 0.85 / peak if peak > 0.85 else 1.0
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767))
            for s in samples
        ))
    print("wrote", os.path.relpath(path, HERE), "%.1fs" % (len(samples) / SR))


def tone(freq, dur, amp=1.0, partials=(1.0, 0.3, 0.12), attack=0.02, decay=None):
    """A soft bell-ish tone. Partials give it body without sounding like a beep."""
    n = int(SR * dur)
    decay = decay if decay is not None else dur
    out = []
    for i in range(n):
        t = i / SR
        env = min(1.0, t / attack) * math.exp(-3.0 * t / decay)
        v = sum(p * math.sin(2 * math.pi * freq * (k + 1) * t)
                for k, p in enumerate(partials))
        out.append(amp * env * v / sum(partials))
    return out


def silence(dur):
    return [0.0] * int(SR * dur)


def seq(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


# --- one-shot cues ----------------------------------------------------------
# Each is deliberately a different *shape*, not just a different pitch. You
# should be able to tell them apart from the next room without listening.

def cue_done():
    # Rising two-note resolve.
    return seq(tone(587.33, 0.16, 0.7, decay=0.2),
               tone(880.00, 0.55, 0.7, decay=0.5))


def cue_failed():
    # Falling minor third, slower, duller.
    return seq(tone(392.00, 0.20, 0.7, partials=(1.0, 0.5, 0.25), decay=0.25),
               tone(311.13, 0.70, 0.7, partials=(1.0, 0.5, 0.25), decay=0.7))


def cue_needs_you():
    # Two quick identical blips — reads as a knock, not as completion.
    b = tone(740.0, 0.09, 0.8, decay=0.09)
    return seq(b, silence(0.07), b, silence(0.2))


def cue_look_away():
    # Gentle rise: go long.
    return seq(tone(523.25, 0.22, 0.55, decay=0.3),
               tone(659.25, 0.22, 0.55, decay=0.3),
               tone(783.99, 0.65, 0.55, decay=0.6))


def cue_come_back():
    # Same notes, reversed. Unmistakably the other end of the pair.
    return seq(tone(783.99, 0.22, 0.5, decay=0.3),
               tone(659.25, 0.22, 0.5, decay=0.3),
               tone(523.25, 0.6, 0.5, decay=0.55))


# --- loops ------------------------------------------------------------------

def place(buf, samples, at):
    """Mix samples into buf starting at `at` seconds, wrapping past the end.
    A tail that runs over the loop point lands at the start, so decaying
    sounds loop without a cut or a click."""
    n = len(buf)
    start = int(at * SR)
    for j, v in enumerate(samples):
        buf[(start + j) % n] += v


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def bowl(freq, amp, bright=1.0, dur=20.0):
    """A struck singing bowl. Few, widely spaced modes, each split into a
    close pair by the bowl's imperfect symmetry — that split is the slow
    wobble. A felt-mallet 'tok' on top."""
    # (frequency ratio, level, decay seconds, wobble Hz)
    modes = [(1.00, 1.00, 7.0, 1.3), (2.76, 0.50 * bright, 3.5, 2.1),
             (5.40, 0.26 * bright, 1.8, 3.2), (8.93, 0.12 * bright, 0.9, 4.4)]
    n = int(SR * dur)
    out = [0.0] * n
    for ratio, level, tau, wobble in modes:
        f = freq * ratio
        for i in range(n):
            t = i / SR
            env = min(1.0, t / 0.004) * math.exp(-t / tau)
            out[i] += level * env * (math.sin(2 * math.pi * f * t)
                                     + 0.6 * math.sin(2 * math.pi * (f + wobble) * t))
    rng = random.Random(3)
    lp = 0.0
    for i in range(int(SR * 0.06)):
        lp += 0.15 * (rng.uniform(-1, 1) - lp)
        out[i] += 0.35 * bright * lp * math.exp(-i / (SR * 0.012))
    return [amp * v / 3.0 for v in out]


def loop_breathing():
    """10s cycle: 4s in, 6s out, marked by singing bowls. A higher bowl says
    breathe in, a lower, softer one says breathe out. Their tails wrap into
    the next cycle the way a real bowl keeps ringing under the next strike."""
    buf = [0.0] * (SR * 10)
    place(buf, bowl(hz(62), 0.55), 0.0)              # D4, in
    place(buf, bowl(hz(57), 0.42, bright=0.6), 4.0)  # A3, out
    return buf


def thump(f_hi, f_lo, dur, amp):
    """A pitch-dropping body thump. Harmonics keep it audible on laptop
    speakers, which can't reproduce the fundamental."""
    n = int(SR * dur)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = f_lo + (f_hi - f_lo) * math.exp(-t / 0.03)
        ph += 2 * math.pi * f / SR
        env = min(1.0, t / 0.004) * math.exp(-t / (dur / 4))
        out.append(amp * env * (math.sin(ph) + 0.5 * math.sin(2 * ph)
                                + 0.25 * math.sin(3 * ph)) / 1.75)
    return out


def loop_heartbeat():
    """Lub-dub at 60 bpm, ten beats. Present without being music."""
    buf = [0.0] * (SR * 10)
    lub = thump(150.0, 60.0, 0.16, 0.9)
    dub = thump(180.0, 75.0, 0.12, 0.6)
    for beat in range(10):
        place(buf, lub, beat)
        place(buf, dub, beat + 0.28)
    return buf


def pad_note(freq, dur, amp):
    """Slow-swelling, gently chorused sustain."""
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        env = min(1.0, t / 1.2) * min(1.0, (dur - t) / 1.5)
        out.append(amp * env * (math.sin(2 * math.pi * freq * t)
                                + math.sin(2 * math.pi * freq * 1.003 * t)
                                + 0.15 * math.sin(4 * math.pi * freq * t)) / 2.15)
    return out


# The hold-music composition, shared by ambient/hold-music and 8-bit/town: eight 6s
# bars ending on a suspended chord that leans back into the first, so it never
# resolves. (bass root, chord tones) as MIDI notes.
HOLD_BARS = [(41, [53, 57, 60, 64]),      # Fmaj7
             (40, [52, 55, 59, 62]),      # Em7
             (38, [50, 53, 57, 60, 64]),  # Dm9
             (36, [48, 52, 55, 59]),      # Cmaj7
             (41, [53, 57, 60, 64]),      # Fmaj7
             (45, [57, 60, 64, 67]),      # Am7
             (38, [50, 53, 57, 60, 64]),  # Dm9
             (43, [55, 60, 62, 69])]      # Gsus4 add9
HOLD_BAR, HOLD_STEP, HOLD_SEED = 6.0, 0.5, 11


def arpeggio(bars, bar, step, seed, rest=0.25):
    """Yields (seconds into the loop, MIDI note): chord tones an octave up,
    picked at random on each step, never the same note twice running.
    Seeded, so every rendering of a song plays the same notes."""
    rng = random.Random(seed)
    for b, (_, chord) in enumerate(bars):
        prev = None
        for s in range(round(bar / step)):
            if rng.random() < rest:
                continue  # rests keep the pattern from sounding mechanical
            m = rng.choice([c + 12 for c in chord if c + 12 != prev])
            prev = m
            yield b * bar + s * step, m


def ambient(bars, bar, step, seed, rest=0.25):
    """A song on soft voices: pad, bass and a vibraphone-ish arpeggio."""
    buf = [0.0] * int(SR * bar * len(bars))
    for b, (root, chord) in enumerate(bars):
        at = b * bar
        place(buf, tone(hz(root), bar - 0.5, 0.35, partials=(1.0, 0.5, 0.25),
                        attack=0.03, decay=4.0), at)
        for m in chord:
            place(buf, pad_note(hz(m), bar + 1.5, 0.07), at)
    for at, m in arpeggio(bars, bar, step, seed, rest):
        place(buf, tone(hz(m), 1.8, 0.3, partials=(1.0, 0.45, 0.2, 0.08),
                        attack=0.012, decay=0.9), at)
    return buf


# --- 8-bit voices -----------------------------------------------------------
# NES-style channels: pulse waves and a stepped triangle. Waveforms are naive
# (aliased) and volumes are 4-bit on purpose — the console's were too.

def nes_pulse(freq, dur, amp, duty=0.5, decay=None, vibrato=False,
              attack=0.0, release=0.03):
    n = int(SR * dur)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = freq
        if vibrato and t > 0.25:
            f *= 1 + 0.004 * math.sin(2 * math.pi * 5.5 * t)
        ph = (ph + f / SR) % 1.0
        env = math.exp(-t / decay) if decay else 0.75 + 0.25 * math.exp(-t / 0.08)
        env *= min(1.0, t / attack if attack else 1.0, (dur - t) / release)
        env = round(env * 15) / 15
        out.append(amp * env * ((1.0 if ph < duty else 0.0) - duty))
    return out


def nes_triangle(freq, dur, amp):
    n = int(SR * dur)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        ph = (ph + freq / SR) % 1.0
        tri = round((4 * abs(ph - 0.5)) * 15) / 15 * 2 - 1  # 16 steps
        gate = min(1.0, t / 0.003, (dur - t) / 0.003)
        out.append(amp * gate * tri)
    return out


def chiptune(bars, bar, step, seed, rest=0.25, duty=0.5):
    """A song on 8-bit voices: triangle bass, thin pulse pad swelling in 4-bit
    steps, pulse arpeggio with a quiet copy half a step later — the echo NES
    composers faked with a spare channel."""
    buf = [0.0] * int(SR * bar * len(bars))
    for b, (root, chord) in enumerate(bars):
        at = b * bar
        place(buf, nes_triangle(hz(root + 12), bar * 0.95, 0.4), at)
        for m in chord:
            place(buf, nes_pulse(hz(m), bar + 1.5, 0.05, duty=0.25,
                                 vibrato=True, attack=1.2, release=1.5), at)
    for at, m in arpeggio(bars, bar, step, seed, rest):
        for delay, level in ((0.0, 0.3), (step / 2, 0.09)):
            place(buf, nes_pulse(hz(m), 1.8, level, duty=duty, decay=0.35), at + delay)

    # Output filtering like the console's: take the edge off the top, drop DC.
    # Run twice over so the filter state at the loop point matches.
    lp = hp_in = hp_out = 0.0
    out = []
    for x in buf + buf:
        lp += 0.6 * (x - lp)
        hp_out = 0.995 * (hp_out + lp - hp_in)
        hp_in = lp
        out.append(hp_out)
    # Pulse waves are dense; this brings it level with the other loops.
    return [0.3 * v for v in out[len(buf):]]


# More songs. Same shape as HOLD_BARS: eight bars of (bass root, chord tones),
# the last one suspended so the loop never resolves.

# -- for chiptune() --

HARBOR = [(38, [50, 53, 57, 60, 64]),  # Dm9
          (34, [46, 50, 53, 57]),      # Bbmaj7
          (41, [53, 57, 60, 64]),      # Fmaj7
          (36, [48, 52, 55, 57]),      # C6
          (38, [50, 53, 57, 60, 64]),  # Dm9
          (43, [55, 58, 62, 65]),      # Gm7
          (34, [46, 50, 53, 57]),      # Bbmaj7
          (45, [57, 62, 64, 67])]      # A7sus4

SNOWFIELD = [(40, [52, 55, 59, 66]),      # Em add9
             (36, [48, 52, 55, 59]),      # Cmaj7
             (43, [55, 59, 62, 66]),      # Gmaj7
             (45, [57, 60, 64, 67]),      # Am7
             (40, [52, 55, 59, 66]),      # Em add9
             (36, [48, 52, 55, 59]),      # Cmaj7
             (45, [57, 60, 64, 67, 71]),  # Am9
             (47, [59, 64, 66, 69])]      # B7sus4

RUINS = [(45, [45, 48, 52, 55, 59]),  # Am9
         (41, [53, 57, 60, 64]),      # Fmaj7
         (38, [50, 53, 57, 60, 64]),  # Dm9
         (40, [52, 56, 59, 62]),      # E7
         (45, [45, 48, 52, 55, 59]),  # Am9
         (41, [53, 57, 60, 64]),      # Fmaj7
         (47, [47, 50, 53, 57]),      # Bm7b5
         (40, [52, 57, 59, 64])]      # Esus4

# -- for ambient() --
# Keys and moves the 8-bit songs don't use: flat keys, a borrowed minor iv,
# a bIII, and a slower step for drift.

DUSK = [(39, [51, 55, 58, 62]),      # Ebmaj7
        (38, [50, 53, 57, 60]),      # Dm7
        (36, [48, 51, 55, 58, 62]),  # Cm9
        (34, [46, 50, 53, 57]),      # Bbmaj7
        (39, [51, 55, 58, 62]),      # Ebmaj7
        (43, [55, 58, 62, 65, 69]),  # Gm9
        (36, [48, 51, 55, 58, 62]),  # Cm9
        (38, [50, 55, 57, 60])]      # D7sus4

LANTERN = [(45, [57, 61, 64, 68, 71]),  # Amaj9
           (36, [48, 52, 55, 59]),      # Cmaj7
           (38, [50, 54, 57, 61]),      # Dmaj7
           (38, [50, 53, 57, 59]),      # Dm6
           (45, [57, 61, 64, 68, 71]),  # Amaj9
           (42, [54, 57, 61, 64, 68]),  # F#m9
           (38, [50, 54, 57, 61]),      # Dmaj7
           (40, [52, 57, 59, 66])]      # Esus4 add9

DRIFT = [(47, [47, 50, 54, 61]),      # Bm add9
         (43, [55, 59, 62, 66]),      # Gmaj7
         (40, [52, 55, 59, 62, 66]),  # Em9
         (42, [54, 57, 61, 64]),      # F#m7
         (47, [47, 50, 54, 61]),      # Bm add9
         (38, [50, 54, 57, 61]),      # Dmaj7
         (43, [55, 59, 62, 66]),      # Gmaj7
         (42, [54, 59, 61, 64])]      # F#7sus4


# Keys are paths under sounds/, so each category is a folder.
SOUNDS = {
    "done": cue_done,
    "failed": cue_failed,
    "needs-you": cue_needs_you,
    "look-away": cue_look_away,
    "come-back": cue_come_back,
    "breathing": loop_breathing,
    "heartbeat": loop_heartbeat,
    "ambient/hold-music": lambda: ambient(HOLD_BARS, HOLD_BAR, HOLD_STEP, HOLD_SEED),
    "ambient/dusk": lambda: ambient(DUSK, 8.0, 0.5, seed=31, rest=0.3),
    "ambient/lantern": lambda: ambient(LANTERN, 6.0, 0.5, seed=17, rest=0.2),
    "ambient/drift": lambda: ambient(DRIFT, 6.0, 0.75, seed=59, rest=0.3),
    "8-bit/town": lambda: chiptune(HOLD_BARS, HOLD_BAR, HOLD_STEP, HOLD_SEED),
    "8-bit/harbor": lambda: chiptune(HARBOR, 7.2, 0.6, seed=23),
    "8-bit/snowfield": lambda: chiptune(SNOWFIELD, 6.0, 0.5, seed=5, rest=0.4, duty=0.25),
    "8-bit/ruins": lambda: chiptune(RUINS, 6.0, 0.5, seed=41, rest=0.12),
}
# sounds/soundscapes/ holds recordings, not generated here.


if __name__ == "__main__":
    import sys
    # Name sounds to regenerate only those, so a file you replaced by hand
    # isn't overwritten. No arguments regenerates everything.
    for name in sys.argv[1:] or SOUNDS:
        write(name, SOUNDS[name]())

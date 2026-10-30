#!/usr/bin/env python3
"""Syntetiserar spelets egna ljud, så att inga licensfrågor uppstår:

  assets/audio/engine_loop.ogg  – motorljud, 2 s sömlös slinga (tonhöjden ändras i spelet)
  assets/audio/music_loop.ogg   – bakgrundsmusik, cirka 69 s sömlös slinga (112 BPM, a-moll)

Filerna laddas upp på create.roblox.com (Creations → Audio), och ljud-ID:na skrivs in i
src/shared/Config/SoundConfig.luau.

Användning: python3 tools/audio/make_audio.py   (kräver numpy, scipy och ffmpeg)
"""

from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

import numpy as np
from scipy import signal
from scipy.io import wavfile

ROOT = Path(__file__).resolve().parent.parent.parent
OUT = ROOT / "assets" / "audio"
RATE = 44100
rng = np.random.default_rng(1307)


def periodic_noise(n: int) -> np.ndarray:
    """Brus som går runt sömlöst (slumpad fas i frekvensplanet)."""
    spectrum = np.exp(1j * rng.uniform(0, 2 * np.pi, n // 2 + 1))
    spectrum[0] = 0
    noise = np.fft.irfft(spectrum, n)
    return noise / np.max(np.abs(noise))


def lowpass(x: np.ndarray, cutoff: float, order: int = 4) -> np.ndarray:
    sos = signal.butter(order, cutoff, "low", fs=RATE, output="sos")
    return signal.sosfiltfilt(sos, x)


def highpass(x: np.ndarray, cutoff: float, order: int = 4) -> np.ndarray:
    sos = signal.butter(order, cutoff, "high", fs=RATE, output="sos")
    return signal.sosfiltfilt(sos, x)


def save(name: str, audio: np.ndarray) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    audio = audio / np.max(np.abs(audio)) * 0.89
    if audio.ndim == 1:
        audio = np.stack([audio, audio], axis=1)
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "out.wav"
        wavfile.write(wav, RATE, (audio * 32767).astype(np.int16))
        target = OUT / name
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "6", str(target)],
            check=True,
        )
    print(f"Skrev {target.relative_to(ROOT)} ({target.stat().st_size // 1024} kB)")


# ---------------------------------------------------------------- motor


def engine() -> np.ndarray:
    """Fyrcylindrig motor på tomgång/låga varv. Allt är periodiskt på 2 s, så slingan är sömlös."""
    seconds = 2.0
    n = int(RATE * seconds)
    t = np.arange(n) / RATE
    fire = 50.0  # tändningar per sekund (100 st på 2 s)
    out = np.zeros(n)
    # Övertoner av tändfrekvensen, med en lätt "hackig" ton från halva frekvensen
    for k, amp in [(0.5, 0.35), (1, 1.0), (2, 0.55), (3, 0.35), (4, 0.22), (5, 0.12), (6, 0.08), (8, 0.04)]:
        phase = rng.uniform(0, 2 * np.pi)
        out += amp * np.sin(2 * np.pi * fire * k * t + phase)
    # Tändpulser: kort smäll vid varje tändning ger motorns knatter
    period = RATE / fire
    pulse_pos = (np.arange(n) % period) / period
    pulses = np.exp(-pulse_pos * 9.0)
    out = out * (0.65 + 0.35 * pulses)
    # Avgasbrus som följer pulserna
    noise = lowpass(periodic_noise(n), 900)
    out += 0.35 * noise * pulses
    out = np.tanh(out * 1.4)  # lite mättnad
    return lowpass(out, 2400)


# ---------------------------------------------------------------- musik

BPM = 112
BEAT = 60 / BPM
BAR = BEAT * 4
BARS = 32


def note_freq(name: str) -> float:
    names = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((names[pitch] + (octave - 4) * 12) / 12)


def envelope(n: int, attack: float, decay: float) -> np.ndarray:
    t = np.arange(n) / RATE
    env = np.minimum(t / max(attack, 1e-4), 1.0) * np.exp(-t / decay)
    fade = min(n, int(0.01 * RATE))
    env[-fade:] *= np.linspace(1, 0, fade)
    return env


def saw(freq: float, n: int, detune: float = 0.0) -> np.ndarray:
    t = np.arange(n) / RATE
    wave = np.zeros(n)
    for d in (-detune, 0.0, detune):
        f = freq * 2 ** (d / 1200)
        wave += signal.sawtooth(2 * np.pi * f * t + rng.uniform(0, 6.28))
    return wave / 3


def add(track: np.ndarray, sound: np.ndarray, start: float) -> None:
    i = int(start * RATE) % len(track)
    end = i + len(sound)
    if end <= len(track):
        track[i:end] += sound
    else:  # svansen går runt till början, så att slingan blir sömlös
        first = len(track) - i
        track[i:] += sound[:first]
        track[: len(sound) - first] += sound[first:]


CHORDS = [  # a-moll, F-dur, C-dur, G-dur (i–VI–III–VII)
    ["A3", "C4", "E4"],
    ["F3", "A3", "C4"],
    ["C4", "E4", "G4"],
    ["G3", "B3", "D4"],
]
BASS = ["A1", "F1", "C2", "G1"]
# Melodi för refrängen: (takt-offset i slag, ton, längd i slag), fyra takter som upprepas
MELODY = [
    (0, "E5", 1.5), (1.5, "D5", 0.5), (2, "C5", 1), (3, "A4", 1),
    (4, "C5", 1.5), (5.5, "D5", 0.5), (6, "E5", 1), (7, "G5", 1),
    (8, "E5", 1.5), (9.5, "D5", 0.5), (10, "C5", 1), (11, "E5", 1),
    (12, "D5", 2), (14, "B4", 1), (15, "D5", 1),
]


def music() -> np.ndarray:
    n = int(BAR * BARS * RATE)
    drums = np.zeros(n)
    bass = np.zeros(n)
    pads = np.zeros(n)
    arp = np.zeros(n)
    lead = np.zeros(n)

    # Trummor
    kick_n = int(0.35 * RATE)
    kt = np.arange(kick_n) / RATE
    kick = np.sin(2 * np.pi * (45 + 90 * np.exp(-kt * 30)) * kt) * np.exp(-kt * 9)
    snare_n = int(0.25 * RATE)
    snare = highpass(rng.standard_normal(snare_n), 1500) * envelope(snare_n, 0.001, 0.07) * 0.3
    snare += np.sin(2 * np.pi * 190 * np.arange(snare_n) / RATE) * envelope(snare_n, 0.001, 0.05) * 0.4
    hat_n = int(0.08 * RATE)
    hat = highpass(rng.standard_normal(hat_n), 7000) * envelope(hat_n, 0.001, 0.02) * 0.1

    for bar in range(BARS):
        section = bar // 8  # 0 intro, 1 vers, 2 refräng, 3 refräng
        start = bar * BAR
        chord = CHORDS[bar % 4]
        for beat in range(4):
            if section > 0 or beat in (0, 2):
                add(drums, kick, start + beat * BEAT)
            if section > 0 and beat in (1, 3):
                add(drums, snare, start + beat * BEAT)
        for eighth in range(8):
            add(drums, hat * (1.0 if eighth % 2 else 0.6), start + eighth * BEAT / 2)

        # Bas: åttondelar med oktavhopp
        bass_len = int(BEAT / 2 * RATE)
        for eighth in range(8):
            freq = note_freq(BASS[bar % 4]) * (2 if eighth % 2 else 1)
            tone = lowpass(saw(freq, bass_len, 6), 600) * envelope(bass_len, 0.005, 0.18)
            add(bass, tone, start + eighth * BEAT / 2)

        # Pad: mjuka ackord över hela takten
        pad_len = int(BAR * RATE)
        chord_sound = sum(saw(note_freq(note), pad_len, 12) for note in chord)
        pad_env = np.minimum(np.arange(pad_len) / (0.25 * RATE), 1) * np.minimum((pad_len - np.arange(pad_len)) / (0.2 * RATE), 1)
        add(pads, lowpass(chord_sound, 1400) * pad_env * 0.5, start)

        # Arpeggio i sextondelar från vers och framåt
        if section >= 1:
            arp_len = int(BEAT / 4 * RATE)
            root_up = chord[0][:-1] + str(int(chord[0][-1]) + 1)  # grundtonen en oktav upp
            notes = chord + [root_up]
            for step in range(16):
                freq = note_freq(notes[step % len(notes)]) * 2
                tone = signal.square(2 * np.pi * freq * np.arange(arp_len) / RATE, 0.3)
                add(arp, lowpass(tone, 3000) * envelope(arp_len, 0.002, 0.06) * 0.35, start + step * BEAT / 4)

        # Melodi i refrängen
        if section >= 2:
            phrase_start = (bar % 4) * 4
            for offset, note, length in MELODY:
                if phrase_start <= offset < phrase_start + 4:
                    tone_len = int(length * BEAT * RATE)
                    freq = note_freq(note)
                    t = np.arange(tone_len) / RATE
                    vibrato = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * t)
                    wave = signal.sawtooth(2 * np.pi * freq * np.cumsum(vibrato) / RATE, 0.5)
                    wave += 0.5 * np.sin(2 * np.pi * freq * 2 * t)
                    env = envelope(tone_len, 0.01, 0.6)
                    add(lead, lowpass(wave, 2600) * env * 0.4, start + (offset - phrase_start) * BEAT)

    # Enkelt eko på melodi och arpeggio (går runt i slingan)
    def echo(track: np.ndarray, delay: float, feedback: float) -> np.ndarray:
        out = track.copy()
        shift = int(delay * RATE)
        for k in range(1, 4):
            out += np.roll(track, shift * k) * feedback**k
        return out

    left = drums * 0.9 + bass * 0.8 + pads * 0.45 + echo(arp, BEAT * 0.75, 0.35) * 0.6 + echo(lead, BEAT * 0.5, 0.3) * 0.75
    right = drums * 0.9 + bass * 0.8 + pads * 0.45 + echo(arp, BEAT * 0.5, 0.35) * 0.6 + echo(lead, BEAT * 0.75, 0.3) * 0.75
    mix = np.stack([left, right], axis=1)
    return np.tanh(mix * 0.8 / np.max(np.abs(mix)) * 1.6)


if __name__ == "__main__":
    save("engine_loop.ogg", engine())
    save("music_loop.ogg", music())

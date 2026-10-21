#!/usr/bin/env python3
"""Procedural sound-effect generator for 小镇周报.

Every sound in assets/audio/sfx/ is synthesized here from noise, impulses,
damped modes and resonant filters -- no recorded samples are used, so the
project owns the output outright.

Usage (from the project root):
    python scripts/tools/gen_sfx.py            # generate all
    python scripts/tools/gen_sfx.py stamp lever  # generate only these

Output: 44.1 kHz, mono, 16-bit PCM WAV. Output is reproducible: every sound
uses its own random generator seeded from a fixed project seed + its name,
so tweaking one sound never changes another.
"""
import os
import sys
import zlib

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
SEED = 1935
OUT_DIR = os.path.join("assets", "audio", "sfx")


# ----------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------

def rng_for(name):
    return np.random.default_rng([SEED, zlib.crc32(name.encode("utf-8"))])


def n_of(dur):
    return int(round(dur * SR))


def T(dur):
    return np.arange(n_of(dur)) / SR


def _sos(kind, f, order):
    return signal.butter(order, f, btype=kind, fs=SR, output="sos")


def lp(x, f, order=2):
    return signal.sosfilt(_sos("lowpass", f, order), x)


def hp(x, f, order=2):
    return signal.sosfilt(_sos("highpass", f, order), x)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(_sos("bandpass", [lo, hi], order), x)


def reson(x, f, q):
    """Resonant band-pass (2-pole) at f with quality q, unity peak gain."""
    b, a = signal.iirpeak(f, q, fs=SR)
    return signal.lfilter(b, a, x)


def circ(x, fn):
    """Apply a (fast-decaying) filter to a periodic signal without a seam."""
    n = len(x)
    return fn(np.concatenate([x, x]))[n:]


def expenv(dur, tau, attack=0.0):
    t = T(dur)
    e = np.exp(-t / tau)
    if attack > 0:
        e *= 1.0 - np.exp(-t / attack)
    return e


def burst(r, dur, tau, attack=0.0):
    """Exponentially decaying white-noise burst."""
    return r.standard_normal(n_of(dur)) * expenv(dur, tau, attack)


def modes(r, dur, freqs, decays, amps, detune=0.0, attack=0.0003):
    """Sum of exponentially damped sinusoids (modal impulse response)."""
    t = T(dur)
    y = np.zeros_like(t)
    for f, d, a in zip(freqs, decays, amps):
        f = f * (1.0 + detune * r.uniform(-1, 1))
        if f >= SR / 2 - 500:
            continue
        y += a * np.exp(-t / d) * np.sin(2 * np.pi * f * t + r.uniform(0, 2 * np.pi))
    if attack > 0:
        y *= 1.0 - np.exp(-t / attack)
    return y


def mix(*xs):
    """Sum arrays of differing lengths (shorter ones are zero-padded)."""
    n = max(len(x) for x in xs)
    y = np.zeros(n)
    for x in xs:
        y[: len(x)] += x
    return y


def place(buf, x, t, gain=1.0):
    """Mix x into buf starting at time t (seconds); truncates at the end."""
    i = n_of(t)
    if i >= len(buf):
        return
    j = min(len(buf), i + len(x))
    buf[i:j] += gain * x[: j - i]


def place_circ(buf, x, t, gain=1.0):
    """Mix x into buf at time t, wrapping around (for seamless loops)."""
    n = len(buf)
    idx = (n_of(t) + np.arange(len(x))) % n
    np.add.at(buf, idx, gain * x)


def small_room(r, x, length=0.25, mix=0.12, lp_hz=5000):
    """Cheap diffuse room: convolve with decaying, filtered noise."""
    ir = lp(burst(r, length, length / 5.0), lp_hz)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
    wet = signal.fftconvolve(x, ir)[: len(x)]
    return x + mix * wet * (np.max(np.abs(x)) / (np.max(np.abs(wet)) + 1e-12))


def fades(x, fin=0.0003, fout=0.01):
    x = x.copy()
    a, b = n_of(fin), n_of(fout)
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)
    if b > 0:
        x[-b:] *= np.linspace(1, 0, b) ** 2
    return x


def normalize(x, dbfs):
    pk = np.max(np.abs(x))
    return x * (10 ** (dbfs / 20.0) / pk) if pk > 0 else x


def loop_crossfade(y, L, C):
    """y has length L+C; returns length-L buffer whose end flows into its start."""
    out = y[:L].copy()
    w = np.linspace(0, 1, C) * np.pi / 2
    out[:C] = y[:C] * np.sin(w) + y[L:L + C] * np.cos(w)
    return out


def finish(x, dbfs, fin=0.0003, fout=0.01, top=14000):
    x = hp(x, 25)
    if top:
        x = lp(x, top, 1)
    x = fades(x, fin, fout)
    return normalize(x, dbfs)


def bell_partials(r, dur, f0, ratios, decays, amps, beat=0.0025):
    """Small bell: inharmonic partials, each split into a slightly detuned doublet."""
    y = np.zeros(n_of(dur))
    for k, (ra, d, a) in enumerate(zip(ratios, decays, amps)):
        f = f0 * ra
        y += modes(r, dur, [f, f * (1 + beat / (k + 1))], [d, d * 0.9], [a, a * 0.6])
    return y


# ----------------------------------------------------------------------------
# sounds
# ----------------------------------------------------------------------------

def typewriter_key(r):
    d = 0.12
    y = np.zeros(n_of(d))
    # type slug hits platen: very sharp, bright click
    click = hp(burst(r, 0.006, 0.0007), 2500, 2)
    # steel type bar ringing briefly
    metal = modes(r, 0.09, [1830, 2710, 3930, 5240, 6900],
                  [0.030, 0.022, 0.015, 0.010, 0.006],
                  [0.35, 0.30, 0.25, 0.18, 0.10], detune=0.02)
    # body / platen thunk
    thunk = mix(lp(burst(r, 0.04, 0.007), 900) * 0.9, modes(
        r, 0.07, [150, 290, 470, 760], [0.022, 0.016, 0.011, 0.008],
        [0.9, 0.55, 0.35, 0.2], detune=0.03))
    place(y, click, 0.002, 1.0)
    place(y, metal, 0.002, 0.8)
    place(y, thunk, 0.003, 0.9)
    # key returning / escapement step a moment later
    esc = mix(hp(burst(r, 0.004, 0.0006), 3000) * 0.35, modes(
        r, 0.03, [2400, 3600], [0.006, 0.004], [0.12, 0.08]))
    place(y, esc, 0.052)
    place(y, lp(burst(r, 0.02, 0.004), 600) * 0.2, 0.053)
    return finish(y, -3, fout=0.015)


def typewriter_bell(r):
    d = 0.6
    y = np.zeros(n_of(d))
    bell = bell_partials(r, d, 2260, [1.0, 2.63, 4.95, 7.4],
                         [0.42, 0.16, 0.07, 0.035], [1.0, 0.45, 0.22, 0.1])
    strike = hp(burst(r, 0.004, 0.0006), 3000) * 0.5
    place(y, bell, 0.003)
    place(y, strike, 0.002)
    # little rattle of the striker arm
    place(y, modes(r, 0.03, [900, 1500], [0.008, 0.005], [0.08, 0.05]), 0.004)
    return finish(y, -3, fout=0.08)


def _crinkle(r, dur, density_env, n_grains, hp_hz=2500, amp=1.0):
    """Sparse paper crackle: many tiny noise grains, density following env."""
    y = np.zeros(n_of(dur))
    p = density_env / density_env.sum()
    idx = r.choice(len(density_env), size=n_grains, p=p)
    for i in idx:
        g = burst(r, 0.003, r.uniform(0.0002, 0.0012)) * r.lognormal(0, 0.6)
        j = min(len(y), i + len(g))
        y[i:j] += g[: j - i]
    return lp(hp(y, hp_hz), 8500) * amp


def page_turn(r):
    d = 0.4
    t = T(d)
    # overall motion envelope: lift, swish, settle
    env = np.clip(t / 0.10, 0, 1) ** 1.5 * np.exp(-np.clip(t - 0.17, 0, None) / 0.06)
    nse = r.standard_normal(len(t))
    low = bp(nse, 250, 1400) * env * 0.9
    hi_env = np.clip(t / 0.06, 0, 1) * np.exp(-np.clip(t - 0.10, 0, None) / 0.07)
    high = bp(r.standard_normal(len(t)), 1800, 7000) * hi_env * 0.45
    swish = low + high
    # paper crinkle mostly at the grab and the turn
    cr_env = np.exp(-((t - 0.05) / 0.04) ** 2) + 0.6 * np.exp(-((t - 0.18) / 0.06) ** 2) + 0.02
    crink = _crinkle(r, d, cr_env, 220, 1800, 0.45)
    y = swish + crink
    # page lands: soft flap
    flap = mix(lp(burst(r, 0.04, 0.008), 350) * 0.6, bp(burst(r, 0.03, 0.004), 700, 4500) * 0.5)
    place(y, flap, 0.295)
    y = lp(y, 9000)
    return finish(y, -3, fin=0.003, fout=0.04)


def paper_slide(r):
    d = 0.35
    t = T(d)
    env = np.clip(t / 0.035, 0, 1) * np.clip((0.33 - t) / 0.12, 0, 1) ** 1.3
    # stick-slip roughness: slow random amplitude wobble
    rough = 1.0 + 0.35 * lp(r.standard_normal(len(t)), 70) / 0.12
    rough = np.clip(rough, 0.3, 1.8)
    nse = r.standard_normal(len(t))
    # the sheet's centre of brightness sinks as it slows down
    bright = bp(nse, 1500, 7500) * np.clip(1.1 - t / 0.33, 0.2, 1)
    mid = bp(nse, 350, 1800)
    fr = (0.55 * bright + 0.8 * mid) * env * rough
    # desk wood picks a little of it up
    wood = reson(fr, 230, 6) * 0.9 + reson(fr, 520, 8) * 0.5
    y = fr + wood
    # fingertips landing on the sheet
    place(y, lp(burst(r, 0.03, 0.006), 500) * 0.25, 0.0)
    place(y, _crinkle(r, 0.05, np.ones(n_of(0.05)), 10, 2500, 0.6), 0.0)
    return finish(y, -3, fin=0.002, fout=0.03)


def mail_slot(r):
    d = 0.9
    y = np.zeros(n_of(d))
    # 1. spring-loaded brass flap squeaks open (stick-slip on the hinge)
    sq_d = 0.17
    ts = T(sq_d)
    f = 950 + 350 * np.sin(np.pi * ts / sq_d) + 25 * lp(r.standard_normal(len(ts)), 40) / 0.1
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = sum(np.sin(k * ph) / k ** 1.2 for k in range(1, 7))
    sq_env = np.sin(np.pi * ts / sq_d) ** 2 * (0.75 + 0.25 * np.sign(np.sin(2 * np.pi * 38 * ts)))
    squeak = bp(tone * sq_env, 700, 5000) * 0.4
    place(y, squeak, 0.01)
    # 2. letters scraping through the slot
    st = T(0.28)
    env = np.sin(np.pi * st / 0.28) ** 1.5
    scrape = bp(r.standard_normal(len(st)), 600, 5000) * env * 0.4
    scrape += _crinkle(r, 0.28, env + 0.05, 70, 1800, 0.35)
    place(y, scrape, 0.12)
    # 3. flap snaps shut: brass clack + small bounce
    def clack(amp):
        c = hp(burst(r, 0.005, 0.0008), 1500) * 0.9
        c = np.pad(c, (0, n_of(0.25) - len(c)))
        c += modes(r, 0.25, [1120, 2610, 3480, 4310, 5920],
                   [0.11, 0.07, 0.05, 0.035, 0.02],
                   [0.5, 0.45, 0.3, 0.25, 0.15], detune=0.01)
        c += lp(burst(r, 0.25, 0.012), 700) * 0.6
        c += modes(r, 0.25, [180, 340], [0.03, 0.02], [0.4, 0.25])  # door panel
        return c * amp
    place(y, clack(1.0), 0.43)
    place(y, clack(0.28), 0.475)
    # 4. letters land on the floor: soft papery slap + low thud
    drop = mix(lp(burst(r, 0.06, 0.012), 300) * 0.55,
               bp(burst(r, 0.05, 0.007), 800, 5000) * 0.35)
    place(y, drop, 0.64)
    place(y, bp(burst(r, 0.04, 0.006), 900, 5000) * 0.18, 0.69)  # second letter slips off
    place(y, _crinkle(r, 0.12, expenv(0.12, 0.04), 25, 2500, 0.5), 0.645)
    y = small_room(r, y, 0.3, 0.15, 4000)  # hallway
    return finish(y, -3, fin=0.002, fout=0.06)


def door_open(r):
    d = 1.2
    y = np.zeros(n_of(d))
    # latch / thumb-latch click
    latch = mix(hp(burst(r, 0.006, 0.0008), 2000) * 0.6, modes(
        r, 0.06, [1750, 3150, 4600], [0.012, 0.008, 0.005], [0.4, 0.3, 0.2]))
    place(y, latch, 0.0)
    place(y, latch * 0.45, 0.035)
    # hinge creak: stick-slip impulse train through wooden door resonances
    cd = 0.85
    tc = T(cd)
    rate = 55 + 95 * np.sin(np.pi * (tc / cd) ** 0.8) + 10 * np.sin(2 * np.pi * 3.1 * tc)
    rate *= 1 + 0.06 * lp(r.standard_normal(len(tc)), 30) / 0.08
    phase = np.cumsum(rate) / SR
    hits = np.diff(np.floor(phase), prepend=0) > 0
    train = hits.astype(float) * r.uniform(0.5, 1.0, len(tc))
    cenv = np.sin(np.pi * tc / cd) ** 0.7 * (0.7 + 0.3 * np.sin(2 * np.pi * 1.6 * tc + 0.5))
    train *= cenv
    creak = (reson(train, 410, 9) * 1.0 + reson(train, 960, 12) * 0.8 +
             reson(train, 1680, 14) * 0.55 + reson(train, 2650, 16) * 0.3)
    creak += bp(r.standard_normal(len(tc)), 300, 2500) * cenv * 0.04
    place(y, creak * 0.55, 0.07)
    # air / door swing whoosh
    sw = lp(r.standard_normal(n_of(0.8)), 300) * np.sin(np.pi * T(0.8) / 0.8) ** 2 * 0.35
    place(y, sw, 0.1)
    # shop bell above the door, clapper bouncing a few times
    bd = 1.1
    for tt, a in [(0.13, 1.0), (0.21, 0.55), (0.30, 0.45), (0.43, 0.3), (0.60, 0.16)]:
        b = bell_partials(r, bd, 2080 * (1 + r.uniform(-0.002, 0.002)),
                          [1.0, 2.42, 4.32, 6.71], [0.55, 0.22, 0.10, 0.05],
                          [1.0, 0.5, 0.28, 0.14])
        b += hp(burst(r, bd, 0.0006), 3000) * 0.4
        place(y, b * a * 0.5, tt)
    return finish(y, -3, fin=0.001, fout=0.15)


def footsteps_wood(r):
    d = 1.6
    y = np.zeros(n_of(d))
    times = [0.06, 0.46, 0.87, 1.25]
    for i, t0 in enumerate(times):
        a = (1.0 if i % 2 == 0 else 0.82) * r.uniform(0.9, 1.05)
        p = r.uniform(0.94, 1.06)
        heel = lp(burst(r, 0.12, 0.010), 550) * 0.9
        heel += modes(r, 0.12, [95 * p, 158 * p, 236 * p, 405 * p, 690 * p],
                      [0.055, 0.045, 0.032, 0.022, 0.012],
                      [0.9, 0.7, 0.45, 0.3, 0.15], detune=0.03)
        heel += bp(burst(r, 0.12, 0.0025), 700, 3000) * 0.5  # hard leather heel tock
        place(y, heel * a, t0)
        toe = bp(burst(r, 0.06, 0.006), 250, 2500) * 0.35
        toe += modes(r, 0.06, [130 * p, 300 * p], [0.02, 0.012], [0.25, 0.12])
        place(y, toe * a, t0 + r.uniform(0.06, 0.085))
    # a floorboard gives a tiny creak under the third step
    tc = T(0.16)
    rate = 140 + 60 * tc / 0.16
    train = (np.diff(np.floor(np.cumsum(rate) / SR), prepend=0) > 0).astype(float)
    train *= np.sin(np.pi * tc / 0.16) * r.uniform(0.5, 1, len(tc))
    cr = reson(train, 520, 10) + reson(train, 1250, 12) * 0.6
    place(y, cr * 0.12, 0.93)
    y = small_room(r, y, 0.3, 0.18, 3000)
    return finish(y, -3, fout=0.1)


def stamp(r):
    d = 0.2
    y = np.zeros(n_of(d))
    thump = lp(burst(r, 0.12, 0.009), 280) * 1.0
    thump += modes(r, 0.12, [82, 138, 205, 330, 520], [0.05, 0.04, 0.03, 0.02, 0.012],
                   [0.8, 0.6, 0.4, 0.25, 0.12], detune=0.02)
    pap = bp(burst(r, 0.02, 0.0025), 500, 2800) * 0.7   # rubber face meets paper
    place(y, thump, 0.004)
    place(y, pap, 0.003)
    # handle wood knock
    place(y, modes(r, 0.05, [880, 1460], [0.01, 0.007], [0.12, 0.07]), 0.005)
    # lifting off: tacky ink peel
    peel = _crinkle(r, 0.04, np.hanning(n_of(0.04)) + 0.01, 14, 1800, 0.18)
    place(y, peel, 0.135)
    return finish(y, -3, fout=0.015)


def lever(r):
    d = 0.8
    y = np.zeros(n_of(d))
    # pawl over ratchet teeth, accelerating then slowing at the end of travel
    clicks = [0.04, 0.12, 0.19, 0.25, 0.305, 0.355, 0.405, 0.46]
    for i, tt in enumerate(clicks):
        a = r.uniform(0.6, 1.0) * (0.75 + 0.25 * i / len(clicks))
        c = hp(burst(r, 0.05, 0.0006), 2000) * 0.4
        c += modes(r, 0.05, [2350, 3420, 5080, 6750], [0.012, 0.009, 0.006, 0.004],
                   [0.5, 0.4, 0.3, 0.2], detune=0.03)
        c += modes(r, 0.05, [470, 760], [0.03, 0.02], [0.25, 0.15])  # iron arm body
        place(y, c * a * 0.9, tt + r.uniform(-0.004, 0.004))
    # gritty pivot grind under the ratchet
    gt = T(0.47)
    grind = bp(r.standard_normal(len(gt)), 180, 1400) * np.sin(np.pi * gt / 0.47) ** 0.5
    grind *= 1 + 0.5 * lp(r.standard_normal(len(gt)), 50) / 0.1
    place(y, grind * 0.07, 0.02)
    # heavy clunk at end of travel, small rebound
    def clunk(a):
        c = lp(burst(r, 0.3, 0.012), 450) * 1.1
        c += modes(r, 0.3, [62, 118, 191, 288, 505], [0.18, 0.12, 0.09, 0.06, 0.04],
                   [1.0, 0.7, 0.5, 0.35, 0.2], detune=0.02)
        c += modes(r, 0.3, [870, 1430, 2210, 3300], [0.12, 0.08, 0.05, 0.03],
                   [0.22, 0.16, 0.1, 0.06])
        c += hp(burst(r, 0.3, 0.001), 1500) * 0.3
        return c * a
    place(y, clunk(1.0), 0.52)
    place(y, clunk(0.2), 0.575)
    return finish(y, -3, fout=0.06)


def press_run(r):
    d = 6.0
    t = T(d)
    n = len(t)
    # cycle rate (cycles/s): spin up over the first second, wind down at the end
    up = np.clip(t / 1.0, 0, 1)
    up = 0.5 - 0.5 * np.cos(np.pi * up)
    down = np.clip((d - t) / 1.05, 0, 1)
    down = 0.5 - 0.5 * np.cos(np.pi * down)
    rate = 0.7 + 1.3 * up
    rate = rate * (0.25 + 0.75 * down)
    amp = (0.35 + 0.65 * up) * down ** 0.8
    phase = np.cumsum(rate) / SR

    y = np.zeros(n)

    def crossings(offset):
        k = np.floor(phase - offset)
        return np.nonzero(np.diff(k) > 0)[0] + 1

    # main clank: bed/platen closing on the forme
    for i in crossings(0.0):
        a = amp[i] * r.uniform(0.9, 1.05)
        c = lp(burst(r, 0.45, 0.018), 900) * 1.0
        c += modes(r, 0.45, [52, 88, 137, 226, 340], [0.2, 0.15, 0.11, 0.08, 0.06],
                   [1.0, 0.8, 0.6, 0.4, 0.3], detune=0.02)
        c += modes(r, 0.45, [430, 790, 1240, 1960, 2870, 4100],
                   [0.10, 0.08, 0.06, 0.045, 0.03, 0.02],
                   [0.35, 0.35, 0.28, 0.22, 0.15, 0.08], detune=0.015)
        c += hp(burst(r, 0.45, 0.0015), 1200) * 0.45
        place(y, c * a, i / SR)
    # secondary clack: gripper / platen opening, lighter and higher
    for i in crossings(0.5):
        a = amp[i] * r.uniform(0.85, 1.0) * 0.5
        c = modes(r, 0.2, [610, 1090, 1760, 2600, 3550], [0.05, 0.04, 0.03, 0.02, 0.012],
                  [0.5, 0.45, 0.35, 0.25, 0.15], detune=0.02)
        c += hp(burst(r, 0.2, 0.001), 1500) * 0.5
        c += lp(burst(r, 0.2, 0.01), 500) * 0.4
        place(y, c * a, i / SR)
    # hiss: air / sheet swept off the tympan, after each clank
    for i in crossings(0.18):
        a = amp[i] * 0.22
        hd = 0.2
        ht = T(hd)
        h = bp(r.standard_normal(len(ht)), 1800, 7500) * np.sin(np.pi * ht / hd) ** 1.5
        h += _crinkle(r, hd, np.sin(np.pi * ht / hd) + 0.05, 25, 2500, 0.6)
        place(y, h * a, i / SR)
    # ink-roller / gear train: continuous rumble and mesh whir tied to the cycle
    rumble = lp(r.standard_normal(n), 160, 4) * 4.0
    rumble *= (0.75 + 0.25 * np.sin(2 * np.pi * phase)) * amp
    mesh_ph = 2 * np.pi * phase * 36.0
    mesh = sum(np.sin(k * mesh_ph + k) / k for k in range(1, 6))
    mesh = bp(mesh * (1 + 0.3 * lp(r.standard_normal(n), 20) / 0.05), 60, 1200) * amp * 0.06
    rollers = bp(r.standard_normal(n), 300, 2500) * amp * 0.03 * (0.6 + 0.4 * np.sin(2 * np.pi * phase + 1.0))
    y += rumble * 0.15 + mesh + rollers
    # gentle saturation glues it together like a big iron machine in a room
    y = small_room(r, y, 0.45, 0.25, 3500)
    y = np.tanh(1.4 * y / np.max(np.abs(y))) / np.tanh(1.4)
    return finish(y, -1, fin=0.005, fout=0.2)


def ui_click(r):
    d = 0.06
    y = np.zeros(n_of(d))
    c = bp(burst(r, 0.004, 0.0006), 1200, 6000) * 0.5
    c = np.pad(c, (0, n_of(0.05) - len(c)))
    c += modes(r, 0.05, [1150, 2280, 3400], [0.010, 0.006, 0.0035], [0.5, 0.3, 0.15])
    c += modes(r, 0.05, [290], [0.012], [0.35])
    place(y, lp(c, 6000), 0.002)
    return finish(y, -12, fout=0.01)


def ui_hover(r):
    d = 0.03
    y = np.zeros(n_of(d))
    c = hp(burst(r, 0.003, 0.0004), 2000) * 0.4
    c = np.pad(c, (0, n_of(0.025) - len(c)))
    c += modes(r, 0.025, [3200, 5100], [0.003, 0.002], [0.5, 0.25])
    place(y, lp(c, 8000), 0.001)
    return finish(y, -20, fout=0.006)


def night_ambience(r):
    L_s, C_s = 20.0, 2.0
    L, C = n_of(L_s), n_of(C_s)
    # room tone: soft pinkish noise, crossfaded into a seamless loop
    nse = r.standard_normal(L + C)
    room = lp(nse, 380, 1) * 0.6 + lp(nse, 120, 2) * 0.8 + bp(r.standard_normal(L + C), 1500, 5000) * 0.05
    room = hp(room, 30)
    room = loop_crossfade(room, L, C)
    room *= 0.03 / np.sqrt(np.mean(room ** 2))
    y = room

    tl = np.arange(L) / SR

    # distant crickets: pulsed near-sine song, placed circularly
    crick = np.zeros(L)
    for f0, period, pulses, gain, phase0 in [(4650, 0.47, 3, 1.0, 0.0),
                                             (4180, 0.61, 4, 0.6, 1.3),
                                             (5020, 0.38, 3, 0.35, 2.4)]:
        t = r.uniform(0, period)
        while t < L_s - 0.3 * period:
            # slow periodic swell; crickets also pause now and then
            sw = 0.55 + 0.45 * np.sin(2 * np.pi * 2 * t / L_s + phase0)
            if sw > 0.22:
                pd = 0.016
                pt = T(pd)
                g = np.zeros(n_of(0.04 * pulses + 0.02))
                f = f0 * r.uniform(0.995, 1.005)
                for k in range(pulses):
                    pulse = np.sin(2 * np.pi * f * pt) + 0.08 * np.sin(4 * np.pi * f * pt)
                    pulse *= np.sin(np.pi * pt / pd) ** 2 * (1 - 0.15 * k)
                    place(g, pulse, k * 0.034)
                place_circ(crick, g, t, gain * sw * r.uniform(0.8, 1.0))
            t += period * r.uniform(0.9, 1.12)
    crick = circ(crick, lambda x: lp(x, 6000))  # distance
    y += crick * 0.11

    # wall clock at 1 Hz, tick / tock
    clock = np.zeros(L)
    for k in range(int(L_s)):
        pitch = 1.0 if k % 2 == 0 else 0.87
        tk = hp(burst(r, 0.06, 0.0005), 2000) * 0.5
        tk += modes(r, 0.06, [2450 * pitch, 3720 * pitch, 5150 * pitch],
                    [0.008, 0.006, 0.004], [0.6, 0.4, 0.25], detune=0.01)
        tk += modes(r, 0.06, [610 * pitch, 1080 * pitch], [0.025, 0.015], [0.35, 0.2])
        tk = lp(tk, 7000)
        place_circ(clock, tk * r.uniform(0.9, 1.0), k + 0.25)
    y += clock * 1.0
    y = circ(y, lambda x: hp(x, 25))
    return normalize(y, -18)


def day_ambience(r):
    L_s, C_s = 20.0, 2.0
    L, C = n_of(L_s), n_of(C_s)
    tl = np.arange(L) / SR

    def periodic_lfo(parts):
        return sum(a * np.sin(2 * np.pi * k * tl / L_s + p) for k, a, p in parts)

    # wind: brownish noise with slow gusts (gust LFO is periodic in the loop)
    nse = r.standard_normal(L + C)
    brown = lp(nse, 60, 1) * 6.0 + lp(nse, 500, 2) * 0.4
    brown = loop_crossfade(hp(brown, 25), L, C)
    whistle = loop_crossfade(bp(r.standard_normal(L + C), 350, 1100), L, C)
    leaves = loop_crossfade(hp(r.standard_normal(L + C), 3000), L, C)
    gust = 0.6 + periodic_lfo([(1, 0.22, 0.3), (3, 0.14, 1.7), (7, 0.07, 4.0), (13, 0.04, 2.2)])
    gust = np.clip(gust, 0.15, None)
    wind = brown / np.std(brown) * gust * 0.5
    wind += whistle / np.std(whistle) * gust ** 3 * 0.06
    wind += leaves / np.std(leaves) * np.clip(gust - 0.55, 0, None) ** 2 * 0.25
    y = wind * 0.05

    # distant birds: a few short sweeping calls with an outdoor tail
    birds = np.zeros(L)
    for t0, kind in [(2.3, 0), (7.9, 1), (11.6, 0), (16.4, 2), (18.9, 1)]:
        call = np.zeros(n_of(1.4))
        if kind == 0:   # two-note "tee-oo"
            notes = [(0.0, 0.11, 4300, 3500), (0.17, 0.16, 3300, 2900)]
        elif kind == 1:  # quick rising chirps
            notes = [(i * 0.09, 0.05, 3000, 4600) for i in range(r.integers(3, 6))]
        else:           # short trill
            notes = [(0.0, 0.45, 3800, 3700)]
        for st, nd, fa, fb in notes:
            nt = T(nd)
            f = np.linspace(fa, fb, len(nt)) * (1 + 0.004 * r.standard_normal())
            if kind == 2:
                f = f + 450 * np.sin(2 * np.pi * 24 * nt)
            ph = 2 * np.pi * np.cumsum(f) / SR
            note = (np.sin(ph) + 0.15 * np.sin(2 * ph)) * np.hanning(len(nt))
            place(call, note, st)
        tail = lp(burst(r, 0.5, 0.12), 4000)
        tail /= np.sqrt(np.sum(tail ** 2))
        call = call + 0.4 * signal.fftconvolve(call, tail)[: len(call)]
        call = lp(call, 5000, 2)
        place_circ(birds, call, t0, r.uniform(0.5, 1.0))
    y += birds * 0.03

    # very far sawmill: a blade whine that sags and roughens while cutting
    cut = np.zeros(L)
    for c0, cl in [(4.0, 5.5), (13.0, 4.0)]:
        seg = (tl - c0) % L_s
        e = np.clip(seg / 0.6, 0, 1) * np.clip((cl - seg) / 0.8, 0, 1) * (seg < cl)
        cut = np.maximum(cut, e)
    f = 420.0 - 55.0 * cut + 3.0 * periodic_lfo([(9, 1.0, 0.0)])
    cycles = np.sum(f) / SR
    f *= round(cycles) / cycles     # whole cycles over the loop -> seamless phase
    ph = 2 * np.pi * np.cumsum(f) / SR
    whine = sum(np.sin(k * ph) / k ** 1.3 for k in range(1, 9))
    rough = loop_crossfade(bp(r.standard_normal(L + C), 200, 1500), L, C)
    saw = whine * (0.25 + 0.75 * cut) + rough / np.std(rough) * cut * 0.25
    saw = circ(saw, lambda x: lp(x, 1100, 2))
    y += saw * 0.0045

    y = circ(y, lambda x: hp(x, 25))
    return normalize(y, -18)


def coins(r):
    d = 0.6
    y = np.zeros(n_of(d))

    def coin_hit(f0, a, ring):
        c = hp(burst(r, 0.25, 0.0004), 2500) * 0.4
        c += modes(r, 0.25, [f0, f0 * 1.72, f0 * 2.33, f0 * 3.08, f0 * 3.9],
                   [ring, ring * 0.8, ring * 0.6, ring * 0.45, ring * 0.3],
                   [0.6, 0.5, 0.4, 0.3, 0.2], detune=0.01)
        c += lp(burst(r, 0.25, 0.006), 700) * 0.35  # wood tabletop
        c += modes(r, 0.25, [320, 690], [0.025, 0.015], [0.2, 0.12])
        return c * a

    for t0, f0, a in [(0.02, 3350, 1.0), (0.18, 2980, 0.85), (0.31, 3720, 0.9)]:
        place(y, coin_hit(f0, a, 0.035), t0)
        # settling wobble: quickly accelerating micro-impacts
        dt, tt, aa = 0.028, t0, a * 0.4
        for _ in range(r.integers(3, 6)):
            tt += dt
            place(y, coin_hit(f0 * r.uniform(0.99, 1.01), aa, 0.015), tt)
            dt *= 0.62
            aa *= 0.6
    # last one lands on another coin: brighter, longer clink
    place(y, coin_hit(4850, 0.7, 0.09), 0.40)
    y = small_room(r, y, 0.2, 0.1, 6000)
    return finish(y, -3, fout=0.05)


def glass_break(r):
    d = 1.2
    y = np.zeros(n_of(d))
    # impact: thump + broadband crack
    place(y, lp(burst(r, 0.08, 0.012), 300) * 0.8, 0.0)
    place(y, hp(burst(r, 0.05, 0.004), 900) * 1.2, 0.0)
    # main crash body: bright noise, decaying, roughened by many grains
    ct = T(0.45)
    crash = hp(r.standard_normal(len(ct)), 2500) * np.exp(-ct / 0.08) * 0.5
    place(y, crash, 0.002)
    # shards: many short ringing grains, dense early, sparse later
    def shard(fmin, fmax, dmin, dmax, a):
        k = r.integers(2, 4)
        fs = r.uniform(fmin, fmax, k)
        ds = r.uniform(dmin, dmax, k)
        g = modes(r, dmax * 4, fs, ds, r.uniform(0.4, 1.0, k))
        g += hp(burst(r, dmax * 4, 0.0004), 3000) * 0.5
        return g * a
    for _ in range(260):
        tt = r.exponential(0.07)
        if tt < d - 0.1:
            place(y, shard(2500, 11000, 0.003, 0.02, r.lognormal(-1.0, 0.5)), tt)
    # larger pieces hitting the floor later, tinkling
    for _ in range(45):
        tt = 0.15 + r.exponential(0.25)
        if tt < d - 0.15:
            place(y, shard(1800, 7000, 0.02, 0.07, r.lognormal(-1.4, 0.5)), tt)
    # one bigger chunk lands
    place(y, shard(1500, 4200, 0.05, 0.1, 0.4) + lp(burst(r, 0.4, 0.01), 400) * 0.2, 0.38)
    y = small_room(r, y, 0.5, 0.2, 7000)
    return finish(y, -6, fout=0.12)


SOUNDS = [
    typewriter_key, typewriter_bell, page_turn, paper_slide, mail_slot,
    door_open, footsteps_wood, stamp, lever, press_run, ui_click, ui_hover,
    night_ambience, day_ambience, coins, glass_break,
]


def write_wav(path, x):
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype(np.int16)
    wavfile.write(path, SR, pcm)


def main(argv):
    os.makedirs(OUT_DIR, exist_ok=True)
    want = set(argv)
    for fn in SOUNDS:
        name = fn.__name__
        if want and name not in want:
            continue
        x = fn(rng_for(name))
        path = os.path.join(OUT_DIR, name + ".wav")
        write_wav(path, x)
        pk = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
        rms = 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)
        print(f"{name + '.wav':22s} {len(x) / SR:6.3f} s  peak {pk:6.1f} dBFS  rms {rms:6.1f} dBFS")


if __name__ == "__main__":
    main(sys.argv[1:])

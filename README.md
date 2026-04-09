# fm2op (a humble Norns AI-assisted synth engine) v1.0.0

**fm2op** is an eight-voice, two-operator FM instrument for Norns, inspired by classic FM hardware. In addition to the basic 2op structure it includes an FX page with a few tasty additions including a drive circuit, low pass filter and redux with an end of chain chorus.

**Included:** MIDI input, preset browsing and loading, carrier/modulator ADSR pages, FM ratio/depth/feedback, and an FX page (drive, tone filter, redux, chorus).

| Component | Path |
|-----------|------|
| Script | `fm2op.lua` |
| Engine class | `lib/Engine_FM2op.sc` |
| Engine name | `FM2op` |

---

## Sound + process

This section is for developers and engineers who are rightfully wary about AI-assisted work, not because of the tooling, but because **undirected “vibe coding”** really can produce shallow code, hidden bugs, and a false sense that craft no longer matters. These worries are legitimate and I empathize.

**fm2op** was **my idea and my product call**: it's a Norns script with a two-operator FM engine, a specific screen layout (presets / carrier / modulator / FM / FX), MIDI behavior, and a sound I wanted to hear—not a generic “make me a synth” dump like you might get from a search engine. I wanted to recreate the nostalgia of early-80s keyboards from my youth. I held the requirements, rejected approaches that did not fit Norns or Crone (from my limited knowledge), and kept iterating until the DSP, presets, and UI behaved the way I intended.

**How the work was done:** I used **several large language models** over the life of the project, alongside normal reading of Norns and SuperCollider docs and watching YouTube tutorials. Early scaffolding and architectural discussion happened mostly in **Claude** (long threads, structure, and conventions before the first coherent code landed in version control). Later passes used **in-editor assistants** (e.g. Cursor) for tight loops: implementing a change, running it on the Norns hardware, spotting regressions, fixing the engine, tuning presets, updating the README (the thing you're reading right now). This is where **co-creation** works best for me: the models propose and refactor; I steer, verify, and own the outcome.

Nothing here replaces **judgment**—FM ratios, envelope shapes, filter drive, redux behavior, polyphony rules, and preset character are the kind of decisions you still make by ear and by reading stack traces. The models **compress iteration time**. I'm not a developer by trade (closer to an average PM); even so, they don't remove the need to understand what you're shipping—and I'm still responsible for that gap when it shows up in the repo.

If you are evaluating this repo: treat it as **human-directed synthesis software** that happened to be built with LLMs in the loop, not as evidence that “AI wrote a sloppy synth” end to end. Thanks for the care you put into your own craft—it matters.

---

## Quick start

1. Copy the project folder to `dust/code/fm2op/` on Norns.
2. Restart, then run `fm2op`.
3. Play from a MIDI controller on port 1; use **PARAMS** or the on-device pages to edit sound.

After editing `Engine_FM2op.sc`, always `;restart` so SuperCollider recompiles the engine correctly.

---

## Signal flow

Per voice, audio is built as follows:

1. **Modulator (Op1)** — `SinOscFB` with its own ADSR and feedback.
2. **Carrier (Op2)** — `SinOsc` FM’d by Op1, with its own ADSR.
3. **Tone / drive** — soft clipping, resonant low-pass with optional cutoff tracking the **carrier** envelope, and bright-punch on the attack.
4. **Chorus** — stereo modulated delays; can be bypassed with K2.
5. **Redux** — last in the chain. One `Decimator` path; **sample rate** and **bit depth** both follow the `redux` control. Output is **crossfaded** dry→wet so `redux = 0` is fully clean (inserting `Decimator` alone at “full rate” is not always transparent on all SC builds).

---

## Screen UI (`E1` = page)

| Page | Role |
|------|------|
| 1 Preset | Browse presets (`E2` loads immediately); `K3` reapplies current preset |
| 2 Carrier | Carrier ADSR |
| 3 Modulator | Modulator ADSR |
| 4 FM | Ratios, depth, feedback |
| 5 FX | Drive, tone, redux, chorus |

**Encoders:** `E2` selects a parameter on the current page (except Preset, where it changes preset). `E3` adjusts the selected value.

**Keys:** On the **FX** page, `K2` toggles chorus. On other pages (not Preset), `K3` sends all notes off.

---

## Parameters (PARAMS menu)

### Carrier envelope
- `car_atk`, `car_dec`, `car_sus`, `car_rel` — attack/decay/sustain/release (times in seconds where applicable).

### Modulator envelope
- `mod_atk`, `mod_dec`, `mod_sus`, `mod_rel` — same idea for the modulator.

### FM core
- `car_ratio`, `mod_ratio` — indices into the ratio table below.
- `mod_depth` — FM index / brightness.
- `feedback` — modulator feedback.

### FX
- `drive` — saturation.
- `bright_punch` — extra FM brightness on the attack.
- `tone_cutoff`, `tone_res`, `tone_env_amt` — ladder filter; cutoff can follow the **carrier** envelope via `tone_env_amt`.
- `redux` — lo-fi amount (`0` = clean, `1` = heavy; in between blends dry and decimated).
- `chorus_rate`, `chorus_depth`, `chorus_mix`, `chorus_on` — chorus.

---

## FM ratio table

Labels available for carrier and modulator:

`1:1`, `3:2`, `2:1`, `5:2`, `3:1`, `7:2`, `4:1`, `5:1`, `5.5`, `7:1`, `11:1`, `14:1`

---

## Presets

Built-in presets: **Piano**, **E.Piano**, **Brass**, **Flute**, **Organ**, **Bell**, **Chime**, **Strings**, **Vibes**, **Synth Bass**.

They are **voiced on purpose** (envelopes, ratios, FX, and optional MIDI offset)—for example **Brass** uses a slightly slower modulator attack than “clicky” FM leads so the harmonic build feels more like a brass-style bloom, not an accidental typo. Along the way I hit plenty of *wrong* voicings too (inverted envelopes, runaway feedback—great for whale-like sound design, less so for melodies).

Loading a preset runs `params:set(...)` on the matching fields, then **`push_engine_state()`** so the engine matches, even if some params were already at the same stored value.

### MIDI transpose (`midi_transpose`)

Optional per-preset field: **semitones** added to incoming MIDI before `noteOn` / `noteOff`, then clamped to **0–127**. Presets that use it:

| Preset | Semitones | Effect |
|--------|-----------|--------|
| Brass, Bell, Strings | `+12` | One octave above played pitch |
| Synth Bass | `-24` | Two octaves below played pitch |

All other presets omit the field (no transpose).

Conceptually I was imagining a limited 2-octave keyboard and wanted to shift the range of the tones to best fit within that framework.

---

## MIDI

- Input device **1**: `midi.connect(1)` in `init`.
- Note on/off use the transposed note: `engine.noteOn(clamp(note + midi_transpose, 0, 127), vel/127)` and the same note number for `noteOff`.
- Velocity scales FM brightness in the engine.

---

## Engine commands and version skew

Lua calls `engine.<command>(value)` by name (`carAtk`, `modDepth`, `redux`, …). The script uses a **guarded** send: if the running engine does not expose that command (e.g. old build), the call is skipped so the script should not crash. Use Maiden’s command list after load to confirm the engine matches the script.

---

## Files

- **`fm2op.lua`** — UI, PARAMS, MIDI, presets, transpose.
- **`lib/Engine_FM2op.sc`** — `SynthDef`, eight-slot voice allocator, Crone commands.

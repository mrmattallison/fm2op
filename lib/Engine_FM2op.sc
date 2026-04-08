// Engine_FM2op.sc
// 2-operator FM synthesis engine for Norns
// Modulator (Op1) -> Carrier (Op2) with chorus

Engine_FM2op : CroneEngine {

  var <synths, <voices, <slotNotes, <slotAges, <voiceAgeCounter;
  var <chorusEnabled;

  *new { arg context, doneCallback;
    ^super.new(context, doneCallback);
  }

  alloc {
    synths = Dictionary.new;
    voices = Array.newClear(8);
    slotNotes = Array.newClear(8);
    slotAges = Array.fill(8, 0);
    voiceAgeCounter = 0;
    chorusEnabled = 0;

    SynthDef(\fm2op_voice, {
      arg out = 0,
          freq = 440,
          vel = 0.8,

          // Modulator (Op1)
          modRatio = 1.0,
          modAtk   = 0.01,
          modDec   = 0.3,
          modSus   = 0.5,
          modRel   = 0.5,
          modDepth = 1.5,
          feedback = 0.0,

          // Carrier (Op2)
          carRatio = 1.0,
          carAtk   = 0.01,
          carDec   = 0.5,
          carSus   = 0.8,
          carRel   = 1.0,
          amp      = 0.5,
          drive    = 0.0,
          brightPunch = 0.0,
          toneCutoff  = 20000,
          toneRes     = 0.1,
          toneEnvAmt  = 0.0,
          redux       = 0.0,

          // Chorus
          chorusRate  = 0.5,
          chorusDepth = 0.005,
          chorusMix   = 0.3,
          chorusOn    = 0,

          gate = 1;

      var modFreq, modEnv, modSig, brightEnv;
      var carFreq, carEnv, carSig, cutoffHz, toneEnv;
      var chorusL, chorusR, wetL, wetR, dryL, dryR, outL, outR, outSig;
      var rx, decimRate, decimBits;

      // --- Modulator ---
      modFreq = freq * modRatio;

      modEnv = EnvGen.kr(
        Env.adsr(modAtk, modDec, modSus, modRel),
        gate
      );

      // SinOscFB gives us feedback for free (0=none, 2pi=full)
      // vel scales brightness: harder playing = more modulation
      brightEnv = EnvGen.kr(Env.perc(0.001, 0.12), gate);
      modSig = SinOscFB.ar(modFreq, feedback * 2pi) * modEnv * modDepth * (1 + (brightPunch * brightEnv)) * vel * freq;

      // --- Carrier ---
      carFreq = (freq * carRatio) + modSig;

      carEnv = EnvGen.kr(
        Env.adsr(carAtk, carDec, carSus, carRel),
        gate,
        doneAction: Done.freeSelf
      );

      carSig = SinOsc.ar(carFreq) * carEnv * amp;
      carSig = tanh(carSig * (1 + (drive * 8)));
      toneEnv = carEnv;
      cutoffHz = (toneCutoff * (1 + (toneEnvAmt * toneEnv))).clip(80, 20000);
      carSig = RLPF.ar(carSig, cutoffHz, (1 - (toneRes.clip(0, 0.95) * 0.8)).clip(0.05, 1.0));

      // --- Chorus (on filtered dry carrier) ---
      chorusL = DelayC.ar(
        carSig,
        0.05,
        chorusDepth * SinOsc.kr(chorusRate, 0) + 0.01
      );
      chorusR = DelayC.ar(
        carSig,
        0.05,
        chorusDepth * SinOsc.kr(chorusRate * 1.03, pi * 0.5) + 0.01
      );

      wetL = XFade2.ar(carSig, chorusL, chorusMix * 2 - 1);
      wetR = XFade2.ar(carSig, chorusR, chorusMix * 2 - 1);
      dryL = carSig;
      dryR = carSig;
      outL = SelectX.ar(chorusOn, [dryL, wetL]);
      outR = SelectX.ar(chorusOn, [dryR, wetR]);

      // Redux: Decimator is not transparent at rate=SR/bits=24 on all builds — bypass with XFade2.
      // rx=0: 100% dry (clean). rx=1: 100% wet (mapped SR + bits). Param changes are audible.
      rx = redux.clip(0, 1);
      decimRate = LinExp.kr(rx.max(0.001), 0.001, 1, SampleRate.ir, 320);
      decimBits = LinLin.kr(rx, 0, 1, 24, 6).clip(4, 24);
      wetL = Decimator.ar(outL, decimRate, decimBits);
      wetR = Decimator.ar(outR, decimRate, decimBits);
      outL = XFade2.ar(outL, wetL, rx * 2 - 1);
      outR = XFade2.ar(outR, wetR, rx * 2 - 1);

      outSig = [outL, outR];

      Out.ar(out, outSig * 0.25);
    }).add;

    // ----- Engine Commands -----

    this.addCommand(\noteOn, "if", { arg msg;
      var note = msg[1].asInteger;
      var vel  = msg[2].asFloat;
      var freq = note.midicps;
      var slot = nil;
      var oldestAge = 1e12;
      var oldNote, oldSynth;
      var i;

      // Retrigger existing note in-place if already allocated.
      8.do({ arg idx;
        if(slotNotes[idx].notNil and: { slotNotes[idx] == note }) {
          slot = idx;
        };
      });

      // Find a free slot.
      if(slot.isNil) {
        8.do({ arg idx;
          if(slot.isNil and: { slotNotes[idx].isNil }) {
            slot = idx;
          };
        });
      };

      // Steal oldest slot when all 8 are occupied.
      if(slot.isNil) {
        8.do({ arg idx;
          if(slotAges[idx] < oldestAge) {
            oldestAge = slotAges[idx];
            slot = idx;
          };
        });
        oldNote = slotNotes[slot];
        if(oldNote.notNil) {
          oldSynth = synths[oldNote];
          if(oldSynth.notNil) { oldSynth.set(\gate, 0); };
          synths.removeAt(oldNote);
        };
      }{
        // If we are reusing a slot for same note, release previous synth first.
        if(slotNotes[slot].notNil and: { slotNotes[slot] == note }) {
          oldSynth = synths[note];
          if(oldSynth.notNil) { oldSynth.set(\gate, 0); };
        };
      };

      voices[slot] = Synth(\fm2op_voice, [
        \out,        context.out_b.index,
        \freq,       freq,
        \vel,        vel,
        \modRatio,   ~modRatio   ? 1.0,
        \modAtk,     ~modAtk     ? 0.01,
        \modDec,     ~modDec     ? 0.3,
        \modSus,     ~modSus     ? 0.5,
        \modRel,     ~modRel     ? 0.5,
        \modDepth,   ~modDepth   ? 1.5,
        \feedback,   ~feedback   ? 0.0,
        \carRatio,   ~carRatio   ? 1.0,
        \carAtk,     ~carAtk     ? 0.01,
        \carDec,     ~carDec     ? 0.5,
        \carSus,     ~carSus     ? 0.8,
        \carRel,     ~carRel     ? 1.0,
        \amp,        ~amp        ? 0.5,
        \drive,      ~drive      ? 0.0,
        \brightPunch, ~brightPunch ? 0.0,
        \toneCutoff, ~toneCutoff ? 20000,
        \toneRes,    ~toneRes    ? 0.1,
        \toneEnvAmt, ~toneEnvAmt ? 0.0,
        \redux,      ~redux      ? 0.0,
        \chorusRate,  ~chorusRate  ? 0.5,
        \chorusDepth, ~chorusDepth ? 0.005,
        \chorusMix,   ~chorusMix   ? 0.3,
        \chorusOn,    chorusEnabled,
        \gate,       1
      ], context.xg);
      synths[note] = voices[slot];
      slotNotes[slot] = note;
      voiceAgeCounter = voiceAgeCounter + 1;
      slotAges[slot] = voiceAgeCounter;
    });

    this.addCommand(\noteOff, "i", { arg msg;
      var note = msg[1].asInteger;
      var i;
      if(synths[note].notNil) {
        synths[note].set(\gate, 0);
        8.do({ arg idx;
          if(slotNotes[idx].notNil and: { slotNotes[idx] == note }) {
            voices[idx] = nil;
            slotNotes[idx] = nil;
            slotAges[idx] = 0;
          };
        });
        synths[note] = nil;
      };
    });

    this.addCommand(\allNotesOff, "", {
      voices.do({ arg s; if(s.notNil) { s.set(\gate, 0); }; });
      synths = Dictionary.new;
      voices = Array.newClear(8);
      slotNotes = Array.newClear(8);
      slotAges = Array.fill(8, 0);
      voiceAgeCounter = 0;
    });

    // Individual param setters — update state vars and all active voices
    this.addCommand(\modRatio, "f", { arg msg;
      ~modRatio = msg[1];
      synths.do({ arg s; s.set(\modRatio, ~modRatio); });
    });

    this.addCommand(\modAtk, "f", { arg msg;
      ~modAtk = msg[1];
      synths.do({ arg s; s.set(\modAtk, ~modAtk); });
    });

    this.addCommand(\modDec, "f", { arg msg;
      ~modDec = msg[1];
      synths.do({ arg s; s.set(\modDec, ~modDec); });
    });

    this.addCommand(\modSus, "f", { arg msg;
      ~modSus = msg[1];
      synths.do({ arg s; s.set(\modSus, ~modSus); });
    });

    this.addCommand(\modRel, "f", { arg msg;
      ~modRel = msg[1];
      synths.do({ arg s; s.set(\modRel, ~modRel); });
    });

    this.addCommand(\modDepth, "f", { arg msg;
      ~modDepth = msg[1];
      synths.do({ arg s; s.set(\modDepth, ~modDepth); });
    });

    this.addCommand(\feedback, "f", { arg msg;
      ~feedback = msg[1];
      synths.do({ arg s; s.set(\feedback, ~feedback); });
    });

    this.addCommand(\carRatio, "f", { arg msg;
      ~carRatio = msg[1];
      synths.do({ arg s; s.set(\carRatio, ~carRatio); });
    });

    this.addCommand(\carAtk, "f", { arg msg;
      ~carAtk = msg[1];
      synths.do({ arg s; s.set(\carAtk, ~carAtk); });
    });

    this.addCommand(\carDec, "f", { arg msg;
      ~carDec = msg[1];
      synths.do({ arg s; s.set(\carDec, ~carDec); });
    });

    this.addCommand(\carSus, "f", { arg msg;
      ~carSus = msg[1];
      synths.do({ arg s; s.set(\carSus, ~carSus); });
    });

    this.addCommand(\carRel, "f", { arg msg;
      ~carRel = msg[1];
      synths.do({ arg s; s.set(\carRel, ~carRel); });
    });

    this.addCommand(\amp, "f", { arg msg;
      ~amp = msg[1];
      synths.do({ arg s; s.set(\amp, ~amp); });
    });

    this.addCommand(\drive, "f", { arg msg;
      ~drive = msg[1];
      synths.do({ arg s; s.set(\drive, ~drive); });
    });

    this.addCommand(\brightPunch, "f", { arg msg;
      ~brightPunch = msg[1];
      synths.do({ arg s; s.set(\brightPunch, ~brightPunch); });
    });

    this.addCommand(\toneCutoff, "f", { arg msg;
      ~toneCutoff = msg[1];
      synths.do({ arg s; s.set(\toneCutoff, ~toneCutoff); });
    });

    this.addCommand(\toneRes, "f", { arg msg;
      ~toneRes = msg[1];
      synths.do({ arg s; s.set(\toneRes, ~toneRes); });
    });

    this.addCommand(\toneEnvAmt, "f", { arg msg;
      ~toneEnvAmt = msg[1];
      synths.do({ arg s; s.set(\toneEnvAmt, ~toneEnvAmt); });
    });

    this.addCommand(\redux, "f", { arg msg;
      ~redux = msg[1];
      synths.do({ arg s; s.set(\redux, ~redux); });
    });

    this.addCommand(\chorusRate, "f", { arg msg;
      ~chorusRate = msg[1];
      synths.do({ arg s; s.set(\chorusRate, ~chorusRate); });
    });

    this.addCommand(\chorusDepth, "f", { arg msg;
      ~chorusDepth = msg[1];
      synths.do({ arg s; s.set(\chorusDepth, ~chorusDepth); });
    });

    this.addCommand(\chorusMix, "f", { arg msg;
      ~chorusMix = msg[1];
      synths.do({ arg s; s.set(\chorusMix, ~chorusMix); });
    });

    this.addCommand(\chorusOn, "i", { arg msg;
      chorusEnabled = msg[1];
      synths.do({ arg s; s.set(\chorusOn, chorusEnabled); });
    });
  }

  free {
    voices.do({ arg s; if(s.notNil) { s.free; }; });
  }
}

-- fm2op v1.0.0
-- 2-operator FM synth
-- Norns, 8-voice MIDI
--
--
--
--    ▼ instructions below ▼
--
-- E1: change page
--     Preset / Carrier /
--     Modulator / FM / FX
--
-- E2: Preset = browse
--     presets (each loads)
--     else pick parameter
--
-- E3: adjust value
--
-- Preset K3: reload
--     selected preset
-- FX K2: chorus
-- else K3: all notes off
--
-- Thanks Norns +
-- SuperCollider folks
--
engine.name = "FM2op"

local midi_in     = nil
local screen_dirty = true
-- Semitones added to incoming MIDI before engine (set from active preset).
local midi_transpose = 0

-- ----------------------------------------------------------------
-- Ratio table
-- ----------------------------------------------------------------

local RATIOS = {
  { label = "1:1",  val = 1.0  },
  { label = "3:2",  val = 1.5  },
  { label = "2:1",  val = 2.0  },
  { label = "5:2",  val = 2.5  },
  { label = "3:1",  val = 3.0  },
  { label = "7:2",  val = 3.5  },
  { label = "4:1",  val = 4.0  },
  { label = "5:1",  val = 5.0  },
  { label = "5.5",  val = 5.5  },
  { label = "7:1",  val = 7.0  },
  { label = "11:1", val = 11.0 },
  { label = "14:1", val = 14.0 },
}

local function ratio_index_for(val)
  for i, r in ipairs(RATIOS) do
    if math.abs(r.val - val) < 0.01 then return i end
  end
  return 1
end

-- ----------------------------------------------------------------
-- Presets
-- chorus_on always false — chorus is a manual choice
-- ----------------------------------------------------------------

local PRESETS = {
  {
    name      = "Piano",
    car_ratio = ratio_index_for(1.0),
    mod_ratio = ratio_index_for(3.0),
    mod_depth = 0.65,
    feedback  = 0.05,
    car_atk   = 0.01, car_dec = 2.0, car_sus = 0.6, car_rel = 1.5,
    mod_atk   = 0.001, mod_dec = 0.22, mod_sus = 0.0, mod_rel = 0.12,
    chorus_rate = 0.5, chorus_depth = 0.005, chorus_mix = 0.25,
    chorus_on = false,
  },
  {
    name      = "E.Piano",
    car_ratio = ratio_index_for(1.0),
    mod_ratio = ratio_index_for(5.0),
    mod_depth = 0.85,
    feedback  = 0.05,
    car_atk   = 0.01, car_dec = 3.0, car_sus = 0.5, car_rel = 2.0,
    mod_atk   = 0.001, mod_dec = 0.25, mod_sus = 0.0, mod_rel = 0.15,
    chorus_rate = 0.35, chorus_depth = 0.006, chorus_mix = 0.35,
    chorus_on = false,
  },
  {
    name      = "Brass",
    car_ratio = ratio_index_for(1.0),
    mod_ratio = ratio_index_for(1.0),
    mod_depth = 0.45,
    feedback  = 0.14,
    car_atk   = 0.04, car_dec = 0.25, car_sus = 0.85, car_rel = 0.25,
    mod_atk   = 0.042, mod_dec = 0.22, mod_sus = 0.1, mod_rel = 0.12,
    drive = 0.0, bright_punch = 1.1, tone_cutoff = 3600, tone_res = 0.22, tone_env_amt = 0.9,
    chorus_rate = 0.6, chorus_depth = 0.004, chorus_mix = 0.2,
    chorus_on = false,
     -- One octave up played keys (MIDI note sent to engine is clamped 0..127).
     midi_transpose = 12
  },
  {
    name      = "Flute",
    car_ratio = ratio_index_for(1.0),
    mod_ratio = ratio_index_for(1.0),
    mod_depth = 0.4,
    feedback  = 0.0,
    car_atk   = 0.08, car_dec = 0.5, car_sus = 0.8, car_rel = 0.6,
    mod_atk   = 0.08, mod_dec = 0.5, mod_sus = 0.7, mod_rel = 0.4,
    chorus_rate = 0.5, chorus_depth = 0.005, chorus_mix = 0.3,
    chorus_on = false,
  },
  {
    name      = "Organ",
    car_ratio = ratio_index_for(1.0),
    mod_ratio = ratio_index_for(2.0),
    mod_depth = 0.35,
    feedback  = 0.08,
    car_atk   = 0.01, car_dec = 0.01, car_sus = 1.0, car_rel = 0.08,
    mod_atk   = 0.01, mod_dec = 0.01, mod_sus = 1.0, mod_rel = 0.08,
    chorus_rate = 0.8, chorus_depth = 0.005, chorus_mix = 0.25,
    chorus_on = false,
  },
  {
    name      = "Bell",
    car_ratio = ratio_index_for(1.0),
    mod_ratio = ratio_index_for(5.5),
    mod_depth = 2.0,
    feedback  = 0.0,
    car_atk   = 0.001,car_dec = 3.0, car_sus = 0.0, car_rel = 4.0,
    mod_atk   = 0.001,mod_dec = 1.5, mod_sus = 0.0, mod_rel = 2.0,
    chorus_rate = 0.3, chorus_depth = 0.008, chorus_mix = 0.35,
    chorus_on = false,
     -- One octave up played keys (MIDI note sent to engine is clamped 0..127).
     midi_transpose = 12
  },
  {
    name      = "Chime",
    car_ratio = ratio_index_for(1.0),
    mod_ratio = ratio_index_for(3.5),
    mod_depth = 1.5,
    feedback  = 0.0,
    car_atk   = 0.001,car_dec = 2.0, car_sus = 0.0, car_rel = 3.0,
    mod_atk   = 0.001,mod_dec = 0.8, mod_sus = 0.0, mod_rel = 1.5,
    chorus_rate = 0.4, chorus_depth = 0.007, chorus_mix = 0.4,
    chorus_on = false,
  },
  {
    name      = "Strings",
    car_ratio = ratio_index_for(1.0),
    mod_ratio = ratio_index_for(2.0),
    mod_depth = 0.26,
    feedback  = 0.04,
    car_atk   = 0.4,  car_dec = 1.0, car_sus = 0.7, car_rel = 1.5,
    mod_atk   = 0.35, mod_dec = 1.0, mod_sus = 0.25, mod_rel = 1.2,
    drive = 0.04, bright_punch = 0.08, tone_cutoff = 2800, tone_res = 0.12, tone_env_amt = 0.45,
    redux = 0.05,
    chorus_rate = 0.5, chorus_depth = 0.009, chorus_mix = 0.5,
    chorus_on = false,
    -- One octave up played keys (MIDI note sent to engine is clamped 0..127).
    midi_transpose = 12
  },
  {
    name      = "Vibes",
    car_ratio = ratio_index_for(1.0),
    mod_ratio = ratio_index_for(5.0),
    mod_depth = 1.05,
    feedback  = 0.02,
    car_atk   = 0.001,car_dec = 2.5, car_sus = 0.0, car_rel = 2.0,
    mod_atk   = 0.001, mod_dec = 0.8, mod_sus = 0.0, mod_rel = 1.3,
    chorus_rate = 0.5, chorus_depth = 0.005, chorus_mix = 0.3,
    chorus_on = false,
  },
  {
    name      = "Synth Bass",
    car_ratio = ratio_index_for(1.0),
    mod_ratio = ratio_index_for(3.0),
    mod_depth = 0.58,
    feedback  = 0.3,
    car_atk   = 0.005, car_dec = 0.2, car_sus = 0.55, car_rel = 0.15,
    mod_atk   = 0.001, mod_dec = 0.09, mod_sus = 0.0, mod_rel = 0.08,
    drive = 0.10, bright_punch = 0.55, tone_cutoff = 1200, tone_res = 0.35, tone_env_amt = 0.5,
    redux = 0.18,
    chorus_rate = 0.6, chorus_depth = 0.004, chorus_mix = 0.15,
    chorus_on = false,
    -- Two octaves below played keys (MIDI note sent to engine is clamped 0..127).
    midi_transpose = -24,
  },
}

-- ----------------------------------------------------------------
-- UI state
-- ----------------------------------------------------------------

local PAGE_PRESET   = 1
local PAGE_CARRIER  = 2
local PAGE_MOD      = 3
local PAGE_FM       = 4
local PAGE_FX       = 5
local NUM_PAGES     = 5

local ui = {
  page       = PAGE_PRESET,
  preset_idx = 1,
  -- selected param index within current page (1-based)
  sel        = { [1]=1, [2]=1, [3]=1, [4]=1, [5]=1 },
  -- note activity indicator
  note_active = false,
  note_clock  = nil,
}

-- param counts per page (for E2 wrapping)
local PAGE_PARAM_COUNT = { 0, 4, 4, 4, 9 }

-- ----------------------------------------------------------------
-- Params
-- ----------------------------------------------------------------

local function send(key, val)
  local fn = engine[key]
  if type(fn) == "function" then fn(val) end
end

-- Push all param values to the engine (used after preset load so audio always
-- matches params even if params:set skipped actions for unchanged values).
local function push_engine_state()
  send("carAtk", params:get("car_atk"))
  send("carDec", params:get("car_dec"))
  send("carSus", params:get("car_sus"))
  send("carRel", params:get("car_rel"))
  send("modAtk", params:get("mod_atk"))
  send("modDec", params:get("mod_dec"))
  send("modSus", params:get("mod_sus"))
  send("modRel", params:get("mod_rel"))
  send("carRatio", RATIOS[params:get("car_ratio")].val)
  send("modRatio", RATIOS[params:get("mod_ratio")].val)
  send("modDepth", params:get("mod_depth"))
  send("feedback", params:get("feedback"))
  send("drive", params:get("drive"))
  send("brightPunch", params:get("bright_punch"))
  send("toneCutoff", params:get("tone_cutoff"))
  send("toneRes", params:get("tone_res"))
  send("toneEnvAmt", params:get("tone_env_amt"))
  send("redux", params:get("redux"))
  send("chorusRate", params:get("chorus_rate"))
  send("chorusDepth", params:get("chorus_depth"))
  send("chorusMix", params:get("chorus_mix"))
  send("chorusOn", params:get("chorus_on") - 1)
end

local function load_preset(idx)
  -- Preset changes `midi_transpose`; held keys would otherwise get noteOff on the
  -- wrong pitch than noteOn. Silencing all voices avoids stuck notes.
  engine.allNotesOff()

  local p = PRESETS[idx]
  local function pget(key, default)
    local v = p[key]
    if v == nil then return default end
    return v
  end
  params:set("car_ratio",    p.car_ratio)
  params:set("mod_ratio",    p.mod_ratio)
  params:set("mod_depth",    pget("mod_depth", 1.5))
  params:set("feedback",     pget("feedback", 0.0))
  params:set("car_atk",      pget("car_atk", 0.01))
  params:set("car_dec",      pget("car_dec", 0.5))
  params:set("car_sus",      pget("car_sus", 0.8))
  params:set("car_rel",      pget("car_rel", 1.0))
  params:set("mod_atk",      pget("mod_atk", 0.01))
  params:set("mod_dec",      pget("mod_dec", 0.3))
  params:set("mod_sus",      pget("mod_sus", 0.5))
  params:set("mod_rel",      pget("mod_rel", 0.5))
  params:set("drive",        pget("drive", 0.0))
  params:set("bright_punch", pget("bright_punch", 0.0))
  params:set("tone_cutoff",  pget("tone_cutoff", 20000))
  params:set("tone_res",     pget("tone_res", 0.1))
  params:set("tone_env_amt", pget("tone_env_amt", 0.0))
  params:set("redux",        pget("redux", 0.0))
  params:set("chorus_rate",  pget("chorus_rate", 0.5))
  params:set("chorus_depth", pget("chorus_depth", 0.005))
  params:set("chorus_mix",   pget("chorus_mix", 0.3))
  -- option params are 1-based: 1=off, 2=on (never use 0)
  params:set("chorus_on",    p.chorus_on and 2 or 1)

  midi_transpose = pget("midi_transpose", 0)

  push_engine_state()

  screen_dirty = true
end

local function init_params()

  params:add_separator("FM2OP")

  -- Carrier envelope
  params:add_control("car_atk", "Car Attack",
    controlspec.new(0.001, 4.0, "exp", 0.001, 0.01, "s"))
  params:set_action("car_atk", function(v) send("carAtk", v) end)

  params:add_control("car_dec", "Car Decay",
    controlspec.new(0.01, 4.0, "exp", 0.001, 0.5, "s"))
  params:set_action("car_dec", function(v) send("carDec", v) end)

  params:add_control("car_sus", "Car Sustain",
    controlspec.new(0.0, 1.0, "lin", 0.01, 0.8))
  params:set_action("car_sus", function(v) send("carSus", v) end)

  params:add_control("car_rel", "Car Release",
    controlspec.new(0.01, 8.0, "exp", 0.001, 1.0, "s"))
  params:set_action("car_rel", function(v) send("carRel", v) end)

  -- Modulator envelope
  params:add_control("mod_atk", "Mod Attack",
    controlspec.new(0.001, 4.0, "exp", 0.001, 0.01, "s"))
  params:set_action("mod_atk", function(v) send("modAtk", v) end)

  params:add_control("mod_dec", "Mod Decay",
    controlspec.new(0.01, 4.0, "exp", 0.001, 0.3, "s"))
  params:set_action("mod_dec", function(v) send("modDec", v) end)

  params:add_control("mod_sus", "Mod Sustain",
    controlspec.new(0.0, 1.0, "lin", 0.01, 0.5))
  params:set_action("mod_sus", function(v) send("modSus", v) end)

  params:add_control("mod_rel", "Mod Release",
    controlspec.new(0.01, 8.0, "exp", 0.001, 0.5, "s"))
  params:set_action("mod_rel", function(v) send("modRel", v) end)

  -- FM params
  params:add_option("car_ratio", "Car Ratio",
    (function() local t={} for _,r in ipairs(RATIOS) do t[#t+1]=r.label end return t end)(),
    1)
  params:set_action("car_ratio", function(v)
    send("carRatio", RATIOS[v].val)
  end)

  params:add_option("mod_ratio", "Mod Ratio",
    (function() local t={} for _,r in ipairs(RATIOS) do t[#t+1]=r.label end return t end)(),
    1)
  params:set_action("mod_ratio", function(v)
    send("modRatio", RATIOS[v].val)
  end)

  params:add_control("mod_depth", "Mod Depth",
    controlspec.new(0.0, 10.0, "lin", 0.01, 1.5))
  params:set_action("mod_depth", function(v) send("modDepth", v) end)

  params:add_control("feedback", "Feedback",
    controlspec.new(0.0, 1.0, "lin", 0.01, 0.0))
  params:set_action("feedback", function(v) send("feedback", v) end)

  params:add_separator("FX")

  params:add_control("drive", "Drive",
    controlspec.new(0.0, 1.0, "lin", 0.01, 0.0))
  params:set_action("drive", function(v) send("drive", v) end)

  params:add_control("bright_punch", "Bright Punch",
    controlspec.new(0.0, 2.0, "lin", 0.01, 0.0))
  params:set_action("bright_punch", function(v) send("brightPunch", v) end)

  params:add_control("tone_cutoff", "Tone Cutoff",
    controlspec.new(100.0, 20000.0, "exp", 1, 20000.0, "Hz"))
  params:set_action("tone_cutoff", function(v) send("toneCutoff", v) end)

  params:add_control("tone_res", "Tone Res",
    controlspec.new(0.0, 0.95, "lin", 0.01, 0.1))
  params:set_action("tone_res", function(v) send("toneRes", v) end)

  params:add_control("tone_env_amt", "Tone Env Amt",
    controlspec.new(0.0, 2.0, "lin", 0.01, 0.0))
  params:set_action("tone_env_amt", function(v) send("toneEnvAmt", v) end)

  params:add_control("redux", "Redux",
    controlspec.new(0.0, 1.0, "lin", 0.01, 0.0))
  params:set_action("redux", function(v) send("redux", v) end)

  -- Chorus
  params:add_control("chorus_rate", "Chorus Rate",
    controlspec.new(0.1, 5.0, "lin", 0.01, 0.5, "Hz"))
  params:set_action("chorus_rate", function(v) send("chorusRate", v) end)

  params:add_control("chorus_depth", "Chorus Depth",
    controlspec.new(0.0, 0.02, "lin", 0.0001, 0.005, "s"))
  params:set_action("chorus_depth", function(v) send("chorusDepth", v) end)

  params:add_control("chorus_mix", "Chorus Mix",
    controlspec.new(0.0, 1.0, "lin", 0.01, 0.3))
  params:set_action("chorus_mix", function(v) send("chorusMix", v) end)

  params:add_option("chorus_on", "Chorus On", {"off", "on"}, 1)
  params:set_action("chorus_on", function(v)
    send("chorusOn", v - 1)  -- option is 1-indexed; engine wants 0/1
  end)
end

-- ----------------------------------------------------------------
-- MIDI
-- ----------------------------------------------------------------

local function to_engine_note(note)
  return util.clamp(note + midi_transpose, 0, 127)
end

local function note_on(note, vel)
  engine.noteOn(to_engine_note(note), vel / 127)
  ui.note_active = true
  if ui.note_clock then ui.note_clock:stop() end
  ui.note_clock = clock.run(function()
    clock.sleep(0.15)
    ui.note_active = false
    screen_dirty = true
  end)
  screen_dirty = true
end

local function note_off(note)
  engine.noteOff(to_engine_note(note))
end

local function init_midi()
  midi_in = midi.connect(1)
  midi_in.event = function(data)
    local msg = midi.to_msg(data)
    if msg.type == "note_on" and msg.vel > 0 then
      note_on(msg.note, msg.vel)
    elseif msg.type == "note_off"
        or (msg.type == "note_on" and msg.vel == 0) then
      note_off(msg.note)
    end
  end
end

-- ----------------------------------------------------------------
-- Drawing helpers
-- ----------------------------------------------------------------

local function draw_header(title, page, total)
  screen.level(4)
  screen.move(0, 7)
  screen.text(title)
  screen.move(128, 7)
  screen.text_right(page .. "/" .. total)
end

-- Draw an ADSR shape aligned with SuperCollider Env.adsr(attack,decay,sustain,release):
-- horizontal extent of attack/decay/release is proportional to their durations (seconds).
-- Sustain is a level (0..1), not a time; we draw a short horizontal plateau for it.
local function draw_adsr(x, y, w, h, atk, dec, sus, rel, sel)
  local y0 = y + h
  local y_peak = y
  local y_sus = y + h * (1 - sus)
  local T = atk + dec + rel
  if T < 1e-9 then
    T = 1e-9
  end
  local w_sus = util.clamp(w * 0.2, 6, w * 0.32)
  local w_adr = w - w_sus
  local w_a = w_adr * atk / T
  local w_d = w_adr * dec / T
  local w_r = w_adr * rel / T

  local x0 = x
  local x1 = x0 + w_a
  local x2 = x1 + w_d
  local x3 = x2 + w_sus
  local x4 = x0 + w

  local segs = {
    { x0, y0, x1, y_peak },   -- attack
    { x1, y_peak, x2, y_sus }, -- decay
    { x2, y_sus, x3, y_sus },  -- sustain (level)
    { x3, y_sus, x4, y0 },    -- release
  }
  local labels = { "A", "D", "S", "R" }
  local cx = { (x0 + x1) / 2, (x1 + x2) / 2, (x2 + x3) / 2, (x3 + x4) / 2 }

  for i, seg in ipairs(segs) do
    screen.level(i == sel and 15 or 3)
    screen.move(seg[1], seg[2])
    screen.line(seg[3], seg[4])
    screen.stroke()
  end

  for i, lbl in ipairs(labels) do
    screen.level(i == sel and 15 or 4)
    screen.move(cx[i], y + h + 8)
    screen.text_center(lbl)
  end
end

local function fmt(v, decimals)
  return string.format("%." .. (decimals or 2) .. "f", v)
end

-- ----------------------------------------------------------------
-- Page renderers
-- ----------------------------------------------------------------

local function draw_preset_page()
  local p = PRESETS[ui.preset_idx]
  draw_header("FM2OP", 1, NUM_PAGES)

  local name = p.name
  screen.level(15)
  screen.font_size(16)
  screen.move(64, 36)
  screen.text_center(name)
  screen.font_size(8)

  -- Navigation hint
  screen.level(4)
  screen.move(0, 56)
  screen.text("E2 preset  K3 load")

  -- Preset index
  screen.level(8)
  screen.move(128, 56)
  screen.text_right(ui.preset_idx .. "/" .. #PRESETS)
end

local function draw_envelope_page(title, page_num, prefix, sel)
  draw_header(title, page_num, NUM_PAGES)

  local a = params:get(prefix .. "atk")
  local d = params:get(prefix .. "dec")
  local s = params:get(prefix .. "sus")
  local r = params:get(prefix .. "rel")

  draw_adsr(4, 12, 90, 30, a, d, s, r, sel)

  -- Values row
  local vals = {
    fmt(a, 3), fmt(d, 2), fmt(s, 2), fmt(r, 2)
  }
  for i, v in ipairs(vals) do
    screen.level(i == sel and 15 or 5)
    screen.move(4 + (i - 0.5) * 22, 58)
    screen.text_center(v)
  end

  -- E3 hint
  screen.level(3)
  screen.move(108, 20)
  screen.text("E2")
  screen.move(108, 30)
  screen.text("sel")
  screen.move(108, 42)
  screen.text("E3")
  screen.move(108, 52)
  screen.text("val")
end

local function draw_fm_page()
  draw_header("FM", PAGE_FM, NUM_PAGES)

  local sel = ui.sel[PAGE_FM]

  local items = {
    { label = "MOD RATIO", val = RATIOS[params:get("mod_ratio")].label },
    { label = "CAR RATIO", val = RATIOS[params:get("car_ratio")].label },
    { label = "DEPTH",     val = fmt(params:get("mod_depth"), 2) },
    { label = "FEEDBACK",  val = fmt(params:get("feedback"), 2) },
  }

  -- 2x2 grid
  local positions = {
    { x = 2,  y = 22 },
    { x = 66, y = 22 },
    { x = 2,  y = 44 },
    { x = 66, y = 44 },
  }

  for i, item in ipairs(items) do
    local pos = positions[i]
    local active = i == sel
    screen.level(active and 15 or 4)
    screen.move(pos.x + (active and 6 or 0), pos.y)
    if active then
      screen.text("> " .. item.label)
    else
      screen.text(item.label)
    end
    screen.level(active and 15 or 8)
    screen.move(pos.x + (active and 6 or 0), pos.y + 10)
    screen.text(item.val)
  end
end

local function draw_fx_page()
  draw_header("FX", PAGE_FX, NUM_PAGES)

  local sel     = ui.sel[PAGE_FX]
  local enabled = params:get("chorus_on") == 2  -- option 1=off, 2=on

  screen.level(6)
  screen.move(64, 18)
  screen.text_center(enabled and "chorus:on" or "chorus:off")
  screen.level(3)
  screen.move(64, 26)
  screen.text_center("K2 toggle")

  local items = {
    { label = "DRV",   val = fmt(params:get("drive"), 2) },
    { label = "CUT",   val = string.format("%.0f", params:get("tone_cutoff")) },
    { label = "RES",   val = fmt(params:get("tone_res"), 2) },
    { label = "ENV",   val = fmt(params:get("tone_env_amt"), 2) },
    { label = "PUNCH", val = fmt(params:get("bright_punch"), 2) },
    { label = "REDUX", val = fmt(params:get("redux"), 2) },
    { label = "CHR RT",val = fmt(params:get("chorus_rate"), 2) },
    { label = "CHR DP",val = fmt(params:get("chorus_depth"), 4) },
    { label = "CHR MX",val = fmt(params:get("chorus_mix"), 2) },
  }

  local current = items[sel]
  screen.level(15)
  screen.move(64, 42)
  screen.text_center(current.label)
  screen.move(64, 54)
  screen.text_center(current.val)
  screen.level(4)
  screen.move(8, 42)
  screen.text("< " .. (items[sel - 1] and items[sel - 1].label or ""))
  screen.move(120, 42)
  screen.text_right((items[sel + 1] and items[sel + 1].label or "") .. " >")
end

-- ----------------------------------------------------------------
-- Redraw
-- ----------------------------------------------------------------

function redraw()
  screen.clear()
  screen.aa(1)
  screen.font_face(0)
  screen.font_size(8)

  if ui.page == PAGE_PRESET then
    draw_preset_page()
  elseif ui.page == PAGE_CARRIER then
    draw_envelope_page("CARRIER", PAGE_CARRIER, "car_", ui.sel[PAGE_CARRIER])
  elseif ui.page == PAGE_MOD then
    draw_envelope_page("MODULATOR", PAGE_MOD, "mod_", ui.sel[PAGE_MOD])
  elseif ui.page == PAGE_FM then
    draw_fm_page()
  elseif ui.page == PAGE_FX then
    draw_fx_page()
  end

  screen.update()
end

-- ----------------------------------------------------------------
-- Encoder / key handlers
-- ----------------------------------------------------------------

-- Maps page + sel to a param key
local function get_param_key(page, sel)
  if page == PAGE_CARRIER then
    return ({ "car_atk","car_dec","car_sus","car_rel" })[sel]
  elseif page == PAGE_MOD then
    return ({ "mod_atk","mod_dec","mod_sus","mod_rel" })[sel]
  elseif page == PAGE_FM then
    return ({ "mod_ratio","car_ratio","mod_depth","feedback" })[sel]
  elseif page == PAGE_FX then
    return ({
      "drive", "tone_cutoff", "tone_res", "tone_env_amt", "bright_punch",
      "redux",
      "chorus_rate", "chorus_depth", "chorus_mix"
    })[sel]
  end
end

function enc(n, delta)
  if n == 1 then
    -- Page select
    ui.page = util.clamp(ui.page + delta, 1, NUM_PAGES)

  elseif n == 2 then
    if ui.page == PAGE_PRESET then
      local prev = ui.preset_idx
      ui.preset_idx = util.clamp(ui.preset_idx + delta, 1, #PRESETS)
      if ui.preset_idx ~= prev then
        load_preset(ui.preset_idx)
      end
    else
      -- Select param within page
      local count = PAGE_PARAM_COUNT[ui.page]
      ui.sel[ui.page] = util.clamp(ui.sel[ui.page] + delta, 1, count)
    end

  elseif n == 3 then
    if ui.page ~= PAGE_PRESET then
      local key = get_param_key(ui.page, ui.sel[ui.page])
      if key then
        params:delta(key, delta)
      end
    end
  end

  screen_dirty = true
end

function key(n, z)
  if z == 0 then return end  -- only act on press

  if n == 2 then
    if ui.page == PAGE_FX then
      -- Toggle chorus on/off
      local current = params:get("chorus_on")
      params:set("chorus_on", current == 1 and 2 or 1)
    end

  elseif n == 3 then
    if ui.page == PAGE_PRESET then
      -- Load selected preset
      load_preset(ui.preset_idx)
    else
      -- All notes off from any page
      engine.allNotesOff()
    end
  end

  screen_dirty = true
end

-- ----------------------------------------------------------------
-- Refresh loop
-- ----------------------------------------------------------------

local function refresh()
  while true do
    clock.sleep(1/30)
    if screen_dirty then
      redraw()
      screen_dirty = false
    end
  end
end

-- ----------------------------------------------------------------
-- Init
-- ----------------------------------------------------------------

function init()
  init_params()
  init_midi()
  params:read()
  params:bang()

  load_preset(1)

  clock.run(refresh)
end

function cleanup()
  engine.allNotesOff()
  if midi_in then
    midi_in.event = nil
  end
end

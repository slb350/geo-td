-- Enemy affixes (V2-M5): a single wave-level modifier that turns a wave into a
-- tactical puzzle. From a per-affix min_wave a qualifying (non-boss) wave may
-- carry one affix, chosen by a DERIVED rng (so it doesn't consume the run's main
-- rng -- the spawn sequence is unchanged, only the affix EFFECTS differ, and the
-- balance sim can disable affixes via run.no_affixes). Affixes apply DERIVED enemy
-- fields at spawn (lib/wave drip) or on split (lib/enemy), or set wave-level flags
-- (Null Field -> lib/resonance). They are announced by the threat preview and
-- listed in the run report. None of this mutates a base enemy/tower def.
--
-- Lifecycle: affix.choose(run, n) (from run.begin_wave) sets run.wave_affix +
-- history + the Null-Field timer; affix.update (from lib/loop) ticks that timer;
-- affix.expire clears it on wave clear. Consumers read run.wave_affix fields
-- directly (it IS the resolved DEFS row) or call the small lifecycle hooks here;
-- keep those hooks leaf-like so enemy/wave integration stays cycle-free.

local C     = require("lib.const")
local rng   = require("lib.rng")
local shape = require("lib.shape")

local DEFS = usagi.read_json("affixes.json")

local M = {}
M.DEFS = DEFS
M.ORDER = { "mirrored", "armored_front", "veiled_pack", "overclock", "fracture", "null_field" }

-- Deterministic affix id for wave n, or nil. Skipped for boss waves (the boss
-- check is inlined to avoid a require cycle with lib/wave) and when run.no_affixes
-- is set. A derived roll first gates whether the wave has an affix at all.
function M.for_wave(run, n)
  if run.no_affixes then return nil end
  if (run.mode and run.mode.boss_rush) or n % C.BOSS_EVERY == 0 then return nil end
  local pool = {}
  for i = 1, #M.ORDER do
    local id = M.ORDER[i]
    if (DEFS[id].min_wave or 1) <= n then pool[#pool + 1] = id end
  end
  if #pool == 0 then return nil end
  local r = rng.derive(run.seed, n * 53 + 17)
  if r:next() >= C.AFFIX_CHANCE then return nil end   -- this wave draws no affix
  return pool[r:int(1, #pool)]
end

-- Choose + arm the wave's affix (or clear it). run.wave_affix becomes the resolved
-- DEFS row (read-only; consumers read its fields). Called from run.begin_wave.
function M.choose(run, n)
  local id = M.for_wave(run, n)
  if not id then
    run.wave_affix = nil
    run.affix_null_active = false
    run.affix_timer = 0
    run.affix_veil_source = nil
    run.affix_overclock_active = false
    return
  end
  local d = DEFS[id]
  run.wave_affix = d
  run.affix_history[#run.affix_history + 1] = id
  run.affix_veil_source = nil
  run.affix_overclock_active = d.overclock_until_aura == true
  if d.disable_resonance then
    run.affix_timer = d.duration
    run.affix_null_active = true
    run.resonance_dirty = true        -- suppress circuits now; restore when it ends
  else
    run.affix_timer = 0
    run.affix_null_active = false
  end
end

-- Apply the spawn-time affix to a freshly dripped enemy (DERIVED fields only).
-- `idx`/`total` size the "vanguard" fraction. Called from lib/wave's drip spawn.
function M.apply_spawn(run, e, idx, total)
  local a = run.wave_affix
  if not a then return end
  local vanguard = idx <= math.ceil(total * (a.fraction or 0))
  if a.armor_add and vanguard then e.armor = e.armor + a.armor_add end
  if a.veil_source and vanguard and not run.affix_veil_source then
    e.affix_veil_source = true
    e.affix_stealth_radius = a.stealth_radius or 42
    run.affix_veil_source = e
  end
  if a.speed_mult and (not a.overclock_until_aura or run.affix_overclock_active) then
    e.affix_speed_mult = a.speed_mult
    e.affix_overclock = a.overclock_until_aura == true
  end
  if a.mirror_pairs then e.affix_mirrored = true end
end

local veil_sources = {}   -- reused scratch; only indices 1..sn are ever read

local function update_veil(run)
  local list = run.enemies
  local sources, sn = veil_sources, 0
  for i = 1, list.n do
    local e = list[i]
    e.affix_stealth = false
    if e.affix_veil_source and not e.dead then
      sn = sn + 1
      sources[sn] = e
    end
  end
  for s = 1, sn do
    local src = sources[s]
    local r = src.affix_stealth_radius or 42
    local r2 = r * r
    for i = 1, list.n do
      local e = list[i]
      if e ~= src and not e.dead then
        local dx, dy = e.x - src.x, e.y - src.y
        if dx * dx + dy * dy <= r2 then e.affix_stealth = true end
      end
    end
  end
  if sn == 0 then run.affix_veil_source = nil end
end

-- Tick wave affix state; restore resonance when Null Field lapses and refresh
-- source-based veil stealth before tower acquisition. From lib/loop.
function M.update(run, dt)
  if run.wave_affix and run.wave_affix.veil_source then update_veil(run) end
  if run.affix_null_active then
    run.affix_timer = run.affix_timer - dt
    if run.affix_timer <= 0 then
      run.affix_null_active = false
      run.resonance_dirty = true
    end
  end
end

function M.overclock_source_killed(run, e)
  local a = run.wave_affix
  if a and a.overclock_until_aura and run.affix_overclock_active and e.def and e.def.aura then
    run.affix_overclock_active = false
  end
end

function M.draw(run)
  local a = run.wave_affix
  if not a then return end
  local list = run.enemies
  for i = 1, list.n do
    local e = list[i]
    if not e.dead then
      if e.affix_veil_source then
        gfx.circ(e.x, e.y, e.affix_stealth_radius or 42, gfx.COLOR_PINK)
        shape.line(a.shape or "diamond", e.x, e.y, e.size + 5, gfx.COLOR_PINK, usagi.elapsed)
      elseif e.affix_stealth then
        gfx.circ(e.x, e.y, e.size + 5, gfx.COLOR_PINK)
      end
      if e.affix_speed_mult then
        shape.line("tri", e.x, e.y, e.size + 4, gfx.COLOR_ORANGE, usagi.elapsed)
      end
      if e.affix_mirrored then
        shape.line("hex", e.x, e.y, e.size + 3, gfx.COLOR_BLUE, usagi.elapsed)
      end
    end
  end
end

-- Clear the affix on wave clear (the next wave's choose overwrites it anyway, but
-- this keeps the between-wave banner clean).
function M.expire(run)
  run.wave_affix = nil
  run.affix_null_active = false
  run.affix_timer = 0
  run.affix_veil_source = nil
  run.affix_overclock_active = false
end

return M

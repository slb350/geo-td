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
-- directly (it IS the resolved DEFS row), so the hot paths never require this
-- module -- which keeps lib/enemy and lib/wave free of a require cycle.

local C   = require("lib.const")
local rng = require("lib.rng")

local DEFS = usagi.read_json("affixes.json")

local M = {}
M.DEFS = DEFS
M.ORDER = { "armored_front", "veiled_pack", "overclock", "fracture", "null_field" }

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
    return
  end
  local d = DEFS[id]
  run.wave_affix = d
  run.affix_history[#run.affix_history + 1] = id
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
  if a.stealth and vanguard then e.affix_stealth = true end
  if a.speed_mult then e.base_speed = e.base_speed * a.speed_mult end
end

-- Tick the Null-Field timer; restore resonance when it lapses. From lib/loop.
function M.update(run, dt)
  if run.affix_null_active then
    run.affix_timer = run.affix_timer - dt
    if run.affix_timer <= 0 then
      run.affix_null_active = false
      run.resonance_dirty = true
    end
  end
end

-- Clear the affix on wave clear (the next wave's choose overwrites it anyway, but
-- this keeps the between-wave banner clean).
function M.expire(run)
  run.wave_affix = nil
  run.affix_null_active = false
  run.affix_timer = 0
end

return M

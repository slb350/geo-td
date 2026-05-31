-- Wave threat preview (V2-M1): a PURE read of what the upcoming wave will throw
-- at the player, so they can build the right counter before pressing START. It
-- never consumes the run's rng (that would desync the actual spawn), so it
-- reports the unlockable pool's threat *tags* and an approximate budget, not an
-- exact roster. Consumers: the build-phase HUD/field preview and (later) the
-- affix/contract previews.

local wave    = require("lib.wave")
local enemy   = require("lib.enemy")
local boss    = require("lib.boss")
local pathmut = require("lib.pathmut")

local M = {}

-- The threat tags shown to the player, in display order. Each maps to "what
-- counter this enemy property demands".
M.TAG_ORDER = { "flyers", "armor", "shield", "regen", "stealth", "splits", "aura" }
M.TAG_LABEL = {
  flyers = "flyers", armor = "armor", shield = "shield", regen = "regen",
  stealth = "stealth", splits = "splitters", aura = "aura",
}

-- Fold one enemy def's threatening properties into the tag set.
local function def_tags(def, tags)
  if def.fly then tags.flyers = true end
  if (def.armor or 0) > 0 then tags.armor = true end
  if (def.shield or 0) > 0 then tags.shield = true end
  if (def.regen or 0) > 0 then tags.regen = true end
  if def.split then tags.splits = true end
  local a = def.aura
  if a then
    tags.aura = true
    if a.kind == "stealth" then tags.stealth = true end
  end
end

-- Preview wave n for the given run. Returns:
--   { wave, boss, boss_kind?, budget?, tags = {set}, tag_list = {ordered}, route_event }
-- boss waves carry only the boss flag/kind (no normal pool); route_event warns
-- that a route choice follows THIS wave (before n+1).
function M.preview(run, n)
  local out = { wave = n, tags = {}, tag_list = {} }
  out.route_event = pathmut.pending_for(run, n + 1)

  if wave.is_boss_for(run, n) then
    out.boss = true
    out.boss_kind = run.mode.boss_rush and boss.cycle(n) or boss.for_wave(n)
    return out
  end

  out.boss = false
  out.budget = wave.budget_for(run, n)
  local pool = wave.weighted_pool(wave.pool_for(n), run.mode)
  local tags = {}
  for i = 1, #pool do def_tags(enemy.DEFS[pool[i].kind], tags) end
  if run.mode.flyer_bias then tags.flyers = true end   -- mode floods the skies
  out.tags = tags

  for i = 1, #M.TAG_ORDER do
    local t = M.TAG_ORDER[i]
    if tags[t] then out.tag_list[#out.tag_list + 1] = t end
  end
  return out
end

return M

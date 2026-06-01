-- Towers: placement validity, target acquisition by policy, cooldown firing
-- into the projectile pool, temporary disable (boss shockwave), aiming + muzzle
-- flash, and geometric rendering (square = Pellet, diamond = Splash, hex = Frost).

local C     = require("lib.const")
local pal   = require("lib.palette")
local path  = require("lib.path")
local proj  = require("lib.projectile")
local fx    = require("lib.fx")
local shape = require("lib.shape")
local modifier = require("lib.modifier")
local target = require("lib.target")
local resource = require("lib.resource")
local resonance = require("lib.resonance")

local DEFS = usagi.read_json("towers.json")

local M = {}
M.DEFS = DEFS

-- Stable display order for the build palette.
M.ORDER = { "pellet", "splash", "frost", "rail", "flak", "drill" }

-- Per-tower targeting overrides (M1), cycled from the inspect panel. false =
-- "auto" (the tower's data-driven priority + policy). "first"/"closest"/
-- "strongest" override the tie-break policy; "air"/"boss" force a focus tier
-- (prefer that target type) while keeping the policy.
M.TARGETING = { false, "first", "closest", "strongest", "air", "boss" }

function M.targeting_label(ov)
  return ov or "auto"
end

-- A focus override only helps if the tower can actually hit that target type:
-- "air" needs an air-capable tower, "boss" needs a ground-capable one (the boss
-- is ground). Policy overrides + auto always apply. Keeps the inspect panel from
-- offering a focus that would silently do nothing.
local function focus_usable(def, ov)
  local tg = def.targets or "ground"
  if ov == "air"  then return tg == "all" or tg == "air" end
  if ov == "boss" then return tg == "all" or tg == "ground" end
  return true
end

-- The targeting options usable by a tower kind (auto + policies + the focuses it
-- can hit), in cycle order.
function M.targeting_options(def)
  local out = {}
  for i = 1, #M.TARGETING do
    if focus_usable(def, M.TARGETING[i]) then out[#out + 1] = M.TARGETING[i] end
  end
  return out
end

-- Next targeting override for a tower, cycling only through its usable options.
function M.cycle_targeting(def, ov)
  local opts = M.targeting_options(def)
  ov = ov or false
  for i = 1, #opts do
    if opts[i] == ov then return opts[(i % #opts) + 1] end
  end
  return opts[1]
end

-- air/ground targeting eligibility (shared with the projectile chain)
local can_hit = target.can_hit

function M.cost(run, kind)
  local def = DEFS[kind]
  return math.max(1, math.floor(def.cost * run.mods.cost_mult))
end

function M.available(meta, kind, mode)
  if mode and mode.no_rail and kind == "rail" then return false end   -- "No Rail" mode
  local def = DEFS[kind]
  if def.locked then
    return meta.unlocks[def.unlock] == true
  end
  return true
end

function M.can_place(run, x, y, kind)
  if x < 0 or x >= C.HUD_X or y < 0 or y >= C.GAME_H then
    return false, "out of bounds"
  end
  if path.dist_to(run.path, x, y) < C.PLACE_MARGIN then
    return false, "too close to path"
  end
  local towers = run.towers
  local min_d = C.TOWER_R * 2
  for i = 1, #towers do
    local t = towers[i]
    local dx, dy = t.x - x, t.y - y
    if dx * dx + dy * dy < min_d * min_d then
      return false, "overlaps a tower"
    end
  end
  if run.money < M.cost(run, kind) then
    return false, "not enough money"
  end
  if DEFS[kind].role == "support" and not resource.near_node(run, x, y) then
    return false, "must be near a prism"   -- the Drill extracts only beside a node
  end
  return true, nil
end

function M.place(run, x, y, kind)
  local def = DEFS[kind]
  run.tower_seq = run.tower_seq + 1
  local t = {
    kind = kind, def = def, x = x, y = y,
    id = run.tower_seq,
    cooldown = 0, disabled_t = 0, aim = 0, flash = 0,
    color = pal.resolve(def.color),
    shape = def.shape,
    upgrades = {},   -- [upgrade id] = level  (per-tower in-run progression, M3)
    module = nil,    -- one socketed geometry module id, or nil
    eff = {},        -- reused effective-stats scratch (no per-frame allocation)
  }
  run.towers[#run.towers + 1] = t
  local cost = M.cost(run, kind)
  run.money = run.money - cost
  run.money_spent = run.money_spent + cost
  t.invested = cost   -- cumulative spend on this tower (grows with upgrades/modules);
                      -- the M7 auto-refund returns it in full
  -- per-tower damage stat lives on the run (keyed by id), so it survives a sell
  run.tower_stats[t.id] = { kind = kind, damage = 0 }
  run.resonance_dirty = true        -- topology changed (M4)
  fx.place_sfx()
  return t
end

function M.sell(run, t)
  if run.no_sell then return end          -- "No Sell" contract gates selling this wave
  local towers = run.towers
  for i = 1, #towers do
    if towers[i] == t then
      run.money = run.money + math.floor(M.cost(run, t.kind) * C.SELL_REFUND)
      table.remove(towers, i)
      run.resonance_dirty = true     -- topology changed (M4)
      fx.sell_sfx()
      return
    end
  end
end

function M.at(run, x, y)
  local towers = run.towers
  for i = 1, #towers do
    local t = towers[i]
    local dx, dy = t.x - x, t.y - y
    if dx * dx + dy * dy <= C.TOWER_R * C.TOWER_R then
      return t
    end
  end
  return nil
end

-- Priority tier for a candidate, from a `priority` list (e.g. {"boss","air"}).
-- Earlier entries rank higher; 0 = no priority match. A higher tier always beats
-- a lower one regardless of the `targeting` score.
local function target_tier(priority, is_boss, is_fly)
  if not priority then return 0 end
  for i = 1, #priority do
    local c = priority[i]
    if (c == "boss" and is_boss) or (c == "air" and is_fly) then
      return #priority - i + 1
    end
  end
  return 0
end

-- Shared single-entry priority lists for the focus overrides (read-only in
-- acquire), so effective_targeting allocates nothing on the per-frame firing path.
local AIR_FOCUS  = { "air" }
local BOSS_FOCUS = { "boss" }

-- The effective (priority list, policy) for a tower, applying its optional M1
-- targeting override. A policy override swaps only the tie-break; a focus
-- override ("air"/"boss") forces a single-entry priority list; auto = the def's
-- own `priority` + `targeting`. Returns plain data, never mutating the def.
local function effective_targeting(t)
  local def = t.def
  local ov = t.targeting_override
  if ov == "first" or ov == "closest" or ov == "strongest" then
    return def.priority, ov
  elseif ov == "air" then
    return AIR_FOCUS, def.targeting
  elseif ov == "boss" then
    return BOSS_FOCUS, def.targeting
  end
  return def.priority, def.targeting
end

-- Tie-break score within a tier, per the tower's `targeting` policy. Higher
-- wins: "closest" = nearest, "strongest" = most HP, default ("first") = furthest
-- along the path (closest to the core).
local function score(policy, dist2, hp, progress)
  if policy == "closest" then return -dist2
  elseif policy == "strongest" then return hp end
  return progress
end

-- True when (tier, sc) outranks the current best: higher tier always wins, an
-- equal tier breaks on score; a nil best (best_tier == nil) loses to anything.
local function better(tier, sc, best_tier, best_score)
  return best_tier == nil or tier > best_tier or (tier == best_tier and sc > best_score)
end

local function acquire(run, t, range)
  local r2 = range * range
  local list = run.enemies
  local def = t.def
  local priority, policy = effective_targeting(t)
  local best, best_tier, best_score
  for i = 1, list.n do
    local e = list[i]
    if not e.dead and target.targetable(e) and can_hit(def, e) then
      local dx, dy = e.x - t.x, e.y - t.y
      local d2 = dx * dx + dy * dy
      if d2 <= r2 then
        local tier = target_tier(priority, false, e.fly)
        local sc = score(policy, d2, e.hp, e.d)
        if better(tier, sc, best_tier, best_score) then
          best, best_tier, best_score = e, tier, sc
        end
      end
    end
  end
  local b = run.boss
  if b and not b.dead and can_hit(def, b) then
    local dx, dy = b.x - t.x, b.y - t.y
    local d2 = dx * dx + dy * dy
    if d2 <= r2 then
      local tier = target_tier(priority, true, b.fly)
      local sc = score(policy, d2, b.hp, run.path.total_len)
      if better(tier, sc, best_tier, best_score) then
        best, best_tier, best_score = b, tier, sc
      end
    end
  end
  return best
end

function M.update(run, dt)
  resonance.update(run)            -- recompute only if the topology changed (M4)
  local towers = run.towers
  local mods = run.mods
  for i = 1, #towers do
    local t = towers[i]
    if t.flash > 0 then t.flash = t.flash - dt end
    if t.disabled_t > 0 then
      -- a blackout disable ticks down on EVERY tower (incl. support Drills, whose
      -- charge extraction in lib/resource is gated on the same disabled_t)
      t.disabled_t = t.disabled_t - dt
    elseif t.def.role == "support" then
      -- support towers (Drill) don't acquire or fire; lib/resource extracts charge
    else
      local def = t.def
      local eff = modifier.effective(run, t, t.eff)
      local target = acquire(run, t, eff.range)
      if target then
        -- two-arg atan gives the heading (Lua 5.3+/Usagi 5.5)
        t.aim = math.atan(target.y - t.y, target.x - t.x)
      end
      t.cooldown = t.cooldown - dt
      if t.cooldown <= 0 and target then
        local dmg = eff.damage
        local crit = mods.crit_chance + eff.crit   -- global crit + module crit
        if crit > 0 and run.rng:chance(crit) then
          dmg = dmg * 2
        end
        proj.spawn(run, t.x, t.y, target, {
          damage = dmg,
          speed = eff.proj_speed,
          radius = def.proj_r,
          color = t.color,
          splash_radius = eff.splash_radius,
          slow_factor = def.slow_factor,
          slow_time = def.slow_time,
          tower = t,
          pierce = mods.pierce + eff.pierce,        -- global card + module socket
          ricochet = mods.ricochet + eff.ricochet,
        })
        t.cooldown = 1 / eff.fire_rate
        t.flash = 0.06
        fx.shoot_sfx()
      end
    end
  end
end

function M.draw(run, t, show_range)
  local r = C.TOWER_R
  local disabled = t.disabled_t > 0
  local color = disabled and gfx.COLOR_DARK_GRAY or t.color
  if show_range then
    gfx.circ(t.x, t.y, modifier.effective(run, t, t.eff).range, pal.RANGE)
  end
  local body_rot = t.shape == "hex" and (usagi.elapsed * 0.6) or 0
  shape.line(t.shape, t.x, t.y, r + 1, gfx.COLOR_DARK_GRAY, body_rot)
  shape.fill(t.shape, t.x, t.y, r, color, body_rot)
  if not disabled then
    local blen = t.def.barrel_len
    if blen and blen > 0 then
      local bw = t.def.barrel_w or 2
      local ex, ey = t.x + math.cos(t.aim) * blen, t.y + math.sin(t.aim) * blen
      gfx.line_ex(t.x, t.y, ex, ey, bw, gfx.COLOR_WHITE)
      if t.flash > 0 then gfx.circ_fill(ex, ey, bw + 1, gfx.COLOR_YELLOW) end
    elseif t.flash > 0 then
      gfx.circ(t.x, t.y, r + 2, gfx.COLOR_YELLOW)   -- barrel-less field tower pulse
    end
  end
  -- inner counter-rotating facet: a constructed-turret core
  shape.fill(t.shape, t.x, t.y, r * 0.4, gfx.COLOR_WHITE, -body_rot)
  if disabled then
    gfx.circ(t.x, t.y, r + 2, gfx.COLOR_RED)
  end
end

return M

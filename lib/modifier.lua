-- Per-tower modifier substrate (M3). Two in-run customization features share
-- one effective-stat layer:
--   * Upgrades: leveled numeric lines per tower kind (data/upgrades.json),
--     bought repeatedly with a cost that scales per level.
--   * Geometry module: one qualitative socket per tower (triangle=crit,
--     square=pierce, circle=range, hex=ricochet, diamond=splash).
-- `effective(run, t, out)` folds base def -> global run.mods -> per-tower
-- upgrades -> module into one stats table, written into the caller-owned `out`
-- (a tower keeps its own t.eff) so the per-frame firing path allocates nothing.
-- The firing path (tower.update / tower.draw) reads these effective stats
-- instead of `def * run.mods` directly.

local C = require("lib.const")

local UPDEFS = usagi.read_json("upgrades.json")

local M = {}
M.UPDEFS = UPDEFS

-- One-per-tower geometry sockets. `value` meaning depends on `effect`; `shape`
-- is the icon's primitive (a real shape.* name).
M.MODULES = {
  triangle = { name = "Triangle", effect = "crit",     value = 0.25, desc = "+25% crit",   shape = "tri" },
  square   = { name = "Square",   effect = "pierce",   value = 1,    desc = "pierce +1",    shape = "square" },
  circle   = { name = "Circle",   effect = "range",    value = 0.30, desc = "+30% range",   shape = "circ" },
  hex      = { name = "Hex",      effect = "ricochet", value = 1,    desc = "ricochet +1",  shape = "hex" },
  diamond  = { name = "Diamond",  effect = "splash",   value = 0.50, desc = "+50% splash",  shape = "diamond" },
}
M.MODULE_ORDER = { "triangle", "square", "circle", "hex", "diamond" }

-- Cost to take an upgrade from its current level to the next (scales linearly).
function M.upgrade_cost(def, level)
  return def.base_cost * (level + 1)
end

-- Usagi live-reload (usagi dev) preserves State.run across a reload, so a tower
-- placed before this module's per-tower fields existed can lack them. Backfill
-- on first touch so a mid-run reload self-heals: `upgrades` (else effective
-- crashes) and `eff` (else the firing path re-allocates its scratch table every
-- frame, defeating the no-allocation goal). `module` defaults to nil, which is
-- already handled.
local function ensure(t)
  if not t.upgrades then t.upgrades = {} end
  if not t.eff then t.eff = {} end
  return t
end

-- Find an upgrade def for a tower kind by id (nil if none).
local function find_upgrade(kind, id)
  local list = UPDEFS[kind]
  if list then
    for i = 1, #list do
      if list[i].id == id then return list[i] end
    end
  end
end

-- Summed per-tower upgrade multiplier for a stat (1 = no upgrades).
local function up_mult(t, stat)
  local list = UPDEFS[t.kind]
  local m = 1
  if list then
    for i = 1, #list do
      local u = list[i]
      if u.stat == stat then m = m + u.per_level * (t.upgrades[u.id] or 0) end
    end
  end
  return m
end

-- Effective stats for tower t, folding base -> global mods -> upgrades -> module.
-- Writes into `out` (reused per tower) to avoid per-frame allocation.
function M.effective(run, t, out)
  out = out or {}
  ensure(t)
  local def, mods = t.def, run.mods
  local range  = def.range * mods.range_mult * up_mult(t, "range_mult")
  local splash = (def.splash_radius or 0) * mods.splash_mult * up_mult(t, "splash_mult")
  out.damage     = def.damage * mods.dmg_mult * up_mult(t, "dmg_mult")
  out.fire_rate  = def.fire_rate * mods.rate_mult * up_mult(t, "rate_mult")
  out.proj_speed = def.proj_speed * mods.proj_mult
  out.crit, out.pierce, out.ricochet = 0, 0, 0
  local mod = t.module and M.MODULES[t.module]
  if mod then
    local e, v = mod.effect, mod.value
    if e == "crit" then out.crit = v
    elseif e == "pierce" then out.pierce = v
    elseif e == "ricochet" then out.ricochet = v
    elseif e == "range" then range = range * (1 + v)
    elseif e == "splash" then splash = splash * (1 + v) end
  end
  out.range = range
  out.splash_radius = splash
  return out
end

-- Per-upgrade rows for the inspect UI: level, next cost, maxed/affordable flags.
function M.upgrade_options(run, t)
  ensure(t)
  local list = UPDEFS[t.kind] or {}
  local out = {}
  for i = 1, #list do
    local def = list[i]
    local lvl = t.upgrades[def.id] or 0
    local maxed = lvl >= def.max_level
    local cost = maxed and 0 or M.upgrade_cost(def, lvl)
    out[i] = {
      id = def.id, name = def.name, level = lvl, max_level = def.max_level,
      cost = cost, maxed = maxed, afford = (not maxed) and run.money >= cost,
    }
  end
  return out
end

function M.can_buy_upgrade(run, t, id)
  ensure(t)
  local def = find_upgrade(t.kind, id)
  if not def then return false end
  local lvl = t.upgrades[id] or 0
  return lvl < def.max_level and run.money >= M.upgrade_cost(def, lvl)
end

function M.buy_upgrade(run, t, id)
  if not M.can_buy_upgrade(run, t, id) then return false end
  local def = find_upgrade(t.kind, id)
  local lvl = t.upgrades[id] or 0
  local cost = M.upgrade_cost(def, lvl)
  run.money = run.money - cost
  run.money_spent = run.money_spent + cost   -- gross spend (M1 run-report stat)
  t.upgrades[id] = lvl + 1
  t.invested = (t.invested or 0) + cost       -- counts toward the M7 full auto-refund
  return true
end

-- Effective module-socket cost, after a one-shot "No Sell" contract discount (M3).
function M.module_cost(run)
  return math.max(0, C.MODULE_COST - (run.module_discount or 0))
end

-- A tower has a single module socket; it can be filled once.
function M.can_socket(run, t, module_id)
  return M.MODULES[module_id] ~= nil and t.module == nil and run.money >= M.module_cost(run)
end

function M.socket_module(run, t, module_id)
  if not M.can_socket(run, t, module_id) then return false end
  local cost = M.module_cost(run)
  run.money = run.money - cost
  run.money_spent = run.money_spent + cost            -- gross spend (M1 run-report stat)
  run.module_discount = 0                             -- one-shot discount consumed
  t.module = module_id
  t.invested = (t.invested or 0) + cost               -- counts toward the M7 full auto-refund
  return true
end

return M

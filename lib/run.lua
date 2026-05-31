-- Builds a fresh run: economy, modifiers, entity pools, and the path. Applies
-- meta unlocks (start bonus) at creation. A "run" is the whole roguelike climb;
-- it lives at State.run and is nil between runs.

local C     = require("lib.const")
local path  = require("lib.path")
local rng   = require("lib.rng")
local fx    = require("lib.fx")
local maps  = require("lib.maps")
local enemy = require("lib.enemy")

local M = {}

function M.new(meta, seed, path_name)
  local money, lives = C.START_MONEY, C.START_LIVES
  if meta.unlocks.start_bonus then
    money = money + 50
    lives = lives + 5
  end
  fx.clear()
  -- an explicit map (map-select / tests) if it names a real layout, else a
  -- seed-derived fallback so any run still gets a valid map.
  local key = (path_name and maps.exists(path_name)) and path_name or maps.pick(seed)
  local layout = maps.get(key)
  return {
    seed = seed,
    rng = rng.new(seed),
    path = path.build(layout.nodes),
    path_name = key,
    map_name = layout.name,
    wave_index = 0,
    phase = "building",  -- building | combat | upgrade
    money = money,
    lives = lives,
    score = 0,
    kills = 0,
    hp_scale = 1,
    speed_scale = 1,
    towers = {},
    enemies = { n = 0 },
    projectiles = { n = 0 },
    boss = nil,
    bosses_killed = 0,
    spawn_queue = { n = 0, i = 0 },
    spawn_timer = 0,
    spawn_interval = C.SPAWN_INTERVAL,
    powerups = {},
    mods = {
      dmg_mult = 1, rate_mult = 1, range_mult = 1, bounty_mult = 1, cost_mult = 1,
      proj_mult = 1, splash_mult = 1, crit_chance = 0, interest = 0, life_per_wave = 0,
    },
  }
end

function M.alive(run)
  return run.lives > 0
end

-- True when the field is clear of enemies and the boss (wave fully resolved).
function M.field_clear(run)
  if run.enemies.n > 0 then return false end
  if run.boss and not run.boss.dead then return false end
  return true
end

-- Orbital strike availability: only mid-combat, with the cost on hand, and only
-- when there is actually something on the field to nuke (so the button greys
-- out rather than burning $500 on an empty screen).
function M.can_orbital(run)
  return run.phase == "combat" and run.money >= C.ORBITAL_COST and run.enemies.n > 0
end

-- Spend ORBITAL_COST to vaporize every enemy currently on the field. This is a
-- pure clear -- no bounty, no score, and no splitter children -- so the screen
-- truly empties and the cost stays a real money sink. The boss is in run.boss,
-- not run.enemies, so it is untouched.
function M.orbital_strike(run)
  if not M.can_orbital(run) then return false end
  run.money = run.money - C.ORBITAL_COST
  local list = run.enemies
  for i = 1, list.n do
    enemy.vaporize(list[i])
  end
  return true
end

return M

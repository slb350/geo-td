-- Builds a fresh run: economy, modifiers, entity pools, and the path. Applies
-- meta unlocks (start bonus) at creation. A "run" is the whole roguelike climb;
-- it lives at State.run and is nil between runs.

local C    = require("lib.const")
local path = require("lib.path")
local rng  = require("lib.rng")
local fx   = require("lib.fx")

local PATHS = usagi.read_json("paths.json")

local M = {}

function M.new(meta, seed)
  local money, lives = C.START_MONEY, C.START_LIVES
  if meta.unlocks.start_bonus then
    money = money + 50
    lives = lives + 5
  end
  fx.clear()
  return {
    seed = seed,
    rng = rng.new(seed),
    path = path.build(PATHS.default.nodes),
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

return M

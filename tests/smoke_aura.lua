-- M4 enemy formation auras: derived buff application + decay (leave radius /
-- emitter dies), no self-buff, per-kind effects, combat integration (armor/
-- shield/regen), stealth targeting, and the enemy.update pass. Run by smoke.lua.

local meta = require("lib.meta")
local enemy = require("lib.enemy")
local combat = require("lib.combat")
local aura = require("lib.aura")
local tower = require("lib.tower")
local helpers = require("tests.helpers")

local M = {}

-- spawn an enemy of `kind` parked at (x,y) with its aura fields reset
local function at(r, kind, x, y)
  local e = enemy.spawn(r, kind, 1, 1, 10)
  e.x, e.y = x, y
  return e
end

function M.run(check, near)
  local m = meta.default()
  local function fresh(seed)
    return helpers.fresh(m, seed)
  end
  -- a fresh run with an empty enemy pool (the common aura-test starting point)
  local function clean()
    local r = fresh()
    r.enemies.n = 0
    return r
  end

  -- a target inside an emitter's radius gains the derived buff; the emitter
  -- never buffs itself
  do
    local r = clean()
    local em = at(r, "warden", 100, 100) -- shield aura, radius 38, value 12
    local tgt = at(r, "mote", 110, 100) -- 10px away, inside radius
    aura.update(r)
    check(near(tgt.aura_shield, 12), "an enemy inside a shield-carrier radius gains the ward")
    check(em.aura_shield == 0, "the emitter does not buff itself")
  end

  -- leaving the radius drops the buff next tick
  do
    local r = clean()
    at(r, "warden", 100, 100)
    local tgt = at(r, "mote", 110, 100)
    aura.update(r)
    check(near(tgt.aura_shield, 12), "buffed while in range")
    tgt.x, tgt.y = 300, 300
    aura.update(r)
    check(tgt.aura_shield == 0, "leaving the radius drops the buff")
  end

  -- killing the emitter removes the buff from the pack
  do
    local r = clean()
    local em = at(r, "warden", 100, 100)
    local tgt = at(r, "mote", 110, 100)
    aura.update(r)
    check(near(tgt.aura_shield, 12), "buffed while emitter lives")
    em.dead = true
    aura.update(r)
    check(tgt.aura_shield == 0, "a dead emitter buffs no one")
  end

  -- each aura kind sets its own derived field
  do
    local r = clean()
    at(r, "accelerant", 100, 100)
    local s = at(r, "mote", 108, 100)
    at(r, "totem", 100, 200)
    local g = at(r, "mote", 108, 200)
    at(r, "lattice", 100, 250)
    local a = at(r, "mote", 108, 250)
    at(r, "veil", 300, 100)
    local v = at(r, "mote", 308, 100)
    aura.update(r)
    check(near(s.aura_speed, 1.4), "speed prism grants a speed multiplier")
    check(near(g.aura_regen, 10), "regen node grants regen")
    check(near(a.aura_armor, 3), "armor lattice grants armor")
    check(v.aura_stealth == true, "stealth veil hides a neighbor")
  end

  -- stacking semantics: armor + regen ADD across emitters; shield takes the
  -- STRONGEST (max). A single-emitter test can't tell add from max here (reset
  -- is 0), so two-emitter cases pin the design decision.
  do
    local r = clean()
    at(r, "lattice", 100, 100)
    at(r, "lattice", 120, 100)
    local a = at(r, "mote", 110, 100) -- inside both lattice radii
    at(r, "totem", 100, 200)
    at(r, "totem", 120, 200)
    local g = at(r, "mote", 110, 200)
    at(r, "warden", 100, 300)
    at(r, "warden", 120, 300)
    local s = at(r, "mote", 110, 300)
    aura.update(r)
    check(near(a.aura_armor, 6), "two armor lattices stack additively (3 + 3)")
    check(near(g.aura_regen, 20), "two regen totems stack additively (10 + 10)")
    check(near(s.aura_shield, 12), "two shield wardens take the strongest (max 12, not 24)")
  end

  -- combat integration (bare entity tables exercise the shared damage paths)
  do
    local e = { hp = 100, maxhp = 100, armor = 0, aura_armor = 4 }
    local _, applied = combat.apply_damage(e, 10)
    check(near(applied, 6), "aura armor reduces applied damage (10 - 4)")
  end
  do
    local e = { hp = 100, maxhp = 100, aura_shield = 12 }
    local _, applied = combat.apply_damage(e, 8)
    check(e.hp == 100 and near(e.aura_shield, 4) and near(applied, 8), "aura shield absorbs before hp")
  end
  do
    local e = { hp = 50, maxhp = 100, regen = 0, aura_regen = 10 }
    combat.tick_regen(e, 1.0)
    check(near(e.hp, 60), "aura regen heals through tick_regen (+10/s)")
  end

  -- stealth: a tower cannot target a stealthed enemy, but the veil itself is fair game
  do
    local r = clean()
    local veil = at(r, "veil", 200, 150)
    local hidden = at(r, "mote", 210, 150)
    tower.place(r, 200, 150, "pellet")
    aura.update(r)
    check(hidden.aura_stealth and not veil.aura_stealth, "veil stealths the pack, not itself")
    r.projectiles.n = 0
    local tw = r.towers[1]
    tw.cooldown = 0
    tower.update(r, 1 / 60)
    local hit_hidden, hit_veil = false, false
    for i = 1, r.projectiles.n do
      local tg = r.projectiles[i].target
      if tg == hidden then hit_hidden = true end
      if tg == veil then hit_veil = true end
    end
    check(not hit_hidden, "a tower cannot target a stealthed enemy")
    check(hit_veil, "the veil emitter is still targetable")
  end

  -- enemy.update runs the aura pass (a target near an emitter is buffed after a tick)
  do
    local r = clean()
    at(r, "lattice", 100, 100)
    local tgt = at(r, "mote", 108, 100)
    enemy.update(r, 1 / 60)
    check(near(tgt.aura_armor, 3), "enemy.update applies auras (armor lattice)")
  end

  -- a speed-buffed neighbor advances faster over one tick
  do
    local r = clean()
    at(r, "accelerant", 100, 100)
    local fast = at(r, "mote", 108, 100)
    fast.d = 10
    enemy.update(r, 1 / 60)
    local base = enemy.DEFS.mote.speed
    check(near(fast.d, 10 + base * 1.4 * (1 / 60)), "speed prism makes a neighbor move faster")
  end
end

return M

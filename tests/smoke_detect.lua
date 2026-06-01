-- Stealth detection cases (anti-veil): a tower with `def.detect` (the Pellet)
-- strips stealth from enemies within its effective range, marking them
-- `revealed` so EVERY tower -- not just the detector -- can acquire them this
-- frame. The reveal pass (tower.reveal) is pure geometry: no rng, recomputed
-- each frame (an enemy leaving every detector's radius re-cloaks), and a field
-- with no stealth reveals nothing (so a veil-free run is byte-identical). It
-- honours both M4 aura veils (aura_stealth) and M5 Veiled Pack (affix_stealth)
-- but never overrides a Specter anchor's arena untargetability. Run by smoke.lua
-- via M.run(check, near).

local meta     = require("lib.meta")
local run_mod  = require("lib.run")
local enemy    = require("lib.enemy")
local tower    = require("lib.tower")
local target   = require("lib.target")

local M = {}

-- Place a tower and return it (tower.place appends to run.towers).
local function place(run, x, y, kind)
  return tower.place(run, x, y, kind)
end

-- Spawn an enemy of `kind` and pin it at (x, y) (spawn derives x,y from path d;
-- the detection cases need exact positions relative to the towers).
local function at(run, kind, x, y)
  local e = enemy.spawn(run, kind, 1, 1, 0)
  e.x, e.y = x, y
  return e
end

-- Did any pooled projectile come from this tower this frame?
local function fired_from(run, tower_id)
  for i = 1, run.projectiles.n do
    if run.projectiles[i].tower_id == tower_id then return true end
  end
  return false
end

function M.run(check, near)
  local m = meta.default()

  -- ------------------------------------------------ API + data shape
  check(type(tower.reveal) == "function", "tower exposes a reveal pass")
  check(tower.DEFS.pellet.detect == true, "Pellet is flagged as a detector (data-driven)")
  check(not tower.DEFS.rail.detect, "Rail is not a detector")
  check(not tower.DEFS.splash.detect, "Splash is not a detector")

  -- ----------------- a detector reveals a cloaked enemy for ALL towers
  -- A detect Pellet + a non-detect Splash both sit near a cloaked ground mote.
  -- Neither can target it while cloaked; after reveal, the Splash (which has no
  -- detection of its own) can fire on it -- proving reveal is field-wide.
  local r = run_mod.new(m, 1, "serpentine"); r.money = 99999
  local pellet = place(r, 180, 150, "pellet")
  local splash = place(r, 212, 150, "splash")
  r.enemies.n = 0
  local mote = at(r, "mote", 206, 150)        -- in range of both, near the splash
  mote.aura_stealth = true                    -- M4 veil cloak
  check(not target.targetable(mote), "a cloaked enemy is untargetable before reveal")

  tower.reveal(r)
  check(mote.revealed == true, "a detector reveals a cloaked enemy in its range")
  check(target.targetable(mote), "a revealed enemy becomes targetable")
  check(pellet.revealing == true, "the detector reports it is actively revealing")

  r.projectiles.n = 0; splash.cooldown = 0; pellet.cooldown = 0
  tower.update(r, 1 / 60)
  check(fired_from(r, splash.id), "a NON-detect tower fires on an enemy a detector revealed")

  -- ------------------------------------ out of range stays cloaked
  local r2 = run_mod.new(m, 1, "serpentine"); r2.money = 99999
  local p2 = place(r2, 60, 60, "pellet")
  r2.enemies.n = 0
  local far = at(r2, "mote", 300, 200)        -- well beyond the pellet's range
  far.aura_stealth = true
  tower.reveal(r2)
  check(far.revealed == false, "a cloaked enemy outside every detector's range stays hidden")
  check(not target.targetable(far), "...and stays untargetable")
  check(p2.revealing == false, "a detector with nothing in range is not 'revealing'")

  -- ------------------------------------ reveal is recomputed every frame
  local r3 = run_mod.new(m, 1, "serpentine"); r3.money = 99999
  place(r3, 180, 150, "pellet")
  r3.enemies.n = 0
  local rover = at(r3, "mote", 200, 150)
  rover.aura_stealth = true
  tower.reveal(r3)
  check(rover.revealed == true, "in range -> revealed")
  rover.x, rover.y = 360, 240                 -- walk out of the detector's radius
  tower.reveal(r3)
  check(rover.revealed == false, "leaving every detector's radius re-cloaks the enemy")

  -- ------------------------------------ M5 affix cloak is also revealed
  local r4 = run_mod.new(m, 1, "serpentine"); r4.money = 99999
  place(r4, 180, 150, "pellet")
  r4.enemies.n = 0
  local packmate = at(r4, "mote", 200, 150)
  packmate.affix_stealth = true               -- Veiled Pack cloak
  tower.reveal(r4)
  check(packmate.revealed and target.targetable(packmate),
    "detection reveals an affix (Veiled Pack) cloak, not just the aura veil")

  -- --------------- a Specter anchor stays untargetable even if 'revealed'
  -- Arena untargetability (invulnerable phase anchors) outranks detection: a
  -- detector must never expose an anchor the boss design means to protect.
  local r5 = run_mod.new(m, 1, "serpentine"); r5.money = 99999
  place(r5, 180, 150, "pellet")
  r5.enemies.n = 0
  local anchor = at(r5, "mote", 200, 150)
  anchor.affix_stealth = true
  anchor.arena = { kind = "anchor", untargetable = true }
  tower.reveal(r5)
  check(not target.targetable(anchor),
    "an untargetable arena anchor is never exposed by detection")

  -- ------------------------------------ a non-detector cannot reveal
  local r6 = run_mod.new(m, 1, "serpentine"); r6.money = 99999
  place(r6, 180, 150, "splash")               -- Splash is not a detector
  r6.enemies.n = 0
  local hidden = at(r6, "mote", 200, 150)
  hidden.aura_stealth = true
  tower.reveal(r6)
  check(hidden.revealed == false and not target.targetable(hidden),
    "a field with no detector reveals nothing")

  -- ------------------------------------ no-stealth field is unaffected
  local r7 = run_mod.new(m, 1, "serpentine"); r7.money = 99999
  place(r7, 180, 150, "pellet")
  r7.enemies.n = 0
  local plain = at(r7, "mote", 200, 150)      -- not cloaked
  tower.reveal(r7)
  check(target.targetable(plain), "a normal (un-cloaked) enemy stays targetable through a reveal pass")
end

return M

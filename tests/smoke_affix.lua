-- Enemy affix cases (V2-M5): deterministic per-wave selection (gated by min_wave,
-- boss waves, and no_affixes), spawn-time DERIVED fields (no base-def mutation),
-- the Veiled Pack source / Overclock derived speed / Armored Front fraction / Fracture
-- split / Null Field resonance suppression, and the threat-preview + report
-- integration. Run by smoke.lua via M.run(check, near).

local C         = require("lib.const")
local meta      = require("lib.meta")
local run_mod   = require("lib.run")
local wave      = require("lib.wave")
local enemy     = require("lib.enemy")
local tower     = require("lib.tower")
local modifier  = require("lib.modifier")
local resonance = require("lib.resonance")
local affix     = require("lib.affix")
local threat    = require("lib.threat")
local report    = require("lib.report")
local target    = require("lib.target")
local harness   = require("tests.harness")

local M = {}

local function count_kind(run, kind)
  local n = 0
  for i = 1, run.enemies.n do if run.enemies[i].kind == kind then n = n + 1 end end
  return n
end

function M.run(check, near)
  local m = meta.default()

  -- ------------------------------------------------------ selection gating
  local r = run_mod.new(m, 1, "serpentine")
  check(affix.for_wave(r, 5) == nil, "no affix on a boss wave (5)")
  check(affix.for_wave(r, 7) == nil, "no affix before the earliest min_wave (8)")
  r.no_affixes = true
  check(affix.for_wave(r, 9) == nil, "no_affixes disables all affixes (balance baseline)")
  r.no_affixes = false
  local an
  for n = 8, 40 do if n % C.BOSS_EVERY ~= 0 and affix.for_wave(r, n) then an = n; break end end
  check(an ~= nil, "some non-boss wave >= 8 draws an affix")
  local r2 = run_mod.new(m, 1, "serpentine")
  check(affix.for_wave(r2, an) == affix.for_wave(r, an), "affix choice is deterministic for seed/wave")

  -- choose arms run.wave_affix + history
  local rc = run_mod.new(m, 1, "serpentine")
  affix.choose(rc, an)
  check(rc.wave_affix ~= nil and #rc.affix_history == 1, "choose arms the wave affix + records history")

  -- ----------------------------------------------- Armored Front (fraction)
  local ra = run_mod.new(m, 1, "serpentine"); ra.wave_affix = affix.DEFS.armored_front
  local armored = 0
  for idx = 1, 10 do
    ra.enemies.n = 0
    local e = enemy.spawn(ra, "mote", 1, 1, 0)
    affix.apply_spawn(ra, e, idx, 10)
    if e.armor > 0 then armored = armored + 1 end
  end
  check(armored == 3, "Armored Front armors exactly the vanguard fraction (ceil(10*0.25)=3)")
  check(enemy.DEFS.mote.armor == 0, "apply_spawn never mutates the base enemy def")

  -- ----------------------------------------------------------- Mirrored pairs
  check(affix.DEFS.mirrored ~= nil, "Mirrored affix is data-driven content")
  local rmir = run_mod.new(m, 9, "serpentine")
  rmir.wave_affix = affix.DEFS.mirrored
  wave.start(rmir, 8)
  local mirrored = true
  for i = 1, rmir.spawn_queue.n - 1, 2 do
    local a, b = enemy.DEFS[rmir.spawn_queue[i]], enemy.DEFS[rmir.spawn_queue[i + 1]]
    if not (a and b and a.fly ~= b.fly) then mirrored = false; break end
  end
  check(mirrored and rmir.spawn_queue.n >= 2, "Mirrored builds paired ground/flyer spawn sets")

  -- ------------------------------------------------------ Overclock (speed)
  local ro = run_mod.new(m, 1, "serpentine"); ro.wave_affix = affix.DEFS.overclock
  ro.affix_overclock_active = true
  ro.enemies.n = 0
  local oe = enemy.spawn(ro, "mote", 1, 1, 0)
  local base_speed = oe.base_speed
  affix.apply_spawn(ro, oe, 5, 10)                       -- not vanguard, but speed hits all
  check(near(oe.base_speed, base_speed), "Overclock does not mutate the enemy base speed")
  check(oe.affix_speed_mult ~= nil and near(oe.affix_speed_mult, 1.3),
    "Overclock applies a derived speed multiplier")
  local src = enemy.spawn(ro, "accelerant", 1, 1, 0)
  affix.apply_spawn(ro, src, 6, 10)
  enemy.kill(ro, src)
  check(ro.affix_overclock_active == false, "Overclock ends when the first aura emitter dies")

  -- ------------------------------------------- Veiled Pack (stealth source)
  local rv = run_mod.new(m, 1, "serpentine"); rv.money = 99999
  rv.wave_affix = affix.DEFS.veiled_pack
  tower.place(rv, 200, 150, "pellet")
  rv.enemies.n = 0
  local source = enemy.spawn(rv, "veil", 1, 1, 0); source.x, source.y = 205, 150
  affix.apply_spawn(rv, source, 1, 10)                   -- vanguard -> veil source
  local cloaked = enemy.spawn(rv, "mote", 1, 1, 0); cloaked.x, cloaked.y = 210, 150
  affix.apply_spawn(rv, cloaked, 2, 10)
  affix.update(rv, 0)
  check(source.affix_veil_source == true and target.targetable(source),
    "Veiled Pack creates a targetable veil source")
  check(cloaked.affix_stealth == true and not target.targetable(cloaked),
    "the veil source protects nearby pack enemies")
  rv.projectiles.n = 0; rv.towers[1].cooldown = 0
  tower.update(rv, 1 / 60)
  check(rv.projectiles.n >= 1, "a tower can shoot the veil source")
  source.dead = true
  affix.update(rv, 0)
  check(cloaked.affix_stealth == false, "Veiled Pack stealth drops when the source dies")
  rv.projectiles.n = 0; rv.towers[1].cooldown = 0
  tower.update(rv, 1 / 60)
  check(rv.projectiles.n >= 1, "the same enemy is targetable once un-cloaked")
  check(type(affix.draw) == "function", "affixes expose visible geometry overlays")
  if type(affix.draw) == "function" then
    source.dead = false
    affix.update(rv, 0)
    harness.reset_gfx()
    affix.draw(rv)
    check(#harness.gfx_calls() > 0, "affix.draw emits ring/icon geometry for affected enemies")
  end

  -- ----------------------------------------------------- Fracture (splits)
  local rf = run_mod.new(m, 1, "serpentine"); rf.wave_affix = affix.DEFS.fracture
  rf.enemies.n = 0
  local sp = enemy.spawn(rf, "splitter", 1, 1, 10)
  enemy.damage(rf, sp, 1e9)                              -- kill -> split
  check(count_kind(rf, "mote") == 1, "Fracture spawns one fewer child (2 -> 1)")
  local child
  for i = 1, rf.enemies.n do if rf.enemies[i].kind == "mote" then child = rf.enemies[i] end end
  check(child and near(child.maxhp, enemy.DEFS.mote.hp * 1.6), "Fracture children are tougher")
  local rf0 = run_mod.new(m, 2, "serpentine"); rf0.enemies.n = 0
  enemy.damage(rf0, enemy.spawn(rf0, "splitter", 1, 1, 10), 1e9)
  check(count_kind(rf0, "mote") == 2, "without Fracture a splitter spawns 2 children")

  -- ------------------------------------ Null Field (resonance suppression)
  local rn = run_mod.new(m, 1, "serpentine"); rn.money = 99999
  local t1 = tower.place(rn, 200, 150, "pellet"); modifier.socket_module(rn, t1, "triangle")
  tower.place(rn, 215, 150, "pellet"); modifier.socket_module(rn, rn.towers[2], "triangle")
  tower.place(rn, 200, 165, "pellet"); modifier.socket_module(rn, rn.towers[3], "triangle")
  resonance.update(rn)
  check(t1.resonance ~= nil, "Triad resonance forms before Null Field")
  rn.wave_affix = affix.DEFS.null_field
  rn.affix_null_active = true; rn.affix_timer = 10
  resonance.update(rn)
  check(t1.resonance == nil, "Null Field suppresses resonance")
  affix.update(rn, 11)                                   -- tick past the 10s duration
  check(rn.affix_null_active == false, "Null Field lapses after its duration")
  resonance.update(rn)
  check(t1.resonance ~= nil, "resonance restores once Null Field ends")

  -- ----------------------------------------- threat preview + report
  local tp = threat.preview(r, an)
  check(tp.affix ~= nil and tp.affix_id == affix.for_wave(r, an), "threat preview names the wave's affix")
  check(threat.preview(r, 5).affix == nil, "no affix on a boss-wave preview")
  local rr = run_mod.new(m, 1, "serpentine")
  rr.affix_history = { "armored_front", "overclock" }
  check(report.build(rr).affixes == 2, "report counts the affix-bearing waves survived")
end

return M

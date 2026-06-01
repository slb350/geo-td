-- Boss arena cases (V2-M6): final-boss scheduling, arena-object spawning (on the
-- route, stationary, scaled to the boss), the per-boss encounter effects (Bulwark
-- shield drop, Specter invuln counter, Lattice anchor gate, Hydra head adds),
-- targetability, the kill accounting, arena clear on boss death, and the report
-- stats. Run by smoke.lua via M.run(check, near).

local meta = require("lib.meta")
local run_mod = require("lib.run")
local boss = require("lib.boss")
local enemy = require("lib.enemy")
local tower = require("lib.tower")
local arena = require("lib.arena")
local aura = require("lib.aura")
local wave = require("lib.wave")
local report = require("lib.report")
local helpers = require("tests.helpers")

local M = {}

local function count_kind(r, kind)
  local n = 0
  for i = 1, r.enemies.n do
    if not r.enemies[i].dead and r.enemies[i].kind == kind then n = n + 1 end
  end
  return n
end

-- A fresh run with a freshly spawned boss of `kind` for boss wave n.
local function spawn(m, n, kind)
  local r = run_mod.new(m, n, "serpentine")
  r.money = 99999
  wave.boss_scale(r, n)
  r.enemies.n = 0
  boss.spawn(r, kind, r.hp_scale)
  return r
end

local function kill_arena(r)
  for i = 1, r.enemies.n do
    if r.enemies[i].arena then enemy.damage(r, r.enemies[i], 1e9) end
  end
end

function M.run(check, near)
  local m = meta.default()

  -- ----------------------------------------------- final-boss scheduling
  check(boss.for_wave(25) == "lattice", "wave 25 is the final-act boss (The Lattice)")
  check(boss.for_wave(5) == "prism" and boss.for_wave(20) == "specter", "the four-boss cycle holds at 5/20")
  check(boss.for_wave(30) ~= "lattice", "the normal cycle resumes after wave 25")
  check(boss.for_wave(50) == "lattice", "the final boss recurs every FINAL_BOSS_EVERY")

  -- ----------------------------------------------- arena objects spawn + place
  local rb = spawn(m, 10, "bulwark")
  check(arena.count(rb, "shield_battery") == 3, "Bulwark seeds 3 shield batteries at spawn")
  local battery
  for i = 1, rb.enemies.n do
    if rb.enemies[i].arena then
      battery = rb.enemies[i]
      break
    end
  end
  check(battery and helpers.in_field(battery.x, battery.y), "an arena object sits in the field")
  local d0 = battery.d
  enemy.update(rb, 0.5)
  check(battery.d == d0, "arena objects are stationary (never move)")
  check(near(battery.maxhp, rb.boss.maxhp * 0.12), "an arena object is scaled to the boss HP")

  -- --------------------------------- Bulwark: killing batteries drops the shield
  check(rb.boss.shield_max > 0, "Bulwark starts shielded")
  kill_arena(rb)
  boss.update(rb, 1 / 60)
  check(rb.boss.shield_max == 0 and rb.boss.shield == 0, "destroying every battery drops the Bulwark shield")
  check(rb.arena_kills == 3, "destroyed arena objects count toward arena_kills")
  check(rb.kills == 0, "arena objects are not normal kills")

  -- ----------------------------------- Lattice: invulnerable until anchors fall
  local rl = spawn(m, 25, "lattice")
  check(rl.final_boss_reached == true, "spawning the Lattice sets final_boss_reached")
  check(arena.count(rl, "lattice_anchor") == 5, "the Lattice seeds 5 anchors")
  local hp0 = rl.boss.hp
  local _, ap0 = boss.hurt(rl, 100)
  check(ap0 == 0 and rl.boss.hp == hp0, "the Lattice is invulnerable while anchors stand")
  kill_arena(rl)
  local _, ap1 = boss.hurt(rl, 100)
  check(ap1 > 0, "the Lattice is vulnerable once all anchors are destroyed")

  -- ------------------------------ Specter: anchors enable invuln counterplay
  local rs = spawn(m, 20, "specter")
  check(arena.count(rs, "phase_anchor") == 3, "Specter seeds 3 phase anchors")
  rs.boss.invuln_t = 5
  local _, sap = boss.hurt(rs, 50)
  check(sap > 0, "Specter is hittable during invuln while a phase anchor stands")
  kill_arena(rs)
  rs.boss.invuln_t = 5
  local _, sap2 = boss.hurt(rs, 50)
  check(sap2 == 0, "Specter is immune during invuln once the anchors are gone")

  -- ------------------------------------ targetability (untargetable anchors)
  local ru = run_mod.new(m, 5, "serpentine")
  ru.money = 99999
  local pel = tower.place(ru, 200, 150, "pellet")
  ru.enemies.n = 0
  local anchor = enemy.spawn(ru, "phase_anchor", 1, 1, 0)
  anchor.x, anchor.y = 205, 150
  anchor.arena = { kind = "phase_anchor", untargetable = true }
  ru.projectiles.n = 0
  pel.cooldown = 0
  tower.update(ru, 1 / 60)
  check(ru.projectiles.n == 0, "a tower skips an untargetable arena object")
  anchor.arena.untargetable = false
  ru.projectiles.n = 0
  pel.cooldown = 0
  tower.update(ru, 1 / 60)
  check(ru.projectiles.n >= 1 and ru.projectiles[1].target == anchor, "a targetable arena object is shot")

  -- ------------------------------------ Hydra heads emit adds (arena.update)
  local rh = spawn(m, 15, "hydra")
  check(arena.count(rh, "hydra_head") == 3, "Hydra seeds 3 heads")
  check(count_kind(rh, "swarm") == 0, "no head adds before arena.update")
  arena.update(rh, 2.5) -- past the 2.0s head interval
  check(count_kind(rh, "swarm") == 3, "each Hydra head emits an add via arena.update")

  -- --------------------------------------------- arena cleared on boss death
  local rc = spawn(m, 10, "bulwark")
  check(arena.count(rc, "shield_battery") == 3, "batteries present before the boss dies")
  boss.kill(rc)
  check(arena.count(rc, "shield_battery") == 0, "boss death clears the arena so the wave can finish")

  -- ----------------------- arena objects are not buffable by enemy auras
  -- (a veil cloaking a battery would block the destroy mechanic -- can happen if
  -- a boss wave is called early with a veil straggler still on the field)
  local rab = spawn(m, 10, "bulwark")
  local bat
  for i = 1, rab.enemies.n do
    if rab.enemies[i].arena then
      bat = rab.enemies[i]
      break
    end
  end
  local veil = enemy.spawn(rab, "veil", 1, 1, 0)
  veil.x, veil.y = bat.x, bat.y
  aura.update(rab)
  check(not bat.aura_stealth, "an enemy aura does not buff an arena object (stays targetable)")

  -- ----------------------------------------------------------- report
  local rr = run_mod.new(m, 8, "serpentine")
  rr.arena_kills = 4
  rr.final_boss_reached = true
  local rep = report.build(rr)
  check(rep.arena_kills == 4 and rep.final_boss == true, "report carries arena kills + final boss reached")
end

return M

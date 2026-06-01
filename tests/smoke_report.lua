-- Report + stat-instrumentation cases for the smoke suite (M1). Split out of
-- tests/smoke.lua so that file stays under the LOC soft limit. Loaded and run by
-- smoke.lua via M.run(check, near) AFTER the engine-stub harness + the scene
-- globals (State / SwitchScene / input) are installed, so these cases reuse the
-- same check counters and can drive the gameover scene.

local C        = require("lib.const")
local harness  = require("tests.harness")
local meta     = require("lib.meta")
local run_mod  = require("lib.run")
local enemy    = require("lib.enemy")
local tower    = require("lib.tower")
local proj     = require("lib.projectile")
local combat   = require("lib.combat")
local boss     = require("lib.boss")
local wave     = require("lib.wave")
local powerup  = require("lib.powerup")
local report   = require("lib.report")
local gameover = require("scenes.gameover")
local helpers  = require("tests.helpers")

local M = {}

local dummy = helpers.dummy                     -- durable stationary target
local fire_and_settle = helpers.fire_and_settle -- fire one shot, settle to impact

function M.run(check, near)
  local m = meta.default()

  -- ---------------------------------------------------- combat applied amount
  -- apply_damage returns (died, applied); applied = shield absorbed + the
  -- armor-reduced HP actually removed, capped at remaining HP (no overkill).
  local e1 = { hp = 5, maxhp = 5 }
  local died, ap = combat.apply_damage(e1, 10)
  check(died and near(ap, 5), "applied caps HP damage at remaining HP (no overkill credit)")

  local e2 = { hp = 100, maxhp = 100, armor = 4 }
  local _, ap2 = combat.apply_damage(e2, 10)
  check(near(ap2, 6), "applied counts armor-reduced HP removal (10 - 4)")

  local e3 = { hp = 100, maxhp = 100, shield = 8, shield_max = 8 }
  local _, ap3 = combat.apply_damage(e3, 5)
  check(near(ap3, 5) and e3.shield == 3, "applied counts shield absorbed, HP untouched")

  local e4 = { hp = 100, maxhp = 100, shield = 8, shield_max = 8 }
  local _, ap4 = combat.apply_damage(e4, 13)
  check(near(ap4, 13), "applied = shield absorbed + HP removed on overflow")

  local e5 = { hp = 100, maxhp = 100, armor = 50 }
  local _, ap5 = combat.apply_damage(e5, 10)
  check(near(ap5, 1), "applied respects the min-1 damage floor through heavy armor")

  -- ------------------------------------------------- projectile attribution
  local r = run_mod.new(m, 2, "serpentine"); r.money = 99999
  local pel = tower.place(r, 200, 150, "pellet")
  check(r.tower_stats[pel.id] and r.tower_stats[pel.id].damage == 0,
    "a freshly placed tower gets a zeroed stat entry keyed by id")
  r.enemies.n = 0
  dummy(r, 205, 150)
  fire_and_settle(r, pel)
  check(r.tower_stats[pel.id].damage > 0, "tower stat accrued applied damage from its shot")
  check(near(r.tower_stats[pel.id].damage, 9), "direct hit credits applied damage (pellet = 9)")

  -- sold tower's damage survives (kept on run.tower_stats, not the tower table)
  tower.sell(r, pel)
  check(r.tower_stats[pel.id].damage == 9, "selling a tower keeps its damage stat")
  local rep = report.build(r)
  check(rep.top_tower and rep.top_tower.kind == "pellet" and near(rep.top_tower.damage, 9),
    "report top-tower survives a sell")

  -- splash credits both the direct target and every splash victim to the source
  local rs = run_mod.new(m, 3, "serpentine"); rs.money = 99999
  local spl = tower.place(rs, 110, 95, "splash")
  rs.enemies.n = 0
  dummy(rs, 112, 96)   -- direct target
  dummy(rs, 116, 96)   -- inside splash radius
  fire_and_settle(rs, spl)
  check(near(rs.tower_stats[spl.id].damage, 12),
    "splash credits direct + splash applied to the source tower (6 + 6)")

  -- invulnerable boss hit credits nothing (boss.hurt returns 0 while phased out)
  local rb = run_mod.new(m, 4, "serpentine")
  wave.boss_scale(rb, 5); boss.spawn(rb, "prism", rb.hp_scale)
  rb.boss.invuln_t = 5
  local kb, apb = boss.hurt(rb, 100)
  check((not kb) and near(apb, 0), "an invulnerable boss hit reports 0 applied damage")

  -- a crit doubles the shot's damage before spawn; attribution reflects it
  local rc = run_mod.new(m, 12, "serpentine"); rc.money = 99999
  rc.mods.crit_chance = 1.0   -- chance(1.0) is always true (next() is always < 1)
  local cpel = tower.place(rc, 200, 150, "pellet")
  rc.enemies.n = 0
  dummy(rc, 205, 150)
  fire_and_settle(rc, cpel)
  check(near(rc.tower_stats[cpel.id].damage, 18), "a crit (9 x2) credits doubled applied damage")

  -- a tower sold while its shot is still in flight is still credited on impact,
  -- because tower_stats is keyed by id on the run, not held on the tower table
  local rf = run_mod.new(m, 13, "serpentine"); rf.money = 99999
  local fpel = tower.place(rf, 200, 150, "pellet")
  rf.enemies.n = 0
  dummy(rf, 205, 150)
  fpel.cooldown = 0
  tower.update(rf, 1 / 60)               -- spawn the projectile
  check(rf.projectiles.n >= 1, "a shot is in flight before the sell")
  tower.sell(rf, fpel)                   -- sell BEFORE the shot lands
  for _ = 1, 300 do
    if rf.projectiles.n == 0 then break end
    proj.update(rf, 1 / 60)
  end
  check(near(rf.tower_stats[fpel.id].damage, 9), "an in-flight shot credits its sold tower")

  -- splash credits post-armor applied damage per victim, just like a direct hit
  local ra = run_mod.new(m, 14, "serpentine"); ra.money = 99999
  local aspl = tower.place(ra, 110, 95, "splash")
  ra.enemies.n = 0
  dummy(ra, 112, 96)                     -- direct target, armor 0 -> 6
  local victim = dummy(ra, 116, 96); victim.armor = 2   -- splash victim, 6 - 2 -> 4
  fire_and_settle(ra, aspl)
  check(near(ra.tower_stats[aspl.id].damage, 10), "splash credits post-armor applied per victim (6 + 4)")

  -- ----------------------------------------------------------- leak counter
  local rl = run_mod.new(m, 5, "serpentine"); rl.lives = 50
  rl.enemies.n = 0
  local leaker = dummy(rl, 0, 0)
  leaker.d = rl.path.total_len
  local lives0 = rl.lives
  enemy.update(rl, 1 / 60)
  check(rl.leaked == 1, "a normal enemy leak increments run.leaked")
  check(rl.lives == lives0 - 1, "a normal leak costs one life")

  local rlb = run_mod.new(m, 6, "serpentine"); rlb.lives = 50
  wave.boss_scale(rlb, 5); boss.spawn(rlb, "prism", rlb.hp_scale)
  rlb.boss.d = rlb.path.total_len
  local bl0 = rlb.leaked
  boss.update(rlb, 1 / 60)
  check(rlb.leaked == bl0 + 1, "a boss leak increments run.leaked")
  check(rlb.lives == 45, "a boss leak keeps its 5-life penalty")

  -- ---------------------------------------------------------- money spent
  local rm = run_mod.new(m, 7, "serpentine"); rm.money = 99999
  local c1 = tower.cost(rm, "pellet")
  tower.place(rm, 200, 150, "pellet")
  check(rm.money_spent == c1, "tower placement adds gross cost to money_spent")
  local c2 = tower.cost(rm, "splash")
  tower.place(rm, 110, 95, "splash")
  check(rm.money_spent == c1 + c2, "money_spent accumulates across placements")
  local ms = rm.money_spent
  tower.sell(rm, rm.towers[#rm.towers])
  check(rm.money_spent == ms, "selling does not reduce money_spent (it is gross)")
  rm.phase = "combat"; rm.enemies.n = 0; dummy(rm, 200, 150); rm.money = 1000
  run_mod.orbital_strike(rm)
  check(rm.money_spent == ms + C.ORBITAL_COST, "orbital strike adds its cost to money_spent")

  -- money_spent records the discounted cost actually paid, not the raw def cost
  local rd = run_mod.new(m, 16, "serpentine"); rd.money = 99999
  rd.mods.cost_mult = 0.5
  local paid = tower.cost(rd, "pellet")
  tower.place(rd, 200, 150, "pellet")
  check(rd.money_spent == paid and paid < tower.DEFS["pellet"].cost,
    "money_spent records the cost_mult-discounted cost actually paid")

  -- ---------------------------------------------------------- report.build
  local r0 = run_mod.new(m, 8, "serpentine")
  local rep0 = report.build(r0)
  check(rep0.top_tower == nil, "report: nil top tower when nothing dealt damage")
  check(rep0.favorite == nil, "report: nil favorite with no powerups")
  check(rep0.kills == 0 and rep0.leaked == 0 and rep0.money_spent == 0,
    "report: counters default to zero")

  r0.powerups = { "dmg", "rate", "dmg", "rate" }   -- tie 2-2, dmg acquired first
  check(report.build(r0).favorite == "dmg", "report: favorite ties break to first-acquired")
  check(report.build(r0).favorite_name == powerup.DEFS["dmg"].name,
    "report: favorite carries the powerup display name")
  r0.powerups = { "rate", "dmg", "rate" }          -- rate is modal
  check(report.build(r0).favorite == "rate", "report: favorite is the modal powerup key")
  r0.powerups = { "range", "dmg", "rate" }         -- all distinct -> first acquired wins
  check(report.build(r0).favorite == "range", "report: all-distinct favorite is the first acquired")

  -- report.top_tower ranks the highest-damage entry across several towers
  local rt = run_mod.new(m, 15, "serpentine")
  rt.tower_stats = {
    [1] = { kind = "pellet", damage = 10 },
    [2] = { kind = "splash", damage = 40 },
    [3] = { kind = "frost", damage = 25 },
  }
  local tt = report.build(rt).top_tower
  check(tt and tt.kind == "splash" and near(tt.damage, 40),
    "report top-tower ranks the highest damage across towers")

  -- ----------------------------------------------------- gameover scene
  -- Reuses the global State / SwitchScene / input that smoke_core.lua installs.
  State.run = run_mod.new(State.meta, 9, "serpentine")
  State.run.final_wave = 12
  State.run.kills = 30
  State.run.leaked = 4
  State.run.money_spent = 640
  State.run.bosses_killed = 2
  State.run.score = 555
  State.run.powerups = { "dmg", "dmg", "rate" }
  State.run.tower_stats[1] = { kind = "pellet", damage = 123 }
  State.pending = nil
  gameover.init()
  local s = State.summary
  check(s ~= nil, "gameover produced a summary")
  check(s.wave == 12 and s.kills == 30 and s.leaked == 4, "summary carries instrumented counters")
  check(s.money_spent == 640 and s.bosses_killed == 2, "summary carries money spent + bosses")
  check(s.top_tower and s.top_tower.kind == "pellet", "summary carries the top tower")
  check(s.favorite == "dmg", "summary carries the favorite powerup")
  check(s.award ~= nil and s.bank ~= nil, "summary carries the meta award + bank total")

  gameover.update(1 / 60)   -- input is idle here, so it must not switch scenes
  check(State.pending == nil and State.run ~= nil, "gameover stays put without input")

  -- layout: every drawn row stays inside the screen panel
  harness.reset_gfx()
  gameover.draw(1 / 60)
  local calls = harness.gfx_calls()
  local rows = 0
  for i = 1, #calls do
    local c = calls[i]
    if c.fn == "text" or c.fn == "text_ex" then
      local text, x, y, scale = c.args[1], c.args[2], c.args[3], 1
      if c.fn == "text_ex" then scale = c.args[4] or 1 end
      local w, h = usagi.measure_text(text)
      w, h = w * scale, h * scale
      rows = rows + 1
      check(x >= 0 and x + w <= C.GAME_W, "gameover row fits horizontally: " .. text)
      check(y >= 0 and y + h <= C.GAME_H, "gameover row fits vertically: " .. text)
    end
  end
  check(rows >= 9, "gameover panel renders the full stat sheet")

  State.run = nil
  State.summary = nil
  State.pending = nil
end

return M

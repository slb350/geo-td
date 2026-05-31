-- M3 per-tower modifier cases: effective-stat stacking (base/global/upgrade/
-- module), cost + affordability gating, one-socket module rules, persistence
-- across a wave, the firing path reading per-tower effective stats, live-reload
-- resilience (the playtest crash), and inspect-panel hit-testing + layout fit.
-- Run by smoke.lua via M.run(check, near).

local C        = require("lib.const")
local harness  = require("tests.harness")
local meta     = require("lib.meta")
local tower    = require("lib.tower")
local proj     = require("lib.projectile")
local modifier = require("lib.modifier")
local inspect  = require("lib.inspect")
local helpers  = require("tests.helpers")

local M = {}
local dummy, settle = helpers.dummy, helpers.settle

function M.run(check, near)
  local m = meta.default()
  local function fresh(seed) return helpers.fresh(m, seed) end

  -- effective base == def * global mods (the behavior-preserving substrate)
  do
    local r = fresh()
    local t = tower.place(r, 200, 150, "pellet")
    local def = tower.DEFS.pellet
    local e = modifier.effective(r, t, {})
    check(near(e.damage, def.damage * r.mods.dmg_mult), "effective damage = def * global mod (no upgrades)")
    check(near(e.range, def.range * r.mods.range_mult), "effective range = def * global mod")
    check(near(e.fire_rate, def.fire_rate * r.mods.rate_mult), "effective fire_rate = def * global mod")
    check(e.crit == 0 and e.pierce == 0 and e.ricochet == 0, "no module = no behavior bonuses")
  end

  -- upgrades stack on base and global mods (base x global x upgrade)
  do
    local r = fresh()
    local t = tower.place(r, 200, 150, "pellet")
    local def = tower.DEFS.pellet
    modifier.buy_upgrade(r, t, "dmg")    -- level 1: +25%
    check(near(modifier.effective(r, t, {}).damage, def.damage * 1.25), "one dmg upgrade -> +25%")
    modifier.buy_upgrade(r, t, "dmg")    -- level 2: +50%
    check(near(modifier.effective(r, t, {}).damage, def.damage * 1.5), "two dmg upgrades stack to +50%")
    r.mods.dmg_mult = 2.0                 -- global mod multiplies on top
    check(near(modifier.effective(r, t, {}).damage, def.damage * 2.0 * 1.5),
      "global mod and per-tower upgrades multiply together")
  end

  -- each geometry module folds its effect (base x global x module)
  do
    local r = fresh()
    local def, ds = tower.DEFS.pellet, tower.DEFS.splash
    local tp = tower.place(r, 200, 150, "pellet"); modifier.socket_module(r, tp, "triangle")
    check(near(modifier.effective(r, tp, {}).crit, 0.25), "triangle module grants +25% crit")
    local tq = tower.place(r, 100, 95, "pellet"); modifier.socket_module(r, tq, "square")
    check(modifier.effective(r, tq, {}).pierce == 1, "square module grants pierce +1")
    local th = tower.place(r, 250, 200, "pellet"); modifier.socket_module(r, th, "hex")
    check(modifier.effective(r, th, {}).ricochet == 1, "hex module grants ricochet +1")
    local tc = tower.place(r, 60, 40, "pellet"); modifier.socket_module(r, tc, "circle")
    check(near(modifier.effective(r, tc, {}).range, def.range * r.mods.range_mult * 1.30),
      "circle module adds +30% range")
    local td = tower.place(r, 300, 60, "splash"); modifier.socket_module(r, td, "diamond")
    check(near(modifier.effective(r, td, {}).splash_radius, ds.splash_radius * r.mods.splash_mult * 1.50),
      "diamond module adds +50% splash")
  end

  -- cost scaling + affordability gating + max-level cap
  do
    local r = fresh(); r.money = 0
    local t = tower.place(r, 200, 150, "pellet")
    check(not modifier.can_buy_upgrade(r, t, "dmg"), "cannot buy an upgrade while broke")
    check(not modifier.buy_upgrade(r, t, "dmg"), "buy no-ops when unaffordable")
    check((t.upgrades.dmg or 0) == 0, "unaffordable buy left the level unchanged")
    r.money = 1000
    local def = modifier.UPDEFS.pellet[1]   -- the dmg line
    local c0 = modifier.upgrade_cost(def, 0)
    modifier.buy_upgrade(r, t, "dmg")
    check(t.upgrades.dmg == 1 and r.money == 1000 - c0, "buying spends the level-0 cost")
    check(modifier.upgrade_cost(def, 1) == def.base_cost * 2, "cost scales with level")
    for _ = 1, 10 do modifier.buy_upgrade(r, t, "dmg") end
    check(t.upgrades.dmg == def.max_level, "upgrade level caps at max_level")
    check(not modifier.can_buy_upgrade(r, t, "dmg"), "a maxed upgrade cannot be bought")
  end

  -- one module socket only, costs MODULE_COST
  do
    local r = fresh()
    local t = tower.place(r, 200, 150, "pellet")
    r.money = C.MODULE_COST   -- exactly enough to socket one module (set after placing)
    check(modifier.can_socket(r, t, "triangle"), "can socket with funds + empty socket")
    check(modifier.socket_module(r, t, "triangle") and r.money == 0, "socketing spends MODULE_COST")
    check(t.module == "triangle", "module recorded on the tower")
    r.money = 1000
    check(not modifier.can_socket(r, t, "square"), "cannot socket a second module")
    check(not modifier.socket_module(r, t, "square"), "second socket no-ops")
    check(t.module == "triangle", "the original module is unchanged")
  end

  -- per-tower upgrade state persists across a wave of simulation
  do
    local r = fresh()
    local t = tower.place(r, 200, 150, "pellet")
    modifier.buy_upgrade(r, t, "rate"); modifier.buy_upgrade(r, t, "dmg")
    r.enemies.n = 0; dummy(r, 210, 150)
    for _ = 1, 60 do tower.update(r, 1 / 60); proj.update(r, 1 / 60) end
    check(t.upgrades.rate == 1 and t.upgrades.dmg == 1, "per-tower upgrades persist across a wave")
    check(r.towers[1] == t, "the upgraded tower persists in run.towers")
  end

  -- firing path reads per-tower effective stats: a square module makes THIS
  -- tower's shots pierce, with no global pierce card set
  do
    local r = fresh()
    local t = tower.place(r, 200, 150, "pellet")
    modifier.socket_module(r, t, "square")   -- pierce +1
    r.enemies.n = 0
    local a = dummy(r, 210, 150)
    local b = dummy(r, 225, 150)             -- ahead, within chain range
    t.cooldown = 0; tower.update(r, 1 / 60); settle(r)
    check(a.hp < a.maxhp and b.hp < b.maxhp, "a square-module tower pierces to a second enemy (no global card)")
  end

  -- a crit module's bonus merges into the firing-path crit roll (module + global)
  do
    local r = fresh()
    local t = tower.place(r, 200, 150, "pellet")
    modifier.socket_module(r, t, "triangle")   -- +25% crit
    r.mods.crit_chance = 0.75                   -- +75% global -> total 1.0, always crits
    r.enemies.n = 0; dummy(r, 205, 150)
    t.cooldown = 0; tower.update(r, 1 / 60); settle(r)
    check(near(r.tower_stats[t.id].damage, 14), "crit module + global crit doubles damage in the firing path (7 -> 14)")
  end

  -- live-reload resilience: usagi dev preserves the run, so a tower placed before
  -- this module's fields existed can lack `upgrades`; effective must backfill,
  -- not crash (the exact playtest error: modifier.lua index nil 'upgrades').
  do
    local r = fresh()
    local legacy = { kind = "pellet", def = tower.DEFS.pellet }   -- no upgrades/module/eff
    local ok = pcall(function() return modifier.effective(r, legacy, {}) end)
    check(ok, "effective() tolerates a tower with no upgrades field (live-reload)")
    check(legacy.upgrades ~= nil, "effective() backfills the missing upgrades field")
    check(legacy.eff ~= nil, "effective() backfills the missing eff scratch (avoids per-frame alloc)")
  end

  -- inspect panel: button hit-testing + every drawn row fits on screen
  do
    local r = fresh()
    local t = tower.place(r, 200, 150, "pellet")
    local up = inspect.button_at(r, t, C.HUD_X + 11, 49)    -- inside upgrade row 1
    check(up and up.type == "upgrade", "inspect click in the upgrade area returns a buy action")
    local sock = inspect.button_at(r, t, C.HUD_X + 11, 137)  -- inside module row 1 (socket empty)
    check(sock and sock.type == "module", "inspect click in the module area returns a socket action")

    harness.reset_gfx()
    inspect.draw(r, t)
    local calls, rows = harness.gfx_calls(), 0
    for i = 1, #calls do
      local c = calls[i]
      if c.fn == "text" then
        local text, x, y = c.args[1], c.args[2], c.args[3]
        local w, h = usagi.measure_text(text)
        rows = rows + 1
        check(x >= 0 and x + w <= C.GAME_W, "inspect row fits horizontally: " .. text)
        check(y >= 0 and y + h <= C.GAME_H, "inspect row fits vertically: " .. text)
      end
    end
    check(rows >= 6, "inspect panel renders the upgrade + module rows")
  end
end

return M

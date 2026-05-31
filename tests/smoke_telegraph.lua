-- M5 boss telegraphs: shockwave / invuln / add-spawn warning windows precede the
-- effect (which still fires on the boss's existing cadence), and a phase change
-- fires a one-shot audio stinger. Run by smoke.lua via M.run(check, near).

local C       = require("lib.const")
local meta    = require("lib.meta")
local wave    = require("lib.wave")
local boss    = require("lib.boss")
local tower   = require("lib.tower")
local helpers = require("tests.helpers")

local M = {}

function M.run(check, near)
  local m = meta.default()
  local function fresh(seed) return helpers.fresh(m, seed) end
  -- a fresh run with one freshly-spawned boss of `kind`
  local function spawn_boss(kind)
    local r = fresh(); r.enemies.n = 0
    wave.boss_scale(r, 5)
    return r, boss.spawn(r, kind, r.hp_scale)
  end
  local IN_WINDOW = C.BOSS_TELEGRAPH * 0.5      -- a countdown inside the warning window
  local OUTSIDE = C.BOSS_TELEGRAPH + 1.0        -- well before the warning window

  -- shockwave: telegraph shows only in the warning window, fires only after it
  do
    local r, b = spawn_boss("prism")   -- prism has the shockwave
    local tw = tower.place(r, b.x, b.y, "pellet")  -- inside the shockwave radius
    b.shock_t = OUTSIDE
    boss.update(r, 1 / 60)
    check(not b.shock_warn, "no shockwave telegraph outside the warning window")
    check(tw.disabled_t == 0, "shockwave does not fire early")
    b.shock_t = IN_WINDOW
    boss.update(r, 1 / 60)
    check(b.shock_warn, "shockwave telegraph shows in the warning window")
    check(tw.disabled_t == 0, "shockwave has not fired yet (telegraph precedes it)")
    local fired = false
    for _ = 1, 120 do
      boss.update(r, 1 / 60)
      if tw.disabled_t > 0 then fired = true; break end
    end
    check(fired, "shockwave fires after the telegraph window")
    check(not b.shock_warn, "telegraph clears once the shockwave fires")
  end

  -- invulnerability: telegraph before the boss phases out
  do
    local r, b = spawn_boss("specter")   -- specter has invuln windows
    b.invuln_cd = IN_WINDOW
    boss.update(r, 1 / 60)
    check(b.invuln_warn, "invuln telegraph shows before the boss phases out")
    check(b.invuln_t == 0, "boss is not yet invulnerable during the telegraph")
    local went = false
    for _ = 1, 120 do
      boss.update(r, 1 / 60)
      if b.invuln_t > 0 then went = true; break end
    end
    check(went, "boss becomes invulnerable after the telegraph window")
    check(not b.invuln_warn, "invuln telegraph clears once invuln starts")
  end

  -- add spawn: portal telegraph before an add appears
  do
    local r, b = spawn_boss("hydra")   -- hydra spawns adds "always"
    b.spawn_t = IN_WINDOW
    boss.update(r, 1 / 60)
    check(b.spawn_warn, "add-spawn portal telegraph shows in the warning window")
    check(r.enemies.n == 0, "no add has spawned yet (telegraph precedes it)")
    local spawned = false
    for _ = 1, 120 do
      boss.update(r, 1 / 60)
      if r.enemies.n > 0 then spawned = true; break end
    end
    check(spawned, "an add spawns after the telegraph window")
    check(not b.spawn_warn, "portal telegraph clears once the add spawns")
  end

  -- phase change fires the audio stinger (spy the one-shot sfx call)
  do
    local r, b = spawn_boss("prism")
    local stung = nil
    local real_play = sfx.play
    sfx.play = function(name) stung = name end
    b.hp = b.maxhp * b.def.phase2_at      -- right at the phase-2 threshold
    boss.hurt(r, 1)                        -- a hit that crosses into phase 2
    check(b.phase == 2, "boss enters phase 2 at the threshold")
    check(stung == "boss_phase", "the phase change fires audio.stinger")
    -- and it fires exactly once: a second hit while already in phase 2 is silent
    local stung2 = nil
    sfx.play = function(name) stung2 = name end
    boss.hurt(r, 1)
    sfx.play = real_play
    check(stung2 == nil, "the stinger does not re-fire on subsequent phase-2 damage")
  end

  -- a boss with no shockwave/invuln/adds never raises any telegraph flag
  do
    local r, b = spawn_boss("bulwark")   -- bulwark has none of the three
    for _ = 1, 300 do boss.update(r, 1 / 60) end
    check(not b.shock_warn, "bulwark (no shockwave) never sets shock_warn")
    check(not b.invuln_warn, "bulwark (no invuln) never sets invuln_warn")
    check(not b.spawn_warn, "bulwark (no adds) never sets spawn_warn")
  end

  -- boundary: a countdown sitting exactly at C.BOSS_TELEGRAPH is inside the window
  -- (dt 0 recomputes the warn flag without drifting the countdown via float math)
  do
    local r, b = spawn_boss("prism")
    b.shock_t = C.BOSS_TELEGRAPH
    boss.update(r, 0)
    check(b.shock_warn, "the telegraph is inclusive of the C.BOSS_TELEGRAPH boundary (<=)")
  end
end

return M

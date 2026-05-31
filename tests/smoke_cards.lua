-- M2 behavior-card cases for the smoke suite: card application/describe,
-- pierce/ricochet chaining, brittle damage vs slowed targets, splash rings, and
-- flyer-death bursts (incl. recursion termination). Run by smoke.lua via
-- M.run(check, near) after the harness installs the engine-stub globals. Lives
-- apart from smoke.lua to keep each test file under the LOC soft limit.

local C       = require("lib.const")
local meta    = require("lib.meta")
local enemy   = require("lib.enemy")
local tower   = require("lib.tower")
local ring    = require("lib.ring")
local powerup = require("lib.powerup")
local helpers = require("tests.helpers")

local M = {}

local dummy = helpers.dummy     -- durable stationary target
local settle = helpers.settle   -- advance projectiles to impact

function M.run(check, near)
  local m = meta.default()
  local function fresh(seed) return helpers.fresh(m, seed) end

  -- ---------------------------------------------------------- card application
  do
    local r = fresh()
    powerup.apply(r, { key = "pierce", rarity = 3 })
    check(r.mods.pierce == 1, "pierce card sets mods.pierce = 1 (flat, not rarity-scaled)")
    powerup.apply(r, { key = "ricochet", rarity = 2 })
    check(r.mods.ricochet == 1, "ricochet card sets mods.ricochet = 1")

    local rb = fresh()
    powerup.apply(rb, { key = "brittle", rarity = 1 })
    check(near(rb.mods.brittle, 0.25), "brittle card (common) sets mods.brittle to its value")
    local rr = fresh()
    powerup.apply(rr, { key = "ring", rarity = 1 })
    check(near(rr.mods.ring, 0.5), "ring card sets mods.ring")
    local ra = fresh()
    powerup.apply(ra, { key = "airburst", rarity = 1 })
    check(near(ra.mods.flyer_burst, 0.5), "flak-burst card sets mods.flyer_burst")

    for _, k in ipairs({ "pierce", "ricochet", "brittle", "ring", "airburst" }) do
      local d = powerup.describe({ key = k, rarity = 2 })
      check(type(d) == "string" and #d > 0, "describe(" .. k .. ") returns text")
    end
    -- strong behavior cards are gated to higher rarities
    check(powerup.DEFS.pierce.min_rarity == 3, "pierce gated to Rare")
    check(powerup.DEFS.ricochet.min_rarity == 2, "ricochet gated to Uncommon+")
  end

  -- ---------------------------------------------------------- ricochet retargets
  do
    local r = fresh(2); r.mods.ricochet = 1
    local t = tower.place(r, 200, 150, "pellet")
    r.enemies.n = 0
    local a = dummy(r, 205, 150)
    local b = dummy(r, 215, 150)   -- within C.CHAIN_RANGE of a
    t.cooldown = 0; tower.update(r, 1 / 60)
    settle(r)
    check(a.hp < a.maxhp and b.hp < b.maxhp, "a ricochet shot damages two enemies")
    check(near(r.tower_stats[t.id].damage, 14), "both ricochet hits credit the source tower (7 + 7)")
  end

  -- ---------------------------------------------------------- pierce hits a line
  do
    local r = fresh(3); r.mods.pierce = 1
    local t = tower.place(r, 200, 150, "pellet")
    r.enemies.n = 0
    local a = dummy(r, 210, 150)   -- first, to the right of the tower
    local b = dummy(r, 225, 150)   -- second, further right (ahead of the heading)
    t.cooldown = 0; tower.update(r, 1 / 60)
    settle(r)
    check(a.hp < a.maxhp and b.hp < b.maxhp, "a pierce shot hits two enemies in a line")
  end

  -- pierce with nothing ahead: hits once, finds no chain target, dies cleanly
  do
    local r = fresh(31); r.mods.pierce = 1
    local t = tower.place(r, 200, 150, "pellet")
    r.enemies.n = 0; dummy(r, 205, 150)   -- the only enemy
    t.cooldown = 0; tower.update(r, 1 / 60); settle(r)
    check(near(r.tower_stats[t.id].damage, 7), "pierce with no target ahead hits once")
    check(r.projectiles.n == 0, "pierce shot with nothing ahead expires cleanly")
  end

  -- ricochet runs out of targets mid-chain: 2 bounces but only 2 enemies present
  do
    local r = fresh(32); r.mods.ricochet = 2
    local t = tower.place(r, 200, 150, "pellet")
    r.enemies.n = 0; dummy(r, 205, 150); dummy(r, 214, 150)
    t.cooldown = 0; tower.update(r, 1 / 60); settle(r)
    check(near(r.tower_stats[t.id].damage, 14), "ricochet=2 with two enemies hits both then stops")
    check(r.projectiles.n == 0, "ricochet shot expires when out of fresh targets")
  end

  -- chain hits compose with brittle: a ricochet onto slowed enemies boosts both
  do
    local r = fresh(33); r.mods.ricochet = 1; r.mods.brittle = 0.5
    local t = tower.place(r, 200, 150, "pellet")
    r.enemies.n = 0
    local a = dummy(r, 205, 150); enemy.slow(a, 0.5, 5)
    local b = dummy(r, 215, 150); enemy.slow(b, 0.5, 5)
    t.cooldown = 0; tower.update(r, 1 / 60); settle(r)
    check(near(r.tower_stats[t.id].damage, 21), "brittle applies to each chained hit on slowed enemies (10.5 + 10.5)")
  end

  -- a chained shot must obey the firing tower's targeting rules: a ground-only
  -- tower's chain cannot hop to a flyer
  do
    local r = fresh(40); r.mods.ricochet = 1
    local t = tower.place(r, 200, 150, "frost")   -- ground-only, no splash to muddy it
    r.enemies.n = 0
    dummy(r, 205, 150)                              -- ground direct target
    local fly = enemy.spawn(r, "wisp", 20, 1, 5); fly.x, fly.y = 214, 150
    fly.armor, fly.shield, fly.shield_max = 0, 0, 0
    local fly_hp0 = fly.hp
    t.cooldown = 0; tower.update(r, 1 / 60); settle(r)
    check(fly.hp == fly_hp0, "a ground-only tower's chain does not hop to a flyer")
  end

  -- a chained shot cannot hop to a stealthed enemy (the veil hides it from chains too)
  do
    local r = fresh(41); r.mods.ricochet = 1
    local t = tower.place(r, 200, 150, "pellet")
    r.enemies.n = 0
    dummy(r, 205, 150)
    local hidden = dummy(r, 214, 150); hidden.aura_stealth = true
    local hp0 = hidden.hp
    t.cooldown = 0; tower.update(r, 1 / 60); settle(r)
    check(hidden.hp == hp0, "a chained shot does not hop to a stealthed enemy")
  end

  -- ----------------------------------------------------- pooled field reset
  do
    -- fire a chaining shot, let it settle (pool emptied), then fire a clean shot
    -- reusing the same recycled table -- it must carry no leftover chain state.
    local r = fresh(4); r.mods.ricochet = 2
    local t = tower.place(r, 200, 150, "pellet")
    r.enemies.n = 0; dummy(r, 205, 150); dummy(r, 214, 150); dummy(r, 223, 150)
    t.cooldown = 0; tower.update(r, 1 / 60); settle(r)
    check(r.projectiles.n == 0, "chaining shot settled, pool emptied")

    r.mods.ricochet = 0
    r.enemies.n = 0; dummy(r, 205, 150)
    t.cooldown = 0; tower.update(r, 1 / 60)
    check(r.projectiles.n >= 1, "fresh shot spawned reusing the pool")
    local p = r.projectiles[1]
    check(p.chain == 0, "pooled projectile reset chain to 0 with no chain mods")
    check(next(p.hits) == nil, "pooled projectile reset its hit-set")
  end

  -- ---------------------------------------------------------- brittle
  do
    local r = fresh(5); r.mods.brittle = 0.5
    local t = tower.place(r, 200, 150, "pellet")
    r.enemies.n = 0
    local e = dummy(r, 205, 150)
    enemy.slow(e, 0.5, 5)   -- slowed -> brittle applies
    t.cooldown = 0; tower.update(r, 1 / 60); settle(r)
    check(near(r.tower_stats[t.id].damage, 10.5), "brittle: slowed target takes 7 x1.5 = 10.5")
  end
  do
    local r = fresh(6); r.mods.brittle = 0.5
    local t = tower.place(r, 200, 150, "pellet")
    r.enemies.n = 0; dummy(r, 205, 150)   -- NOT slowed
    t.cooldown = 0; tower.update(r, 1 / 60); settle(r)
    check(near(r.tower_stats[t.id].damage, 7), "brittle does nothing to an unslowed target")
  end

  -- ---------------------------------------------------------- splash ring
  do
    local r = fresh(7)
    r.enemies.n = 0
    local e = dummy(r, 100, 100)
    r.tower_stats[7] = { kind = "splash", damage = 0 }   -- a stat entry to credit
    ring.spawn(r, 100, 100, { radius = 20, damage = 5, tower_id = 7 })
    check(r.rings.n == 1, "ring.spawn adds a ring to the pool")
    for _ = 1, C.RING_TICKS * math.ceil(C.RING_INTERVAL * 60) + 10 do ring.update(r, 1 / 60) end
    check(r.rings.n == 0, "ring expires after exactly its ticks")
    check(e.hp < e.maxhp, "ring damaged the enemy in its radius")
    check(near(r.tower_stats[7].damage, 5 * C.RING_TICKS), "ring credits each tick to its tower")
  end
  do
    local r = fresh(8); r.mods.ring = 0.5
    local t = tower.place(r, 110, 95, "splash")
    r.enemies.n = 0; dummy(r, 112, 96)
    t.cooldown = 0; tower.update(r, 1 / 60); settle(r)
    check(r.rings.n >= 1, "a splash shot with the ring card leaves a ring")
  end
  -- a ring credits its tower even after the tower is sold (stat persists by id)
  do
    local r = fresh(17)
    local t = tower.place(r, 110, 95, "splash"); local tid = t.id
    tower.sell(r, t)
    r.enemies.n = 0; dummy(r, 100, 100)
    ring.spawn(r, 100, 100, { radius = 25, damage = 5, tower_id = tid })
    for _ = 1, C.RING_TICKS * math.ceil(C.RING_INTERVAL * 60) + 10 do ring.update(r, 1 / 60) end
    check(near(r.tower_stats[tid].damage, 5 * C.RING_TICKS), "a ring credits its sold tower's stat")
  end
  -- a ring tick can kill an enemy; split children spawned mid-tick are NOT hit
  -- that same tick (the loop limit is captured before the loop)
  do
    local r = fresh(18)
    r.enemies.n = 0
    local sp = enemy.spawn(r, "splitter", 1, 1, 10); sp.x, sp.y = 100, 100
    ring.spawn(r, 100, 100, { radius = 30, damage = 50, tower_id = nil })   -- 50 > splitter 42 hp
    ring.update(r, C.RING_INTERVAL + 0.01)   -- one tick fires
    check(sp.dead, "a ring tick can kill an enemy in its radius")
    check(r.enemies.n == 3, "split children spawned but were not processed in the killing tick")
  end
  -- brittle reaches ring ticks too (the bonus lives at enemy.damage, not the
  -- projectile), so a ring pulsing a slowed enemy does extra damage
  do
    local r = fresh(19); r.mods.brittle = 1.0   -- +100% to slowed
    r.enemies.n = 0
    local e = dummy(r, 100, 100); enemy.slow(e, 0.5, 5)
    r.tower_stats[5] = { kind = "splash", damage = 0 }
    ring.spawn(r, 100, 100, { radius = 20, damage = 5, tower_id = 5 })
    ring.update(r, C.RING_INTERVAL + 0.01)   -- one tick: 5 x (1 + 1.0) = 10
    check(near(r.tower_stats[5].damage, 10), "brittle boosts a ring tick on a slowed enemy")
  end

  -- ---------------------------------------------------------- flyer burst
  do
    local r = fresh(9); r.mods.flyer_burst = 0.5
    r.enemies.n = 0
    local a = enemy.spawn(r, "wisp", 1, 1, 5); a.x, a.y = 100, 100
    local b = enemy.spawn(r, "wisp", 1, 1, 5); b.x, b.y = 110, 100   -- within C.FLYER_BURST_R
    local b_hp0 = b.hp
    enemy.kill(r, a)
    check(a.dead, "the flyer was killed")
    check(near(b_hp0 - b.hp, a.maxhp * 0.5), "a dying flyer bursts neighbors for maxhp x fraction")
    check(next(r.tower_stats) == nil, "flyer-burst damage is attributed to no tower")
  end
  do
    -- a burst big enough to kill the neighbor must not recurse forever
    local r = fresh(10); r.mods.flyer_burst = 5
    r.enemies.n = 0
    local a = enemy.spawn(r, "wisp", 1, 1, 5); a.x, a.y = 100, 100
    local b = enemy.spawn(r, "wisp", 1, 1, 5); b.x, b.y = 110, 100
    enemy.kill(r, a)
    check(a.dead and b.dead, "a lethal burst kills the neighbor without infinite recursion")
  end

  -- ground enemies do not burst
  do
    local r = fresh(11); r.mods.flyer_burst = 0.5
    r.enemies.n = 0
    local g = dummy(r, 100, 100)        -- ground hulk
    local n = dummy(r, 110, 100)
    local n_hp0 = n.hp
    enemy.kill(r, g)
    check(n.hp == n_hp0, "a dying ground enemy does not trigger the flyer burst")
  end
end

return M

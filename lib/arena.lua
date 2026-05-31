-- Boss arenas (V2-M6): each boss wave gets destructible "arena" objects placed on
-- the route, so a boss becomes a designed encounter instead of a scaled HP bar.
-- Arena objects are modelled as STATIONARY enemies (in run.enemies, tagged
-- e.arena = {kind, untargetable}) -- so the existing targeting + projectile +
-- splash pipeline handles them for free, no special firing-path code. They never
-- move or leak (lib/enemy skips that for e.arena) and grant no split.
--
-- Boss effects read the LIVE count of an arena kind (M.count scans run.enemies, so
-- it is correct however an object dies -- tower, splash, orbital), not a cached
-- tally that could drift:
--   Bulwark shield_battery  -> killing all drops the boss shield (drop_shield)
--   Hydra   hydra_head      -> each head spawns swarm adds until killed
--   Specter phase_anchor    -> while any stands, the boss is hittable during invuln
--   Prism   prism_mirror    -> decoys that draw tower fire (a target-priority test)
--   Lattice lattice_anchor  -> the boss is INVULNERABLE until all are destroyed
--
-- Objects are seeded at boss spawn or on the phase-2 transition (spawn_at) and
-- vaporized when the boss dies (M.clear), so they never block the wave clear.

local C     = require("lib.const")
local path  = require("lib.path")
local enemy = require("lib.enemy")

local M = {}

-- Spawn boss b's arena objects (if its def has an `arena` of this spawn phase).
-- They are placed evenly along the route, scaled to a fraction of the boss HP.
function M.spawn_for(run, b, phase)
  local a = b.def.arena
  if not a or a.spawn_at ~= phase then return end
  local total = run.path.total_len
  for i = 1, a.count do
    local x, y = path.point_at(run.path, total * i / (a.count + 1))
    local e = enemy.spawn(run, a.kind, 1, 1, 0)
    e.maxhp = b.maxhp * a.hp_mult
    e.hp = e.maxhp
    e.x, e.y = x, y
    e.base_speed = 0
    e.arena = { kind = a.kind, untargetable = a.untargetable == true }
    if a.head_spawn_every then
      e.arena.head_every = a.head_spawn_every
      e.arena.head_timer = a.head_spawn_every
    end
  end
end

-- Live count of arena objects of `kind` (scans run.enemies, so it is always right
-- regardless of how an object died). Read by lib/boss for the encounter effects.
function M.count(run, kind)
  local n, list = 0, run.enemies
  for i = 1, list.n do
    local e = list[i]
    if not e.dead and e.arena and e.arena.kind == kind then n = n + 1 end
  end
  return n
end

-- Per-frame arena behaviour: Hydra heads emit swarm adds until killed. From
-- lib/loop (combat only); a no-op on waves with no arena objects.
function M.update(run, dt)
  local list = run.enemies
  local i = 1
  while i <= list.n do
    local e = list[i]
    local ar = e.arena
    if ar and ar.head_every and not e.dead then
      ar.head_timer = ar.head_timer - dt
      if ar.head_timer <= 0 then
        ar.head_timer = ar.head_every
        enemy.spawn(run, "swarm", run.hp_scale * C.BOSS_ADD_HP_MULT, run.speed_scale, 0)
      end
    end
    i = i + 1
  end
end

-- Vaporize every arena object (on boss death), so they don't block the wave clear.
function M.clear(run)
  local list = run.enemies
  for i = 1, list.n do
    if list[i].arena then enemy.vaporize(list[i]) end
  end
end

-- Faint link lines from each arena object to the boss + a marker ring, so the
-- encounter reads clearly (which objects feed the boss). Dim for the CRT bloom.
function M.draw(run)
  local b = run.boss
  if not b or b.dead then return end
  local list = run.enemies
  for i = 1, list.n do
    local e = list[i]
    if e.arena and not e.dead then
      gfx.line(e.x, e.y, b.x, b.y, gfx.COLOR_DARK_PURPLE)
      gfx.circ(e.x, e.y, (e.size or 6) + 3, gfx.COLOR_PINK)
    end
  end
end

return M

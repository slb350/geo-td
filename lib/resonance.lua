-- Tower resonance (V2-M4): socketed geometry modules form CIRCUITS. A tower gains
-- a resonance "proof" when the required module shapes are present within a radius
-- of it (its own module + neighbors'), optionally gated to a tower kind. Named
-- proofs are mixed-shape patterns near a specific tower (Delta Chain = triangle +
-- hex near Pellet); matching circuits are N of one shape near any tower (Triad =
-- three triangles). Effects fold into modifier.effective as the LAST layer (base
-- -> global -> upgrade -> module -> resonance), reusing the existing crit / pierce
-- / ricochet plumbing -- so resonance creates new BEHAVIOUR, not just bigger
-- numbers, and a run with no modules is byte-identical.
--
-- Module ids ARE the shape names used in `requires` (triangle/square/circle/hex/
-- diamond -- see modifier.MODULES). Resonance is DERIVED: recomputed only when the
-- tower topology changes (run.resonance_dirty), never per frame.

local M = {}

local DEFS = usagi.read_json("resonance.json")
M.DEFS = DEFS
-- fixed application order (JSON keys are unordered) for deterministic name lists
M.ORDER = { "delta_chain", "orbit_field", "diamond_wake", "green_vector", "triad", "lattice" }

-- The largest proof radius, so the build overlay's link range tracks the data.
local MAX_RADIUS = 0
for _, R in pairs(DEFS) do
  if R.radius > MAX_RADIUS then MAX_RADIUS = R.radius end
end

-- The module shapes present within `radius` of tower t (its own + neighbours').
local function shapes_within(run, t, radius)
  local r2 = radius * radius
  local have = {}
  local towers = run.towers
  for i = 1, #towers do
    local o = towers[i]
    if o.module then
      local dx, dy = o.x - t.x, o.y - t.y
      if dx * dx + dy * dy <= r2 then have[o.module] = (have[o.module] or 0) + 1 end
    end
  end
  return have
end

-- Does the shape multiset `have` satisfy resonance R's `requires`?
local function satisfies(have, R)
  local need = {}
  for i = 1, #R.requires do
    need[R.requires[i]] = (need[R.requires[i]] or 0) + 1
  end
  for shape, n in pairs(need) do
    if (have[shape] or 0) < n then return false end
  end
  return true
end

local function accumulate(t, R)
  local res = t.resonance
  if not res then
    res = {
      crit = 0,
      pierce = 0,
      ricochet = 0,
      range = 0,
      splash = 0,
      dmg = 0,
      slow_aura = 0,
      ring_extra = 0,
      mark = 0,
      names = {},
    }
    t.resonance = res
  end
  local e = R.effect
  res.crit = res.crit + (e.crit or 0)
  res.pierce = res.pierce + (e.pierce or 0)
  res.ricochet = res.ricochet + (e.ricochet or 0)
  res.range = res.range + (e.range or 0)
  res.splash = res.splash + (e.splash or 0)
  res.dmg = res.dmg + (e.dmg or 0)
  res.slow_aura = res.slow_aura + (e.slow_aura or 0) -- Orbit Field aura radius (M4)
  res.ring_extra = res.ring_extra + (e.ring_extra or 0) -- Diamond Wake extra ring ticks
  res.mark = res.mark + (e.mark or 0) -- Green Vector mark amount
  res.names[#res.names + 1] = R.name
end

-- Recompute every tower's resonance, but only when the topology changed
-- (run.resonance_dirty). Treats nil as dirty so a live-reloaded pre-M4 run
-- self-heals on first touch. O(towers^2 * proofs), and only on change.
function M.update(run)
  -- Null Field affix (M5): circuits go dark for its duration. Clear all resonance
  -- and keep dirty so it recomputes the moment the affix lapses (affix.update).
  if run.affix_null_active then
    local towers = run.towers
    for i = 1, #towers do
      towers[i].resonance = nil
    end
    run.resonance_dirty = true
    return
  end
  if run.resonance_dirty == false then return end
  run.resonance_dirty = false
  local towers = run.towers
  for i = 1, #towers do
    towers[i].resonance = nil
  end
  for i = 1, #towers do
    local t = towers[i]
    for k = 1, #M.ORDER do
      local R = DEFS[M.ORDER[k]]
      if (not R.tower or R.tower == t.kind) and satisfies(shapes_within(run, t, R.radius), R) then accumulate(t, R) end
    end
  end
end

-- Build-phase overlay: links between moduled towers, lit where a resonance is
-- active. Drawn dim so the CRT bloom lifts it. Cheap (a few line/circ per tower).
function M.draw(run)
  local towers = run.towers
  for i = 1, #towers do
    local t = towers[i]
    if t.module then
      gfx.circ(t.x, t.y, 4, gfx.COLOR_PINK)
      for j = i + 1, #towers do
        local o = towers[j]
        if o.module then
          local dx, dy = o.x - t.x, o.y - t.y
          if dx * dx + dy * dy <= MAX_RADIUS * MAX_RADIUS then
            local lit = (t.resonance ~= nil) or (o.resonance ~= nil)
            gfx.line(t.x, t.y, o.x, o.y, lit and gfx.COLOR_PINK or gfx.COLOR_DARK_PURPLE)
          end
        end
      end
    end
    if t.resonance then gfx.circ(t.x, t.y, 8, gfx.COLOR_PINK) end
  end
end

return M

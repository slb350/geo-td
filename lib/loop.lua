-- Canonical per-frame combat step: the ONE definition of the update order
-- (spawns -> enemies -> boss -> towers -> projectiles -> splash rings) shared by
-- the game scene, the headless sim, and the test fixtures, so the sequence can't
-- drift between "the real game" and "what balance measures".
--
-- This is a leaf orchestrator: it requires the systems it drives, and none of
-- them require it back. The combat step can't live in lib/run.lua because the
-- systems it orchestrates (tower/projectile/ring) themselves require run -- that
-- is exactly why a dedicated module is the right home.

local wave  = require("lib.wave")
local enemy = require("lib.enemy")
local boss  = require("lib.boss")
local tower = require("lib.tower")
local proj  = require("lib.projectile")
local ring  = require("lib.ring")

local M = {}

-- Advance one combat frame. Returns true once the wave's spawn queue is drained
-- (boss waves carry no queue, so they are always "done" spawning).
function M.step(run, dt)
  local boss_wave = wave.is_boss_for(run, run.wave_index)
  local spawns_done = boss_wave or wave.update(run, dt)
  enemy.update(run, dt)
  if boss_wave then boss.update(run, dt) end
  tower.update(run, dt)
  proj.update(run, dt)
  ring.update(run, dt)
  return spawns_done
end

return M

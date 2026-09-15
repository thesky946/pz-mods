package.path = package.path .. ';../42/media/lua/shared/?.lua'
local mod = require 'MMACombat_Shared'
assert(mod.ID == 'MMACombat')

local kick = require 'MMACombat_SpinningKick'

assert(kick.ITEM_FULL_TYPE == 'Base.BareHands')
assert(kick.STATIONARY.maxDamage == 1.2)
assert(kick.STATIONARY.swingAnim == 'Shove')

local clip = assert(io.open('../common/media/anims_X/Bob/Bob_Shove.X', 'r'))
local clipText = clip:read('*a')
clip:close()
assert(clipText:find('AnimationSet Bob_Shove', 1, true))
-- The authored clip is frames 1..40 at the PZ export tick spacing (6,400).
assert(clipText:find('6400;4;', 1, true))
print('ALL TESTS PASSED')

package.path = package.path .. ';../42/media/lua/shared/?.lua'
local mod = require 'MMACombat_Shared'
assert(mod.ID == 'MMACombat')
print('ALL TESTS PASSED')

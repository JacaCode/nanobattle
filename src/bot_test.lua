local client = require "client"

function client.Bot:init()
    self.frame = 0
    self.bot_move = "+"
end

function client.Bot:turn(bx, by, bd, gd, rd, rv, es)
    self.bot_rot = self.frame < 10 and "+" or "="
    self.rad_rot = self.frame % 10 < 2 and "-" or "="
    self.gun_rot = self.frame % 20 < 2 and "+" or "="
    self.gun_fire = self.frame % 25 == 0 and "+" or "="
    self.frame = (self.frame + 1) % 100
end

local bot = client.new_bot("127.0.0.1", 1700)
local id = bot:join(arg[1])
assert(id ~= nil, "name already in use")
if id == 6 then
    bot:end_group()
end
bot:run()

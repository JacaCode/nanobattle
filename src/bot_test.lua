local client = require "client"

function client.Bot:init()
    self.frame = 0
    self.bot_move = "+"
end

function client.Bot:turn(bx, by, bd, gd, rd, rv, es)
    if self.frame < 10 then
        self.bot_rot = "+"
    else
        self.bot_rot = "="
    end
    self.frame = (self.frame + 1) % 100
end

local bot = client.new_bot("127.0.0.1", 1700)
local id = bot:join(arg[1])
assert(id ~= nil, "name already in use")
if id == 6 then
    bot:end_group()
end
bot:run()

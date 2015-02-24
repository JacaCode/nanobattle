local client = require "client"

function client.Bot:init()
    math.randomseed(os.time() + self.id)
    self.frame = math.random(100)
    self.rot_length = 0
    self.rot_dir = "="
    self.bot_move = "+"
end

function client.Bot:turn(bx, by, bd, gd, rd, rv, es)
    if self.frame == 0 then
        self.rot_length = math.random(20)
    end
    if self.frame % 10 == 0 then
        self.rot_dir = ({"-", "+"})[math.random(2)]
    end
    self.bot_rot = self.frame < self.rot_length and self.rot_dir or "="
    self.rad_rot = self.frame % 10 < 2 and "-" or "="
    self.rad_cal = ({"-", "=", "+"})[math.random(3)]
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

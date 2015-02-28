package.path = package.path .. ";../src/?.lua"

local client = require "client"

local function hypot(dx, dy)
    return math.sqrt(dx*dx + dy*dy)
end

function client.Bot:random_target()
    local margin = 2*self.r
    repeat
        self.tx = math.random(margin, self.w-margin)
        self.ty = math.random(margin, self.h-margin)
    until hypot(self.tx-self.x, self.ty-self.y) > 100
end

function client.Bot:direction_target(d)
    local margin = 2*self.r
    local c, s = math.cos(math.rad(d)), math.sin(math.rad(d))
    local rx, ry
    if c < 0 then
        rx = (margin - self.x) / c
    else
        rx = (self.w-margin - self.x) / c
    end
    if s < 0 then
        ry = (margin - self.y) / s
    else
        ry = (self.h-margin - self.y) / s
    end
    local r = math.min(rx, ry) * math.random()
    self.tx = self.x + r * c
    self.ty = self.y + r * s
end

function client.Bot:follow()
    local fx = self.x + math.cos(math.rad(self.d)) * self.r
    local fy = self.y + math.sin(math.rad(self.d)) * self.r
    local sa = (self.x-self.tx) * (fy-self.y) - (self.x-fx) * (self.ty-self.y)
    if math.abs(sa) < 200 then
        self.bot_rot = "="
    else
        self.bot_rot = sa < 0 and "-" or "+"
    end
    return hypot(self.tx-self.x, self.ty-self.y)
end

function client.Bot:init(w, h, r, n)
    math.randomseed(os.time() + self.id)
    self.frame = 0
    self.w, self.h, self.r = w, h, r
    self.tx, self.ty = w/2, h/2
    self.bot_move = "+"
    self.dd = ({-90, 90})[math.random(2)]
    self.direction = ({"-", "+"})[math.random(2)]
    self.e = 100
end

function client.Bot:turn(bx, by, bd, gd, rd, rv, es)
    if bx == self.x and by == self.y then
        self:random_target()
    end
    self.x, self.y, self.d = bx, by, bd
    if self:follow() < 2*self.r then
        self:random_target()
    end
    local e = es[self.id]
    if rv == 0 then
        self.action = "="
        self.rad_rot = self.direction
        self.gun_rot = self.direction
        self.dd = ({-135, 135})[math.random(2)]
    else
        self.action = "+"
        self.rad_rot = "="
        self.gun_rot = "="
        if e < 50 then
            self:direction_target(rd+self.dd)
        else
            self:direction_target(rd)
        end
    end
    self.frame = self.frame + 1
    if self.frame == 200 then
        self.action = "+"
        self.frame = 0
    end
    if e < self.e then
        self.action = "+"
        self.e = e
    end
end

local bot = client.new_bot("127.0.0.1", 1700)
local id = bot:join(arg[1])
assert(id ~= nil, "name already in use")
bot:run()

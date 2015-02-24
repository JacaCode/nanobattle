package.path = package.path .. ";../lib/?.lua;../lib/?/init.lua"

local ffi = require "ffi"
local nn = require "nanomsg"

local len = 256
local buf = ffi.new("char[?]", len)

local function get_nums(str)
    local nums = {}
    for s in string.gmatch(str, "-?%d+") do
        nums[#nums+1] = tonumber(s)
    end
    return unpack(nums)
end

local Bot = {}
Bot.__index = Bot

local function new_bot(ip, port)
    local bot = {
        ip = ip, port = port,
        bot_rot = "=", bot_move = "=",
        gun_rot = "=", gun_fire = "=",
        rad_rot = "=", rad_cal = "="
    }
    return setmetatable(bot, Bot)
end

function Bot:request(req)
    local err, sock, rc, size, rep
    local url = "tcp://"..self.ip..":"..tostring(self.port)

    sock, err = nn.socket(nn.REQ)
    assert(sock, nn.strerror(err))
    rc, err = sock:connect(url)
    assert(rc ~= nil, nn.strerror(err))
    size, err = sock:send(req, #req)
    assert(size ~= nil, nn.strerror(err))
    size, err = sock:recv(buf, len)
    assert(size ~= nil, nn.strerror(err))
    return ffi.string(buf, size)
end

function Bot:join(name)
    local err, rc
    local rep = self:request(name)
    if rep == "DUPLICATE" then
        return nil
    end
    self.id, self.name = tonumber(rep), name
    local url = "tcp://"..self.ip..":"..tostring(self.port+self.id)
    self.sock, err = nn.socket(nn.REP)
    assert(self.sock, nn.strerror(err))
    rc, err = self.sock:connect(url)
    assert(rc ~= nil, nn.strerror(err))
    return self.id
end

function Bot:end_group()
    assert(self:request("ENDGROUP") == "OK")
end

function Bot:run()
    local err, size
    size, err = self.sock:recv(buf, len)
    assert(size ~= nil, nn.strerror(err))
    local w, h, n = get_nums(ffi.string(buf, size))
    if self.init ~= nil then
        self:init(w, h, n)
    end
    size, err = self.sock:send("OK", 2)
    assert(size ~= nil, nn.strerror(err))
    while true do
        size, err = self.sock:recv(buf, len)
        assert(size ~= nil, nn.strerror(err))
        local s1, s2 = string.match(ffi.string(buf, size), "([^\n]*)\n(.*)")
        local bx, by, bd, gd, rd, rv = get_nums(s1)
        local es = {}
        for e in string.gmatch(s2, "-?%d+") do
            es[#es+1] = tonumber(e)
        end
        self:turn(bx, by, bd, gd, rd, rv, es)
        local msg = (
            self.bot_rot..self.bot_move..self.gun_rot ..
            self.gun_fire..self.rad_rot..self.rad_cal
        )
        size, err = self.sock:send(msg, #msg)
        assert(size ~= nil, nn.strerror(err))
    end
end

return {new_bot = new_bot, Bot = Bot}

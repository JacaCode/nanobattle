package.path = package.path .. ";../lib/?.lua;../lib/?/init.lua"

local ffi = require "ffi"
local nn = require "nanomsg"

local len = 256
local buf = ffi.new("char[?]", len)

local function get_nums(str, n)
    local num = "(-?%d+)"
    local pattern = string.rep(num.." ", n-1)..num
    return string.match(str, pattern)
end

local Bot = {}
Bot.__index = Bot

local function new_bot(ip, port)
    return setmetatable({ip = ip, port = port}, Bot)
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
    local w, h, n = get_nums(ffi.string(buf, size), 3)
    if self.init ~= nil then
        self:init(w, h, n)
    end
    size, err = self.sock:send("OK", 2)
    assert(size ~= nil, nn.strerror(err))
    while true do
        size, err = self.sock:recv(buf, len)
        assert(size ~= nil, nn.strerror(err))
        local s1, s2 = string.match(ffi.string(buf, size), "([^\n]*)\n(.*)")
        local bx, by, bd, gd, rd, rv = get_nums(s1, 6)
        local es = {}
        for e in string.gmatch(s2, "-?%d+") do
            es[#es+1] = tonumber(e)
        end
        local msg = self:turn(bx, by, bd, gd, rd, rv, es)
        size, err = self.sock:send(msg, #msg)
        assert(size ~= nil, nn.strerror(err))
    end
end

return {new_bot = new_bot, Bot = Bot}

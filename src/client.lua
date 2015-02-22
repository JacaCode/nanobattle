package.path = package.path .. ";../lib/?.lua;../lib/?/init.lua"

local ffi = require "ffi"
local nn = require "nanomsg"

local len = 256
local buf = ffi.new("char[?]", len)

local Client = {}
Client.__index = Client

local function new_client(ip, port)
    return setmetatable({ip = ip, port = port}, Client)
end

function Client:request(req)
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

function Client:join(name)
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

function Client:end_group()
    assert(self:request("ENDGROUP") == "OK")
end

function Client:control_loop()
    local err, size
    size, err = self.sock:recv(buf, len)
    assert(size ~= nil, nn.strerror(err))
    size, err = self.sock:send("OK", 2)
    assert(size ~= nil, nn.strerror(err))
    while true do
        size, err = self.sock:recv(buf, len)
        assert(size ~= nil, nn.strerror(err))
        size, err = self.sock:send("++====", 6)
        assert(size ~= nil, nn.strerror(err))
    end
end

local client = new_client("127.0.0.1", 1700)
local id = client:join(arg[1])
assert(id ~= nil, "name already in use")
if id == 6 then
    client:end_group()
end
client:control_loop()

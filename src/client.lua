package.path = package.path .. ";../lib/?.lua;../lib/?/init.lua"

local ffi = require "ffi"
local nn = require "nanomsg"

local len = 256
local buf = ffi.new("char[?]", len)

local function request(ip, port, req)
    local err, sock, rc, size, rep
    local url = "tcp://"..ip..":"..tostring(port)

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

local function join(ip, port, name)
    local err, sock, rc
    local rep = request(ip, port, name)
    assert(rep ~= "DUPLICATE")
    local id = tonumber(rep)
    local url = "tcp://"..ip..":"..tostring(port+id)
    sock, err = nn.socket(nn.REP)
    assert(sock, nn.strerror(err))
    rc, err = sock:connect(url)
    assert(rc ~= nil, nn.strerror(err))
    return sock, id
end

local function end_group(ip, port)
    assert(request(ip, port, "ENDGROUP") == "OK")
end

local function control_loop(sock)
    local err, size
    size, err = sock:recv(buf, len)
    assert(size ~= nil, nn.strerror(err))
    size, err = sock:send("OK", 2)
    assert(size ~= nil, nn.strerror(err))
    while true do
        size, err = sock:recv(buf, len)
        assert(size ~= nil, nn.strerror(err))
        size, err = sock:send("++====", 6)
        assert(size ~= nil, nn.strerror(err))
    end
end

local ip = "127.0.0.1"
local port = 1700
local sock, id = join(ip, port, arg[1])
if id == 5 then
    end_group(ip, port)
end
control_loop(sock)

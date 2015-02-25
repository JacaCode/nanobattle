package.path = package.path .. ";../lib/?.lua;../lib/?/init.lua"

local ffi = require "ffi"
local nn = require "nanomsg"

local len = 256
local buf = ffi.new("char[?]", len)

local err, rc, sock, size

local url = "tcp://127.0.0.1:1800"

sock, err = nn.socket(nn.SUB)
assert(sock, nn.strerror(err))
rc, err = sock:setsockopt(nn.SUB, nn.SUB_SUBSCRIBE, "", 0)
assert(rc == 0, nn.strerror(err))
rc, err = sock:connect(url)
assert(rc ~= nil, nn.strerror(err))

while true do
    size, err = sock:recv(buf, len)
    assert(size ~= nil, nn.strerror(err))
    io.write(ffi.string(buf, size).."\n")
end

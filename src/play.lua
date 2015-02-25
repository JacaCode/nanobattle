package.path = package.path .. ";../lib/?.lua;../lib/?/init.lua"

local ffi = require "ffi"
local nn = require "nanomsg"

ffi.cdef[[
void Sleep(int ms);
int poll(struct pollfd *fds, unsigned long nfds, int timeout);
]]

local sleep
if ffi.os == "Windows" then
  function sleep(s)
    ffi.C.Sleep(s*1000)
  end
else
  function sleep(s)
    ffi.C.poll(nil, 0, s*1000)
  end
end

local err, rc, sock, size

local url = "tcp://127.0.0.1:1800"

sock, err = nn.socket(nn.PUB)
assert(sock, nn.strerror(err))
rc, err = sock:bind(url)
assert(rc ~= nil, nn.strerror(err))

local fps = tonumber(arg[1]) or 60

for msg in io.lines() do
    size, err = sock:send(msg, #msg)
    assert(size ~= nil, nn.strerror(err))
    if string.sub(msg, 1, 1) == "!" then
        sleep(1/fps)
    end
end

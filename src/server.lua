package.path = package.path .. ";../lib/?.lua;../lib/?/init.lua"

local ffi = require "ffi"
local nn = require "nanomsg"

local len = 256
local buf = ffi.new("char[?]", len)

local WIN_WIDTH, WIN_HEIGHT = 800, 600
local STEP = 2
local BOT_RADIUS = 20
local BULLET_RADIUS = 4
local RADAR_AREA = 5000
local RADAR_MIN_RADIUS = math.sqrt(2*RADAR_AREA/math.pi)
local RADAR_MAX_RADIUS = math.sqrt(2*RADAR_AREA/(math.pi/60))

local MAX_CLIENTS = tonumber(arg[1]) or 6

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

local function set_radar_angle(bot, angle)
    bot.rad_angle = angle
    bot.rad_radius = math.sqrt(2*RADAR_AREA/angle)
end

local function set_radar_radius(bot, radius)
    bot.rad_radius = radius
    bot.rad_angle = 2*RADAR_AREA/(radius*radius)
end

local function bind(port, protocol)
    local err, sock, rc
    local url = "tcp://127.0.0.1:"..tostring(port)
    sock, err = nn.socket(protocol)
    assert(sock, nn.strerror(err))
    rc, err = sock:bind(url)
    assert(rc ~= nil, nn.strerror(err))
    return sock
end

local function timeout(sock, ms)
    local err, rc
    local ptimeout = ffi.new("int[1]", ms)
    rc, err = sock:setsockopt(
        nn.SOL_SOCKET, nn.RCVTIMEO, ptimeout, ffi.sizeof(ptimeout)
    )
    assert(rc == 0, nn.strerror(err))
end

local function request(sock, msg)
    local err, size
    size, err = sock:send(msg, #msg)
    assert(size ~= nil, nn.strerror(err))
    size, err = sock:recv(buf, len)
    assert(size ~= nil, nn.strerror(err))
    return ffi.string(buf, size)
end

local Server = {}
Server.__index = Server

local function new_server(port, width, height)
    local view = bind(port+100, nn.PUB)
    return setmetatable({
        port = port, view = view,
        width = width, height = height
    }, Server)
end

function Server:publish(msg)
    local err, size
    size, err = self.view:send(msg, #msg)
    assert(size ~= nil, nn.strerror(err))
end

function Server:get_group()
    local err, sock, rc, size, msg

    sock = bind(self.port, nn.REP)
    timeout(sock, 100)

    local n = 0
    local group = {}
    local group_open = true
    while group_open and n < MAX_CLIENTS do
        size, err = sock:recv(buf, len)
        assert(size ~= nil, nn.strerror(err))
        if size > 0 then
            local name = ffi.string(buf, size)
            if name == "ENDGROUP" then
                group_open = false
                print("end group")
                msg = "OK"
            elseif group[name] == nil then
                n = n + 1
                group[name] = n
                print(name.." joined")
                msg = tostring(n)
            else
                print("duplicate "..name)
                msg = "DUPLICATE"
            end
            size, err = sock:send(msg, #msg)
            assert(size ~= nil, nn.strerror(err))
        end
    end
    self.names = {}
    for name, id in pairs(group) do
        self.names[id] = name
    end
    msg = string.format(
        "%d %d %d %d %d",
        WIN_WIDTH, WIN_HEIGHT,
        BOT_RADIUS, BULLET_RADIUS,
        RADAR_AREA
    )
    self:publish(msg)
end

function Server:init_bots()
    local err, size, msg
    msg = string.format("%d %d %d", self.width, self.height, #self.names)
    self.bots = {}
    for id = 1, #self.names do
        local bot = {
            cx = math.random(BOT_RADIUS, self.width-BOT_RADIUS),
            cy = math.random(BOT_RADIUS, self.height-BOT_RADIUS),
            dir = math.random()*2*math.pi,
            gun_dir = math.random()*2*math.pi,
            rad_dir = math.random()*2*math.pi,
            energy = 100
        }
        set_radar_radius(bot, 8*BOT_RADIUS)
        print("waiting for "..self.names[id])
        bot.sock = bind(self.port+id, nn.REQ)
        assert(request(bot.sock, msg) == "OK")
        self.bots[id] = bot
    end
end

function Server:update_bot(id, cmd)
    local bot = self.bots[id]
    local idx = {}
    idx['-'] = 1
    idx['='] = 2
    idx['+'] = 3
    local rot = ({-1, 0, 1})[idx[string.sub(cmd, 1, 1)]]
    local vel = ({-0.5, 0, 1})[idx[string.sub(cmd, 2, 2)]]
    local gun_rot = ({-1, 0, 1})[idx[string.sub(cmd, 3, 3)]]
    local action = ({-1, 0, 1})[idx[string.sub(cmd, 4, 4)]]
    local rad_rot = ({-1, 0, 1})[idx[string.sub(cmd, 5, 5)]]
    local rad_cal = ({-4, 0, 4})[idx[string.sub(cmd, 6, 6)]]
    bot.cx = bot.cx + vel * STEP * math.cos(bot.dir)
    bot.cy = bot.cy + vel * STEP * math.sin(bot.dir)
    bot.cx = math.max(BOT_RADIUS, math.min(self.width-BOT_RADIUS, bot.cx))
    bot.cy = math.max(BOT_RADIUS, math.min(self.height-BOT_RADIUS, bot.cy))
    bot.dir = bot.dir + rot * STEP * math.pi / 30
    bot.gun_dir = bot.gun_dir + gun_rot * STEP * math.pi / 30
    bot.rad_dir = bot.rad_dir + rad_rot * STEP * math.pi / 30
    local radius = bot.rad_radius + rad_cal * STEP
    radius = math.max(RADAR_MIN_RADIUS, radius)
    radius = math.min(RADAR_MAX_RADIUS, radius)
    set_radar_radius(bot, radius)
end

function Server:update_view()
    local err, size, msg
    msg = string.format("%d %d", #self.bots, 0)
    self:publish(msg)
    for id = 1, #self.bots do
        local bot = self.bots[id]
        msg = string.format(
            "%d %d %d %d %d %d %d",
            bot.cx, bot.cy, math.deg(bot.dir),
            math.deg(bot.gun_dir),
            math.deg(bot.rad_dir), bot.rad_radius,
            bot.energy
        )
        self:publish(msg)
    end
end

function Server:control_loop()
    local size, err, msg, cmd
    local running = true
    while running do
        local energies = ""
        for id = 1, #self.bots do
            local bot = self.bots[id]
            energies = string.format("%s %d", energies, bot.energy)
        end
        for id = 1, #self.bots do
            local bot = self.bots[id]
            msg = string.format("%d %d ", bot.cx, bot.cy)
            msg = msg..string.format("%d ", math.deg(bot.dir))
            msg = msg..string.format("%d ", math.deg(bot.gun_dir))
            msg = msg..string.format("%d ", math.deg(bot.rad_dir))
            msg = msg..string.format("%d\n", 0)..energies
            cmd = request(bot.sock, msg)
            self:update_bot(id, cmd)
        end
        self:update_view()
        sleep(0.01)
    end
end

math.randomseed(os.time())
local server = new_server(1700, WIN_WIDTH, WIN_HEIGHT)
server:get_group()
server:init_bots()
server:control_loop()

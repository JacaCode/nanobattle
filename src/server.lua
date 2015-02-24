package.path = package.path .. ";../lib/?.lua;../lib/?/init.lua"

local ffi = require "ffi"
local nn = require "nanomsg"

local len = 256
local buf = ffi.new("char[?]", len)

local WIN_WIDTH, WIN_HEIGHT = 900, 600
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

local function disk_collision(x1, y1, r1, x2, y2, r2)
    local dx, dy = x2-x1, y2-y1
    local d = math.sqrt(dx*dx + dy*dy)
    return d < r1+r2
end

local function line_collision(x1, y1, x2, y2, x, y, r)
    -- compute the projection P of (x, y) on the line.
    local dx, dy = x2-x1, y2-y1
    local s = (dx * (y-y1) + dy * (x1-x)) / (dx*dx + dy*dy)
    local px, py = x + dy * s, y - dx * s
    -- check if P is inside the bounding box of the line segment.
    local inside = (
        math.min(x1, x2) < px and px < math.max(x1, x2) and
        math.min(y1, y2) < py and py < math.max(y1, y2)
    )
    -- compute the distance between the disk center and the segment,
    local dist
    if inside then
        -- dist = distance between (x, y) and P
        local dx, dy = x-px, y-py
        dist = math.sqrt(dx*dx + dy*dy)
    else
        -- dist = distance between (x, y) and its closest segment endpoint
        local dx1, dy1 = x-x1, y-y1
        local d1 = math.sqrt(dx1*dx1 + dy1*dy1)
        local dx2, dy2 = x-x2, y-y2
        local d2 = math.sqrt(dx2*dx2 + dy2*dy2)
        dist = math.min(d1, d2)
    end
    return dist < r
end

local function radar_collision(rad_x, rad_y, rad_r, rad_d, rad_a, x, y, r)
    -- check if disk intersects radar disk.
    if disk_collision(rad_x, rad_y, rad_r, x, y, r) then
        -- check if disk intersects either of radar segments.
        local left_angle = rad_d - rad_a/2
        local left_x = rad_x + rad_r * math.cos(left_angle)
        local left_y = rad_y + rad_r * math.sin(left_angle)
        if line_collision(rad_x, rad_y, left_x, left_y, x, y, r) then
            return true
        end
        local right_angle = rad_d + rad_a/2
        local right_x = rad_x + rad_r * math.cos(right_angle)
        local right_y = rad_y + rad_r * math.sin(right_angle)
        if line_collision(rad_x, rad_y, right_x, right_y, x, y, r) then
            return true
        end
        -- check if disk center is within radar angle range:
        --  let C be the center of the radar;
        --  let L & R be the left & right segment endpoints of the radar;
        --  let D be the center of the disk;
        --  the disk center is within radar angle range iif the signed areas
        --  of triangles CLD and CRD are positive and negative, respectively.
        -- here the shoelace formula is used to get the doubled signed area.
        local cld = (rad_x - x) * (left_y - rad_y) - (rad_x - left_x) * (y - rad_y)
        local crd = (rad_x - x) * (right_y - rad_y) - (rad_x - right_x) * (y - rad_y)
        if cld > 0 and crd < 0 then
            return true
        end
    end
    return false
end

local function shield_collision(sx, sy, sd, sa, x, y)
    local left_angle = sd - sa/2
    local left_x = sx + math.cos(left_angle)
    local left_y = sy + math.sin(left_angle)
    local right_angle = sd + sa/2
    local right_x = sx + math.cos(right_angle)
    local right_y = sy + math.sin(right_angle)
    local cld = (sx - x) * (left_y - sy) - (sx - left_x) * (y - sy)
    local crd = (sx - x) * (right_y - sy) - (sx - right_x) * (y - sy)
    return cld > 0 and crd < 0
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
end

function Server:init_bots()
    local err, size, msg
    msg = string.format(
        "%d %d %d %d",
        self.width, self.height, BOT_RADIUS, #self.names
    )
    self.bots = {}
    self.energies = {}
    for i = 1, #self.names do
        local dir = math.random()*2*math.pi
        local bot = {
            cx = math.random(BOT_RADIUS, self.width-BOT_RADIUS),
            cy = math.random(BOT_RADIUS, self.height-BOT_RADIUS),
            dir = dir, gun_dir = dir, rad_dir = dir,
            energy = 100, wait = 0, shield = 0, id = i
        }
        set_radar_radius(bot, 8*BOT_RADIUS)
        bot.sock = bind(self.port+i, nn.REQ)
        assert(request(bot.sock, msg) == "OK")
        self.bots[i] = bot
        self.energies[i] = bot.energy
    end
    self.bullets = {}
end

function Server:fire(bot)
    self.bullets[#self.bullets+1] = {
        cx = bot.cx + math.cos(bot.gun_dir) * BOT_RADIUS,
        cy = bot.cy + math.sin(bot.gun_dir) * BOT_RADIUS,
        dir = bot.gun_dir, id = bot.id
    }
end

function Server:hit(bullet, bot)
    local damage = 10
    if bot.shield > 0 then
        if shield_collision(
            bot.cx, bot.cy, bot.rad_dir, bot.rad_angle,
            bullet.cx, bullet.cy
        ) then
            damage = 3
        end
    end
    bot.energy = math.max(0, bot.energy - damage)
    self.energies[bot.id] = bot.energy
    if bot.energy == 0 then
        -- give energy boost to killer bot.
        for i = 1, #self.bots do
            local other = self.bots[i]
            if other.id == bullet.id then
                other.energy = math.min(100, other.energy+10)
                break
            end
        end
    end
end

function Server:update_bullets()
    local new_bullets = {}
    for i = 1, #self.bullets do
        local bullet = self.bullets[i]
        bullet.cx = bullet.cx + 2 * STEP * math.cos(bullet.dir)
        bullet.cy = bullet.cy + 2 * STEP * math.sin(bullet.dir)
        local active = (
            bullet.cx >= 0 and bullet.cx <= WIN_WIDTH and
            bullet.cy >= 0 and bullet.cy <= WIN_HEIGHT
        )
        if active then
            local new_bots = {}
            for j = 1, #self.bots do
                local bot = self.bots[j]
                local alive = true
                if bot.id ~= bullet.id then
                    if disk_collision(
                        bullet.cx, bullet.cy, BULLET_RADIUS,
                        bot.cx, bot.cy, BOT_RADIUS
                    ) then
                        active = false
                        self:hit(bullet, bot)
                        if bot.energy == 0 then
                            alive = false
                        end
                    end
                end
                if alive then
                    new_bots[#new_bots+1] = bot
                end
            end
            self.bots = new_bots
        end
        if active then
            new_bullets[#new_bullets+1] = bullet
        end
    end
    self.bullets = new_bullets
end

function Server:update_bot(bot, cmd)
    local idx = {}
    idx['-'] = 1
    idx['='] = 2
    idx['+'] = 3
    local state = {}
    for i = 1, 6 do
        state[i] = idx[string.sub(cmd, i, i)]
    end
    local rot = ({-1, 0, 1})[state[1]]
    local vel = ({-0.5, 0, 1})[state[2]]
    local gun_rot = ({-1, 0, 1})[state[3]]
    local action = ({-1, 0, 1})[state[4]]
    local rad_rot = ({-1, 0, 1})[state[5]]
    local rad_cal = ({-4, 0, 4})[state[6]]
    local cx, cy
    cx = bot.cx + vel * STEP * math.cos(bot.dir)
    cy = bot.cy + vel * STEP * math.sin(bot.dir)
    cx = math.max(BOT_RADIUS, math.min(self.width-BOT_RADIUS, cx))
    cy = math.max(BOT_RADIUS, math.min(self.height-BOT_RADIUS, cy))
    local ok = true
    for i = 1, #self.bots do
        local other = self.bots[i]
        if other.id ~= bot.id then
            if disk_collision(
                other.cx, other.cy, BOT_RADIUS,
                cx, cy, BOT_RADIUS
            ) then
                ok = false
                break
            end
        end
    end
    if ok then
        bot.cx, bot.cy = cx, cy
    end
    bot.dir = (bot.dir + rot * STEP * math.pi / 30) % (2 * math.pi)
    bot.gun_dir = (bot.gun_dir + gun_rot * STEP * math.pi / 30) % (2 * math.pi)
    bot.rad_dir = (bot.rad_dir + rad_rot * STEP * math.pi / 30) % (2 * math.pi)
    local radius = bot.rad_radius + rad_cal * STEP
    radius = math.max(RADAR_MIN_RADIUS, radius)
    radius = math.min(RADAR_MAX_RADIUS, radius)
    set_radar_radius(bot, radius)
    if bot.wait > 0 then
        bot.wait = bot.wait - 1
    else
        bot.shield = 0
        if action == 1 then
            self:fire(bot)
            bot.wait = 50
        elseif action == -1 then
            bot.shield = 1
            bot.wait = 50
        end
    end
end

function Server:update_radars()
    for i = 1, #self.bots do
        local bot = self.bots[i]
        local visible = 0
        for j = 1, #self.bots do
            if j ~= i then
                local other = self.bots[j]
                if radar_collision(
                    bot.cx, bot.cy, bot.rad_radius,
                    bot.rad_dir, bot.rad_angle,
                    other.cx, other.cy, BOT_RADIUS
                ) then
                    visible = visible + 1
                end
            end
        end
        bot.visible = visible
    end
end

function Server:update_view()
    local err, size, msg
    msg = string.format(
        "! %d %d %d %d %d %d %d",
        WIN_WIDTH, WIN_HEIGHT,
        BOT_RADIUS, BULLET_RADIUS,
        RADAR_AREA, #self.bots, #self.bullets
    )
    self:publish(msg)
    for i = 1, #self.bots do
        local bot = self.bots[i]
        msg = string.format(
            "%d %d %d %d %d %d %d %d %d %d %d",
            bot.id, bot.cx, bot.cy, math.deg(bot.dir),
            math.deg(bot.gun_dir), bot.wait, bot.shield,
            math.deg(bot.rad_dir), bot.rad_radius,
            bot.visible, bot.energy
        )
        self:publish(msg)
    end
    for i = 1, #self.bullets do
        local bullet = self.bullets[i]
        msg = string.format("%d %d", bullet.cx, bullet.cy)
        self:publish(msg)
    end
end

function Server:control_loop()
    local size, err, msg, cmd
    local running = true
    while running do
        local energies = ""
        for id = 1, #self.energies do
            energies = energies..string.format(" %d", self.energies[id])
        end
        self:update_radars()
        for i = 1, #self.bots do
            local bot = self.bots[i]
            msg = string.format("%d %d ", bot.cx, bot.cy)
            msg = msg..string.format("%d ", math.deg(bot.dir))
            msg = msg..string.format("%d ", math.deg(bot.gun_dir))
            msg = msg..string.format("%d ", math.deg(bot.rad_dir))
            msg = msg..string.format("%d\n", bot.visible)..energies
            cmd = request(bot.sock, msg)
            self:update_bot(bot, cmd)
        end
        self:update_bullets()
        self:update_view()
        sleep(0.01)
    end
end

math.randomseed(os.time())
local server = new_server(1700, WIN_WIDTH, WIN_HEIGHT)
server:get_group()
server:init_bots()
server:control_loop()

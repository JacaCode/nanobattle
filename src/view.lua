package.path = package.path .. ";../lib/?.lua;../lib/?/init.lua"

local ffi = require "ffi"
local nn = require "nanomsg"
local sdl = require "sdl2"

ffi.cdef[[
int filledCircleRGBA(
    SDL_Renderer *renderer, Sint16 x, Sint16 y, Sint16 rad,
    Uint8 r, Uint8 g, Uint8 b, Uint8 a
);
int filledTrigonRGBA(
    SDL_Renderer *renderer, Sint16 x1, Sint16 y1, Sint16 x2, Sint16 y2,
    Sint16 x3, Sint16 y3, Uint8 r, Uint8 g, Uint8 b, Uint8 a
);
int filledPieRGBA(
    SDL_Renderer *renderer, Sint16 x, Sint16 y, Sint16 rad,
    Sint16 start, Sint16 end, Uint8 r, Uint8 g, Uint8 b, Uint8 a
);
typedef struct {
    Uint32 framecount;
    float rateticks;
    Uint32 baseticks;
    Uint32 lastticks;
    Uint32 rate;
} FPSmanager;
void SDL_initFramerate(FPSmanager *manager);
int SDL_setFramerate(FPSmanager *manager, Uint32 rate);
int SDL_getFramecount(FPSmanager *manager);
Uint32 SDL_framerateDelay(FPSmanager *manager);
]]

local gfx = ffi.load("SDL2_gfx")

local initFramerate = gfx.SDL_initFramerate
local setFramerate = gfx.SDL_setFramerate
local getFramecount = gfx.SDL_getFramecount
local framerateDelay = gfx.SDL_framerateDelay

local function Rect(x, y, w, h)
    return ffi.new("SDL_Rect", {x, y, w, h})
end

local TITLE = "bots"
local WIN_WIDTH, WIN_HEIGHT
local BOT_RADIUS
local BULLET_RADIUS
local RADAR_AREA

local COLORS = {
    {255, 0, 0},
    {0, 255, 0},
    {0, 0, 255},
    {255, 255, 0},
    {0, 255, 255},
    {255, 0, 255}
}

local len = 256
local buf = ffi.new("char[?]", len)

local function recv(sock)
    size, err = sock:recv(buf, len)
    assert(size ~= nil, nn.strerror(err))
    return ffi.string(buf, size)
end

local function init(ip, port)
    local err, sock, rc, size
    local url = "tcp://"..ip..":"..tostring(port)
    sock, err = nn.socket(nn.SUB)
    assert(sock, nn.strerror(err))
    rc, err = sock:setsockopt(nn.SUB, nn.SUB_SUBSCRIBE, "", 0)
    assert(rc == 0, nn.strerror(err))
    rc, err = sock:connect(url)
    assert(rc ~= nil, nn.strerror(err))
    return sock
end

local function set_radar_radius(bot, radius)
    bot.rad_radius = radius
    bot.rad_angle = 2*RADAR_AREA/(radius*radius)
end

local function clear(renderer, r, g, b)
    sdl.renderClear(renderer)
    sdl.setRenderDrawColor(renderer, r, g, b, 255)
    sdl.renderFillRect(renderer, Rect(0, 0, WIN_WIDTH, WIN_HEIGHT))
end

local function draw_bot_body(renderer, bot)
    gfx.filledCircleRGBA(
        renderer, bot.cx, bot.cy, BOT_RADIUS,
        bot.r, bot.g, bot.b, bot.a
    )
    local a = bot.dir
    local b = bot.dir + 2 * math.pi / 3
    local c = bot.dir - 2 * math.pi / 3
    local cosa, sina = math.cos(a), math.sin(a)
    local cosb, sinb = math.cos(b), math.sin(b)
    local cosc, sinc = math.cos(c), math.sin(c)
    gfx.filledTrigonRGBA(
        renderer, bot.cx, bot.cy,
        bot.cx + cosa * BOT_RADIUS, bot.cy + sina * BOT_RADIUS,
        bot.cx + cosb * BOT_RADIUS, bot.cy + sinb * BOT_RADIUS,
        128, 128, 128, bot.a
    )
    gfx.filledTrigonRGBA(
        renderer, bot.cx, bot.cy,
        bot.cx + cosa * BOT_RADIUS, bot.cy + sina * BOT_RADIUS,
        bot.cx + cosc * BOT_RADIUS, bot.cy + sinc * BOT_RADIUS,
        128, 128, 128, bot.a
    )
end

local function draw_bot_gun(renderer, bot)
    local o, s = math.pi / 20, 1.3
    local cosa, sina = math.cos(bot.gun_dir), math.sin(bot.gun_dir)
    local cosb, sinb = math.cos(bot.gun_dir-o), math.sin(bot.gun_dir-o)
    local cosc, sinc = math.cos(bot.gun_dir+o), math.sin(bot.gun_dir+o)
    gfx.filledTrigonRGBA(
        renderer,
        bot.cx - cosa * BOT_RADIUS/2, bot.cy - sina * BOT_RADIUS/2,
        bot.cx + cosb * BOT_RADIUS*s, bot.cy + sinb * BOT_RADIUS*s,
        bot.cx + cosc * BOT_RADIUS*s, bot.cy + sinc * BOT_RADIUS*s,
        0, 0, 0, bot.a
    )
end

local function draw_bot_radar(renderer, bot)
    local a1 = bot.rad_dir - bot.rad_angle/2
    local a2 = bot.rad_dir + bot.rad_angle/2
    gfx.filledPieRGBA(
        renderer,
        bot.cx, bot.cy, bot.rad_radius,
        math.deg(a1), math.deg(a2),
        255, 255, 255, 128
    )
end

local function draw_bullet(renderer, bullet)
    gfx.filledCircleRGBA(
        renderer, bullet.x, bullet.y, BULLET_RADIUS,
        64, 56, 20, 255
    )
end

local sock = init("127.0.0.1", 1800)
local num = "(-?%d+)"

local pattern = "! "..string.rep(num.." ", 6)..num
local str
while true do
    str = recv(sock)
    if string.sub(str, 1, 1) == "!" then
        break
    end
end
local w, h, br, fr, ra, n, m = string.match(str, pattern)
for i = 1, n+m do
    recv(sock)
end

WIN_WIDTH, WIN_HEIGHT = tonumber(w), tonumber(h)
BOT_RADIUS = tonumber(br)
BULLET_RADIUS = tonumber(fr)
RADAR_AREA = tonumber(ra)

sdl.init(sdl.INIT_VIDEO)

local win = sdl.createWindow(
    TITLE,
    sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED,
    WIN_WIDTH, WIN_HEIGHT, 0
)

local rdr = sdl.createRenderer(win, -1, sdl.RENDERER_ACCELERATED)

local pb = string.rep(num.." ", 6)..num
local pc = num.." "..num
local pevent = ffi.new("SDL_Event[1]")
local running = true
while running do
    while sdl.pollEvent(pevent) == 1 do
        local event = pevent[0]
        if event.type == sdl.KEYDOWN and event.key.keysym.sym == sdl.K_q then
            running = false
        end
    end
    w, h, br, fr, ra, n, m = string.match(recv(sock), pattern)
    local bots = {}
    for i = 1, n do
        local id, bx, by, bd, gd, rd, rr, e = string.match(recv(sock), pb)
        local color = COLORS[tonumber(id)]
        bots[i] = {
            cx = tonumber(bx), cy = tonumber(by), dir = math.rad(tonumber(bd)),
            r = color[1], g = color[2], b = color[3], a = 255,
            gun_dir = math.rad(tonumber(gd)), rad_dir = math.rad(tonumber(rd)),
            energy = tonumber(e)
        }
        set_radar_radius(bots[i], tonumber(rr))
    end
    local bullets = {}
    for i = 1, m do
        local x, y = string.match(recv(sock), pc)
        bullets[i] = {x = tonumber(x), y = tonumber(y)}
    end
    clear(rdr, 160, 160, 160)
    for i = 1, n do
        local bot = bots[i]
        draw_bot_body(rdr, bot)
    end
    for i = 1, n do
        local bot = bots[i]
        draw_bot_radar(rdr, bot)
    end
    for i = 1, n do
        local bot = bots[i]
        draw_bot_gun(rdr, bot)
    end
    for i = 1, m do
        draw_bullet(rdr, bullets[i])
    end
    sdl.renderPresent(rdr)
    sdl.delay(10)
end

sdl.destroyRenderer(rdr)
sdl.destroyWindow(win)
sdl.quit()

package.path = package.path .. ";../lib/?.lua;../lib/?/init.lua"

local ffi = require "ffi"
local nn = require "nanomsg"
local sdl = require "sdl2"

ffi.cdef[[
int aacircleRGBA(
    SDL_Renderer *renderer, Sint16 x, Sint16 y, Sint16 rad,
    Uint8 r, Uint8 g, Uint8 b, Uint8 a
);
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

local TITLE = "nanobattle"
local WIN_WIDTH, WIN_HEIGHT
local BOT_RADIUS
local BULLET_RADIUS
local RADAR_AREA

local COLORS = {
    {255, 0, 0},
    {0, 255, 0},
    {0, 0, 255},
    {226, 214, 0},
    {0, 255, 255},
    {255, 0, 255},
    {255, 255, 255},
    {0, 0, 0}
}

local len = 256
local buf = ffi.new("char[?]", len)

local function bot2color(id)
    local n = #COLORS
    local idx = id - 1
    local a = idx % n
    local b = (a + (math.floor(idx / n)) + 1) % n
    return a+1, b+1
end

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
        bot.color_a[1], bot.color_a[2], bot.color_a[3], 255
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
        bot.color_b[1], bot.color_b[2], bot.color_b[3], 255
    )
    gfx.filledTrigonRGBA(
        renderer, bot.cx, bot.cy,
        bot.cx + cosa * BOT_RADIUS, bot.cy + sina * BOT_RADIUS,
        bot.cx + cosc * BOT_RADIUS, bot.cy + sinc * BOT_RADIUS,
        bot.color_b[1], bot.color_b[2], bot.color_b[3], 255
    )
end

local function draw_bot_gun(renderer, bot)
    local o = math.pi / 20
    local s
    if bot.shield == 0 then
        s = 1.3 - bot.wait * 0.8 / 50
    else
        s = 0.5
    end
    local cosa, sina = math.cos(bot.gun_dir), math.sin(bot.gun_dir)
    local cosb, sinb = math.cos(bot.gun_dir-o), math.sin(bot.gun_dir-o)
    local cosc, sinc = math.cos(bot.gun_dir+o), math.sin(bot.gun_dir+o)
    gfx.filledTrigonRGBA(
        renderer,
        bot.cx - cosa * BOT_RADIUS/2, bot.cy - sina * BOT_RADIUS/2,
        bot.cx + cosb * BOT_RADIUS*s, bot.cy + sinb * BOT_RADIUS*s,
        bot.cx + cosc * BOT_RADIUS*s, bot.cy + sinc * BOT_RADIUS*s,
        0, 0, 0, 255
    )
end

local function draw_bot_shield(renderer, bot)
    if bot.shield == 1 then
        local a1 = bot.rad_dir - bot.rad_angle/2
        local a2 = bot.rad_dir + bot.rad_angle/2
        local s = 1 + bot.wait * 0.3 / 50
        gfx.filledPieRGBA(
            renderer,
            bot.cx, bot.cy, BOT_RADIUS*s,
            math.deg(a1), math.deg(a2),
            255, 255, 255, 255
        )
    end
end

local function draw_bot_radar(renderer, bot)
    local a1 = bot.rad_dir - bot.rad_angle/2
    local a2 = bot.rad_dir + bot.rad_angle/2
    local r, g, b
    if bot.visible == 0 then
        r, g, b = 255, 255, 255
    else
        r, g, b = 255, 0, 0
    end
    gfx.filledPieRGBA(
        renderer,
        bot.cx, bot.cy, bot.rad_radius,
        math.deg(a1), math.deg(a2),
        r, g, b, 96
    )
end

local function draw_bot_energy(renderer, bot)
    local e = bot.energy
    local r = BOT_RADIUS
    local dy = bot.cy < BOT_RADIUS+10 and r+5 or -r-10
    local rect = Rect(bot.cx-r, bot.cy+dy, 2*r, 5)
    sdl.setRenderDrawColor(renderer, 0, 0, 0, 255)
    sdl.renderFillRect(renderer, rect)
    sdl.setRenderDrawColor(renderer, (100-e/2)*255/100, e*255/100, 0, 255)
    rect.w = rect.w * e / 100
    sdl.renderFillRect(renderer, rect)
end

local function draw_bullet(renderer, bullet)
    gfx.filledCircleRGBA(
        renderer, bullet.x, bullet.y, BULLET_RADIUS,
        255, 102, 0, 255
    )
    gfx.aacircleRGBA(
        renderer, bullet.x, bullet.y, BULLET_RADIUS,
        255, 255, 255, 255
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

local pb = string.rep(num.." ", 10)..num
local pc = num.." "..num
local pevent = ffi.new("SDL_Event[1]")
local running = true
local fps_res = 50
local t1, t2
t1 = sdl.getTicks()
local frame = 0
local fps = 0
while running do
    while sdl.pollEvent(pevent) == 1 do
        local event = pevent[0]
        if event.type == sdl.KEYDOWN and event.key.keysym.sym == sdl.K_q then
            running = false
        end
    end
    w, h, br, fr, ra, n, m = string.match(recv(sock), pattern)
    local bots = {}
    local vis = 0
    for i = 1, n do
        local id, bx, by, bd, gd, gw, s, rd, rr, rv, e = string.match(recv(sock), pb)
        id = tonumber(id)
        local id_a, id_b = bot2color(id)
        local color_a, color_b = COLORS[id_a], COLORS[id_b]
        local bot = {
            cx = tonumber(bx), cy = tonumber(by), dir = math.rad(tonumber(bd)),
            color_a = color_a, color_b = color_b,
            gun_dir = math.rad(tonumber(gd)), rad_dir = math.rad(tonumber(rd)),
            wait = tonumber(gw), shield = tonumber(s),
            visible = tonumber(rv), energy = tonumber(e)
        }
        set_radar_radius(bot, tonumber(rr))
        vis = vis + bot.visible
        bots[i] = bot
    end
    local bullets = {}
    for i = 1, m do
        local x, y = string.match(recv(sock), pc)
        bullets[i] = {x = tonumber(x), y = tonumber(y)}
    end
    clear(rdr, 130, 130, 150)
    local layers = {
        draw_bot_shield, draw_bot_body, draw_bot_gun,
        draw_bot_radar, draw_bot_energy
    }
    for i = 1, #layers do
        local layer = layers[i]
        for j = 1, n do
            layer(rdr, bots[j])
        end
    end
    for i = 1, m do
        draw_bullet(rdr, bullets[i])
    end
    sdl.renderPresent(rdr)
    local title = string.format(
        "%s: %2d bots, %2d visible, %2d bullets (%d fps)",
        TITLE, n, vis, m, fps
    )
    sdl.setWindowTitle(win, title)
    sdl.delay(1)
    frame = frame + 1
    if frame == fps_res then
        frame = 0
        t2 = sdl.getTicks()
        fps = fps_res * 1000 / (t2-t1)
        t1 = t2
    end
end

sdl.destroyRenderer(rdr)
sdl.destroyWindow(win)
sdl.quit()

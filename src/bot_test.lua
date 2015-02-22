local client = require "client"

function client.Bot:turn(bx, by, bd, gd, rd, rv, es)
    return "++===="
end

local bot = client.new_bot("127.0.0.1", 1700)
local id = bot:join(arg[1])
assert(id ~= nil, "name already in use")
if id == 6 then
    bot:end_group()
end
bot:run()

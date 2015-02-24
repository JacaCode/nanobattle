#! /bin/sh

N=`wc -l < local.cfg`

luajit ../src/server.lua $N 2>server.log &
echo $! > server.pid
sleep 0.2

> bots.pid
for i in `seq 1 $N`
do
    read bot
    luajit "bot_$bot.lua" $i 2>"bot$i.log" &
    echo $! >> bots.pid
    sleep 0.2
done < local.cfg

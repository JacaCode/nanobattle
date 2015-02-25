#! /bin/sh

N=`wc -l < local.cfg`
LOG="/tmp/nanolog"

mkdir -p $LOG

luajit ../src/server.lua $N 2>"$LOG/server.log" &
echo $! > server.pid
sleep 0.2

> bots.pid
for i in `seq 1 $N`
do
    read bot
    luajit "bot_$bot.lua" $i 2>"$LOG/bot$i.log" &
    echo $! >> bots.pid
    sleep 0.2
done < local.cfg

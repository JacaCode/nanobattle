#! /bin/sh

N=`wc -l < local.cfg`
LOG="/tmp/nanolog"

mkdir -p $LOG

rm -f $LOG/*.log

luajit ../src/record.lua > "$LOG/battle.nnb" 2> /dev/null &
echo $! > record.pid
sleep 0.2

luajit ../src/server.lua $N 2> "$LOG/server.log" &
echo $! > server.pid
sleep 0.2

> bots.pid
for i in `seq 1 $N`
do
    read bot
    luajit "bot_$bot.lua" "$bot:$i" 2> "$LOG/bot$i.log" &
    echo $! >> bots.pid
    sleep 0.2
done < local.cfg

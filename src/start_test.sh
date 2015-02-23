#! /bin/sh

N=${1-1}

luajit server.lua $N 2>server.log &
echo $! > server.pid
sleep 0.2

> bots.pid
for i in `seq 1 $N`
do
    luajit bot_test.lua $i 2>"bot$i.log" &
    echo $! >> bots.pid
    sleep 0.2
done

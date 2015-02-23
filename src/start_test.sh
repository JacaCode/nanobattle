#! /bin/sh

N=${1-1}

luajit server.lua $N 2>server.log &
echo $! > server.pid
sleep 1

luajit view.lua 2>view.log &
echo $! > view.pid
sleep 1

> bots.pid
for i in `seq 1 $N`
do
    luajit bot_test.lua $i 2>"bot$i.log" &
    echo $! >> bots.pid
    sleep 1
done

#! /bin/sh

pid=`cat server.pid`
kill -s INT $pid && rm server.pid

pid=`cat view.pid`
kill -s INT $pid && rm view.pid

while read pid
do
    kill -s INT $pid
done < bots.pid && rm bots.pid

#! /bin/sh

pid=`cat server.pid`
kill -s INT $pid
rm -f server.pid

while read pid
do
    kill -s INT $pid
done < bots.pid
rm -f bots.pid

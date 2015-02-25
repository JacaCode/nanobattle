#! /bin/sh

pid=`cat server.pid`
kill -s INT $pid 2> /dev/null
rm -f server.pid

while read pid
do
    kill -s INT $pid 2> /dev/null
done < bots.pid
rm -f bots.pid

#! /bin/sh

./start_local.sh && luajit ../src/view.lua && ./stop_local.sh

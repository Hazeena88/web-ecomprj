#!/bin/bash
cd /home/ec2-user/backend
node index.js > app.out.log 2> app.err.log < /dev/null &

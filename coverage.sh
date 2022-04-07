#!/bin/zsh
cd `dirname $0`
genhtml coverage/lcov.info --output-directory coverage/html
open coverage/html/index.html

#!/bin/sh

#  hello_in.sh
#  RxExecs
#
wc -l <&0 | xargs echo

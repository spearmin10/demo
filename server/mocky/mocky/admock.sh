#!/bin/sh
cd "$(dirname "$0")"
python3 ./admock.py --ldif ../etc/admock.ldif

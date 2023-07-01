#!/usr/bin/env bash

[ -z "$4" ] && { echo "Usage: $0 from to subject message"; exit 1; }

nc mx.sendgrid.net 25 <<EOF
ehlo ${2##*@}
mail from: $1
rcpt to: $2
data
From: <$1>
To: $2 <$2>
Subject: $3

$4
.
quit
EOF

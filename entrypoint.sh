#!/bin/bash

set -m

/iris-main "$@" &

/usr/irissys/dev/Cloud/ICM/waitISC.sh

/usr/irissys/bin/irispython /scripts/oauth_setup.py ${ISC_OAUTH_SECRET_PATH}

# Bring the IRIS instance to foreground
fg %1

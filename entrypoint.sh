#!/bin/bash

set -m

/iris-main "$@" &

/usr/irissys/dev/Cloud/ICM/waitISC.sh

if [ -f ${ISC_OAUTH_SECRET_PATH} ]; then
    /usr/irissys/bin/irispython /scripts/oauth_setup.py ${ISC_OAUTH_SECRET_PATH}
fi

fg %1

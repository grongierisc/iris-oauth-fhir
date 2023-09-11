FROM intersystemsdc/irishealth-community:latest as builder

##### first part of the script

# create data dir for persistent IRIS store and change owner to IRIS user
USER root
RUN mkdir -p /data
RUN chown -R ${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} /data
USER ${ISC_PACKAGE_MGRUSER}

# modify and configure IRIS (create namespace, FHIR repo, etc.)
RUN \
	--mount=type=bind,src=.,dst=/irisdev/app \
	--mount=type=bind,src=./iris.script,dst=/tmp/iris.script \
	pip3 install -r /irisdev/app/requirements.txt && \
	iris start IRIS && \
	iris session IRIS < /tmp/iris.script && \
	iris stop iris quietly

FROM intersystemsdc/irishealth-community:latest as final

##### end of multi stage build

# script to slim down the image
ADD --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} https://github.com/grongierisc/iris-docker-multi-stage-script/releases/latest/download/copy-data.py /irisdev/app/copy-data.py

# run the slim down script
RUN --mount=type=bind,source=/,target=/builder/root,from=builder \
    cp -f /builder/root/usr/irissys/iris.cpf /usr/irissys/iris.cpf && \
    python3 /irisdev/app/copy-data.py -c /usr/irissys/iris.cpf -d /builder/root/ 

# Python stuff
ENV IRISUSERNAME "SuperUser"
ENV IRISPASSWORD "SYS"
ENV IRISNAMESPACE "FHIRSERVER"
ENV IRISINSTALLDIR $ISC_PACKAGE_INSTALLDIR
ENV LD_LIBRARY_PATH=$IRISINSTALLDIR/bin:$LD_LIBRARY_PATH

# copy the python requirements file
COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} ./requirements.txt /irisdev/app/requirements.txt

# install the python requirements
RUN pip3 install -r /irisdev/app/requirements.txt

# copy the python source code
COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} ./src/python /irisdev/app/src/python

# add the entrypoint script
COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} ./entrypoint.sh /entrypoint.sh

# copy the oauth_setup.py script
COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} ./src/python/oauth_setup.py /scripts/oauth_setup.py

# copy merge.cpf script
COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} ./common.cpf /irisdev/app/common.cpf

ENTRYPOINT [ "/tini", "--", "/entrypoint.sh" ]
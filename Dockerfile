FROM quay.io/datacratic/baseimage:0.9.17

VOLUME /source

COPY run_in_container.sh rebuild_pycs.py /source/

RUN chmod +x /source/run_in_container.sh && /source/run_in_container.sh

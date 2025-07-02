##
# do some common things that all layers use, on top of the UBI base; also
# make sure security updates are installed
##
FROM ${BASE_IMAGE} AS core

# We need to install inetutils-ping to get the JNI Pinger to work.
# The JNI Pinger is tested with getprotobyname("icmp") and it is null if inetutils-ping is missing.
# TODO: switch `vim` back to `vim-minimal` once https://issues.redhat.com/browse/RHEL-25748 is resolved
RUN microdnf -y upgrade && \
    microdnf -y install \
        hostname \
        iputils \
        less \
        ncurses \
        openssh-clients \
        rsync \
        tar \
        unzip \
        uuid \
        vim-minimal \
        /usr/bin/ps \
        /usr/bin/which \
    && \
    rm -rf /var/cache/yum

##
# Pre-stage image to build various binaries
##
FROM core AS binary-build

## Install build dependencies
RUN microdnf -y install \
    autoconf \
    automake \
    gcc \
    git \
    java-1.8.0-openjdk-devel \
    libtool \
    make

## Checkout and build JICMP
RUN git config --global advice.detachedHead false

RUN git clone --depth 1 --branch "${JICMP_VERSION}" "${JICMP_GIT_REPO_URL}" /usr/src/jicmp && \
    cd /usr/src/jicmp && \
    git submodule update --init --recursive --depth 1 && \
    autoreconf -fvi && \
    ./configure
RUN cd /usr/src/jicmp && make -j1

# Checkout and build JICMP6
RUN git clone --depth 1 --branch "${JICMP6_VERSION}" "${JICMP6_GIT_REPO_URL}" /usr/src/jicmp6 && \
    cd /usr/src/jicmp6 && \
    git submodule update --init --recursive --depth 1 && \
    autoreconf -fvi && \
    ./configure
RUN cd /usr/src/jicmp6 && make -j1

## Checkout and build jattach
RUN git clone --depth 1 --branch "${JATTACH_VERSION}" "${JATTACH_GIT_REPO_URL}" /usr/src/jattach
RUN cd /usr/src/jattach && make

##
# Assemble deploy base image with jattach, confd and OpenJDK
##
FROM core

RUN microdnf -y install \
        "java-${JAVA_MAJOR_VERSION}-openjdk-headless" \
    && \
    rm -rf /var/cache/yum

# Set JAVA_HOME at runtime
ENV JAVA_HOME=${JAVA_HOME}

# To be able to use DGRAM to send ICMP messages we have to give the java binary CAP_NET_RAW capabilities in Linux.
COPY do-setcap.sh /usr/local/bin/
RUN /usr/local/bin/do-setcap.sh

# Install confd
RUN if [ "$(uname -m)" = "x86_64" ]; then \
      curl -L "${CONFD_SOURCE}/releases/download/v${CONFD_VERSION}/confd-v${CONFD_VERSION}-linux-amd64.tar.gz" --output /tmp/confd.tar.gz; \
    elif [ "$(uname -m)" = "armv7l" ]; then \
      curl -L "${CONFD_SOURCE}/releases/download/v${CONFD_VERSION}/confd-v${CONFD_VERSION}-linux-arm7.tar.gz" --output /tmp/confd.tar.gz; \
    else \
      curl -L "${CONFD_SOURCE}/releases/download/v${CONFD_VERSION}/confd-v${CONFD_VERSION}-linux-arm64.tar.gz" --output /tmp/confd.tar.gz; \
    fi && \
    cd /usr/bin && \
    tar -xzf /tmp/confd.tar.gz && \
    rm -f /tmp/confd.tar.gz

## Install jicmp
RUN mkdir -p /usr/lib/jni
COPY --from=binary-build /usr/src/jicmp/.libs/libjicmp.la /usr/lib/jni/
COPY --from=binary-build /usr/src/jicmp/.libs/libjicmp.so /usr/lib/jni/
COPY --from=binary-build /usr/src/jicmp/jicmp.jar /usr/share/java/

# Install jicmp6
COPY --from=binary-build /usr/src/jicmp6/.libs/libjicmp6.la /usr/lib/jni/
COPY --from=binary-build /usr/src/jicmp6/.libs/libjicmp6.so /usr/lib/jni/
COPY --from=binary-build /usr/src/jicmp6/jicmp6.jar /usr/share/java/

# Install jattach
COPY --from=binary-build /usr/src/jattach/build/jattach /usr/bin/

RUN mkdir -p /opt/prom-jmx-exporter

WORKDIR /opt/prom-jmx-exporter

RUN curl -L "${PROM_JMX_EXPORTER_URL}" --output ./jmx_prometheus_javaagent.jar && \
    echo "${PROM_JMX_EXPORTER_SHA256} jmx_prometheus_javaagent.jar" > jmx_prometheus_javaagent.jar.sha256 && \
    sha256sum -c /opt/prom-jmx-exporter/jmx_prometheus_javaagent.jar.sha256 && \
    chown -R 10001:0 /opt/prom-jmx-exporter

RUN curl -L --output /tmp/repo.rpm https://yum.opennms.org/repofiles/opennms-repo-stable-rhel9.noarch.rpm && \
    rpm -Uf /tmp/repo.rpm && \
    rpm --import https://yum.opennms.org/OPENNMS-GPG-KEY

LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.title="OpenNMS deploy based on ${BASE_IMAGE}" \
      org.opencontainers.image.source="${VCS_SOURCE}" \
      org.opencontainers.image.revision="${VCS_REVISION}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.vendor="The OpenNMS Group, Inc." \
      org.opencontainers.image.authors="OpenNMS Community" \
      org.opencontainers.image.licenses="AGPL-3.0" \
      org.opennms.image.base="${BASE_IMAGE}" \
      org.opennms.image.java.version="${JAVA_MAJOR_VERSION}" \
      org.opennms.image.java.home="${JAVA_HOME}" \
      org.opennms.image.jicmp.version="${JICMP_VERSION}" \
      org.opennms.image.jicmp6.version="${JICMP6_VERSION}" \
      org.opennms.cicd.branch="${BUILD_BRANCH}" \
      org.opennms.cicd.buildurl="${BUILD_URL}" \
      org.opennms.cicd.buildnumber="${BUILD_NUMBER}"


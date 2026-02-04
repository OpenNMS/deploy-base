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
    libtool \
    make


RUN if [ "$(uname -m)" = "x86_64" ]; then \
        curl -L https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u482-b08/OpenJDK8U-jdk_x64_linux_hotspot_8u482b08.tar.gz --output /tmp/openjdk8.tar.gz; \
    elif [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then \
        curl -L https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u482-b08/OpenJDK8U-jdk_aarch64_linux_hotspot_8u482b08.tar.gz --output /tmp/openjdk8.tar.gz; \
    fi && \
    tar -xzf /tmp/openjdk8.tar.gz -C /opt && \
    rm -f /tmp/openjdk8.tar.gz; \

## Checkout and build JICMP
RUN git config --global advice.detachedHead false

RUN export JAVA_HOME=/opt/jdk8u482-b08 && export PATH=/opt/jdk8u482-b08/bin:$PATH && \
    git clone --depth 1 --branch "${JICMP_VERSION}" "${JICMP_GIT_REPO_URL}" /usr/src/jicmp && \
    cd /usr/src/jicmp && \
    git submodule update --init --recursive --depth 1 && \
    autoreconf -fvi && \
    ./configure
RUN cd /usr/src/jicmp && make -j1

# Checkout and build JICMP6
RUN export JAVA_HOME=/opt/jdk8u482-b08 && export PATH=/opt/jdk8u482-b08/bin:$PATH && \
    git clone --depth 1 --branch "${JICMP6_VERSION}" "${JICMP6_GIT_REPO_URL}" /usr/src/jicmp6 && \
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

# if JAVA_MAJOR_VERSION is 11, use this:
# https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.30%2B7/OpenJDK11U-jdk_x64_linux_hotspot_11.0.30_7.tar.gz
RUN if [ "${JAVA_MAJOR_VERSION}" = "11" ]; then \
    if [ "$(uname -m)" = "x86_64" ]; then \
        curl -L "https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.30%2B7/OpenJDK11U-jdk_x64_linux_hotspot_11.0.30_7.tar.gz" --output /tmp/openjdk.tar.gz; \
    elif [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then \
        curl -L "https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.30%2B7/OpenJDK11U-jdk_aarch64_linux_hotspot_11.0.30_7.tar.gz" --output /tmp/openjdk.tar.gz; \
    fi && \
    tar -xzf /tmp/openjdk.tar.gz -C /opt && \
    rm -f /tmp/openjdk.tar.gz; \
    fi
# if JAVA_MAJOR_VERSION is 17, use this:
# https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.18%2B8/OpenJDK17U-jdk_x64_linux_hotspot_17.0.18_8.tar.gz
RUN if [ "${JAVA_MAJOR_VERSION}" = "17" ]; then \
    if [ "$(uname -m)" = "x86_64" ]; then \
        curl -L "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.18%2B8/OpenJDK17U-jdk_x64_linux_hotspot_17.0.18_8.tar.gz" --output /tmp/openjdk.tar.gz; \
    elif [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then \
        curl -L "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.18%2B8/OpenJDK17U-jdk_aarch64_linux_hotspot_17.0.18_8.tar.gz" --output /tmp/openjdk.tar.gz; \
    fi && \
    tar -xzf /tmp/openjdk.tar.gz -C /opt && \
    rm -f /tmp/openjdk.tar.gz; \
    fi
# else install using microdnf
RUN if [ "${JAVA_MAJOR_VERSION}" != "11" ] && [ "${JAVA_MAJOR_VERSION}" != "17" ]; then \
    echo "Installing OpenJDK ${JAVA_MAJOR_VERSION} via microdnf"; \
    microdnf -y install \
    "java-${JAVA_MAJOR_VERSION}-openjdk-headless" && \
    rm -rf /var/cache/yum; \
    fi

# Set JAVA_HOME based on installed version - create a symlink for consistency
RUN if [ "${JAVA_MAJOR_VERSION}" = "11" ]; then \
    ln -sf /opt/jdk-11.0.30+7 /opt/java; \
    elif [ "${JAVA_MAJOR_VERSION}" = "17" ]; then \
    ln -sf /opt/jdk-17.0.18+8 /opt/java; \
    else \
    ln -sf $(dirname $(dirname $(readlink -f $(which java)))) /opt/java; \
    fi

# Set JAVA_HOME at runtime
ENV JAVA_HOME=/opt/java

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
    chown -R 10001:0 /opt/prom-jmx-exporter && \
    chmod 2775 /opt/prom-jmx-exporter && \
    chmod 0664 /opt/prom-jmx-exporter/*

RUN curl -L --output /tmp/repo.rpm https://yum.opennms.org/repofiles/opennms-repo-stable-rhel9.noarch.rpm && \
    rpm -Uvh --nodigest --nosignature --noverify /tmp/repo.rpm && \
    sed -i 's/gpgcheck=1/gpgcheck=0/g' /etc/yum.repos.d/opennms*.repo && \
    rm -f /tmp/repo.rpm

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

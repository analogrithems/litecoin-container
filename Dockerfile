FROM amazonlinux:latest

ARG LITECOIN_VERSION=0.18.1
ARG LITECOIN_USER=litecoin
ARG LITECOIN_GROUP=litecoin
ARG uid=1010
ARG gid=1010
ARG APP_VERSION=0.0
ARG BUILD_TIME=0
ENV APP_VERSION=${APP_VERSION} \
    BUILD_TIME=${BUILD_TIME} \
    LITECOIN_USER=${LITECOIN_USER} \
    LITECOIN_GROUP=${LITECOIN_GROUP} \
    ENABLE_SSM=false \
	MAX_CONNECTIONS='' \
	ENABLE_WALLET='' \
	RPC_USER=litecoinrpc \
	RPC_PASSWORD='fXgL<ehxzk'

RUN yum fs filter languages en && yum fs documentation && yum fs -y refilter && yum fs -y refilter-cleanup
RUN amazon-linux-extras install -y epel 
RUN yum -y install jq procps wget which openssl python-pip shadow-utils sudo tar
RUN yum update -y

#Litecoin service setup
COPY litecoin.init.sh /usr/local/bin/litecoin.init.sh
RUN chmod 755 /usr/local/bin/litecoin.init.sh
COPY litecoin.supervisor.conf /etc/supervisord.d/litecoin.conf
RUN groupadd -g ${gid} ${LITECOIN_GROUP}
RUN useradd -d "/litecoin" -u ${uid} -g ${gid} -m -s /bin/bash ${LITECOIN_USER}

RUN wget https://download.litecoin.org/litecoin-${LITECOIN_VERSION}/linux/litecoin-${LITECOIN_VERSION}-x86_64-linux-gnu.tar.gz && \
    wget https://download.litecoin.org/litecoin-${LITECOIN_VERSION}/linux/litecoin-${LITECOIN_VERSION}-x86_64-linux-gnu.tar.gz.asc && \
    gpg --keyserver pgp.mit.edu --recv-key FE3348877809386C && \
    gpg --verify litecoin-${LITECOIN_VERSION}-x86_64-linux-gnu.tar.gz.asc && \
    tar xfz /litecoin-${LITECOIN_VERSION}-x86_64-linux-gnu.tar.gz && \
    mv litecoin-${LITECOIN_VERSION}/bin/* /usr/local/bin/ && \
    rm -rf litecoin-* /root/.gnupg

#This section is setup to allow us to shell into a running container without SSH
ADD supervisor.conf /etc/supervisord.conf
ADD ssm-agent.conf /etc/supervisord.d/ssm-agent.conf
ADD ssm-setup.sh /usr/local/bin/ssm-setup.sh
#Fix sudoers path
RUN sed -i 's/^Defaults    secure_path/# Defaults    secure_path/' /etc/sudoers
RUN chmod 755 /usr/local/bin/ssm-setup.sh
ADD ssm-agent-user /etc/sudoers.d/ssm-agent-users 
#RUN mv /etc/amazon/ssm/seelog.xml.template /etc/amazon/ssm/seelog.xml

ADD requirements.txt .
RUN pip install -r requirements.txt
RUN yum remove -y systemtap-client systemtap-runtime subversion-libs boost-system gdb kernel-headers
RUN yum clean all && \
    rm -Rf /tmp/packages /etc/udev /var/tmp/yum* \
    /usr/share/{licenses,doc,man,info,vim}/* /var/cache/yum /root/.cache/*  && \
    localedef --delete-from-archive $(localedef --list-archive | grep -v -i ^en | xargs) && \
    cp /usr/lib/locale/locale-archive /usr/lib/locale/locale-archive.tmpl && \
    build-locale-archive

VOLUME ["/litecoin"]

EXPOSE 9333 9332

CMD ["/usr/bin/supervisord","-c","/etc/supervisord.conf"]
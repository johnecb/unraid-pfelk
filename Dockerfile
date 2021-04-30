# Dockerfile for ELK stack
# Elasticsearch, Logstash, Kibana OSS 7.10.0

# Run with:
# /usr/local/emhttp/plugins/dynamix.docker.manager/scripts/docker create --name='pfELK' --net='bridge' --privileged=false -e TZ="Europe/London" -e HOST_OS="Unraid" -e 'MAX_OPEN_FILES'='65536' -p '5601:5601/tcp' -p '9200:9200/tcp' -p '5044:5044/tcp' -p '5140:5140/udp' -p '5141:5141/tcp' -p '5145:5145/udp' -v '/mnt/user/appdata/unraid-pfelk/conf.d/':'/etc/logstash/conf.d':'rw' -v '/mnt/user/appdata/maxmind/database':'/usr/share/GeoIP/':'rw' 'noodlemctwoodle/unraid-pfelk'

# replace with master-arm64 for ARM64
ARG IMAGE=18.04-1.0.0
FROM phusion/baseimage:${IMAGE}
ENV \
 REFRESHED_AT=2020-06-20


###############################################################################
#                                INSTALLATION
###############################################################################

### install prerequisites (cURL, gosu, tzdata, JDK for Logstash)

RUN set -x \
 && apt update -qq \
 && apt install -qqy --no-install-recommends ca-certificates curl gosu tzdata openjdk-11-jdk-headless wget\
 && apt clean \
 && rm -rf /var/lib/apt/lists/* \
 && gosu nobody true \
 && set +x


### set current package version

ARG ELK_VERSION=oss-7.12.0

# replace with aarch64 for ARM64 systems
ARG ARCH=x86_64 


### install Elasticsearch

# predefine env vars, as you can't define an env var that references another one in the same block
ENV \
 ES_VERSION=${ELK_VERSION} \
 ES_HOME=/opt/elasticsearch

ENV \
 ES_PACKAGE=elasticsearch-${ES_VERSION}-linux-${ARCH}.tar.gz \
 ES_GID=991 \
 ES_UID=991 \
 ES_PATH_CONF=/etc/elasticsearch \
 ES_PATH_BACKUP=/var/backups \
 KIBANA_VERSION=${ELK_VERSION}

RUN DEBIAN_FRONTEND=noninteractive \
 && mkdir ${ES_HOME} \
 && curl -O https://artifacts.elastic.co/downloads/elasticsearch/${ES_PACKAGE} \
 && tar xzf ${ES_PACKAGE} -C ${ES_HOME} --strip-components=1 \
 && rm -f ${ES_PACKAGE} \
 && groupadd -r elasticsearch -g ${ES_GID} \
 && useradd -r -s /usr/sbin/nologin -M -c "Elasticsearch service user" -u ${ES_UID} -g elasticsearch elasticsearch \
 && mkdir -p /var/log/elasticsearch ${ES_PATH_CONF} ${ES_PATH_CONF}/scripts /var/lib/elasticsearch ${ES_PATH_BACKUP} \
 && chown -R elasticsearch:elasticsearch ${ES_HOME} /var/log/elasticsearch /var/lib/elasticsearch ${ES_PATH_CONF} ${ES_PATH_BACKUP}


### install Logstash

ENV \
 LOGSTASH_VERSION=${ELK_VERSION} \
 LOGSTASH_HOME=/opt/logstash

ENV \
 LOGSTASH_PACKAGE=logstash-${LOGSTASH_VERSION}.tar.gz \
 LOGSTASH_GID=992 \
 LOGSTASH_UID=992 \
 LOGSTASH_PATH_CONF=/etc/logstash \
 LOGSTASH_PATH_SETTINGS=${LOGSTASH_HOME}/config
 
RUN mkdir ${LOGSTASH_HOME} \
 && curl -O https://artifacts.elastic.co/downloads/logstash/${LOGSTASH_PACKAGE} \
 && tar xzf ${LOGSTASH_PACKAGE} -C ${LOGSTASH_HOME} --strip-components=1 \
 && rm -f ${LOGSTASH_PACKAGE} \
 && groupadd -r logstash -g ${LOGSTASH_GID} \
 && useradd -r -s /usr/sbin/nologin -d ${LOGSTASH_HOME} -c "Logstash service user" -u ${LOGSTASH_UID} -g logstash logstash \
 && mkdir -p /var/log/logstash ${LOGSTASH_PATH_CONF}/conf.d \
 && chown -R logstash:logstash ${LOGSTASH_HOME} /var/log/logstash ${LOGSTASH_PATH_CONF}


### install Kibana

ENV \
 KIBANA_HOME=/opt/kibana \
 KIBANA_PACKAGE=kibana-${KIBANA_VERSION}-linux-${ARCH}.tar.gz \
 KIBANA_GID=993 \
 KIBANA_UID=993

RUN mkdir ${KIBANA_HOME} \
 && curl -O https://artifacts.elastic.co/downloads/kibana/${KIBANA_PACKAGE} \
 && tar xzf ${KIBANA_PACKAGE} -C ${KIBANA_HOME} --strip-components=1 \
 && rm -f ${KIBANA_PACKAGE} \
 && groupadd -r kibana -g ${KIBANA_GID} \
 && useradd -r -s /usr/sbin/nologin -d ${KIBANA_HOME} -c "Kibana service user" -u ${KIBANA_UID} -g kibana kibana \
 && mkdir -p /var/log/kibana \
 && chown -R kibana:kibana ${KIBANA_HOME} /var/log/kibana


###############################################################################
#                              START-UP SCRIPTS
###############################################################################

### Elasticsearch

ADD ./elasticsearch-init /etc/init.d/elasticsearch
RUN sed -i -e 's#^ES_HOME=$#ES_HOME='$ES_HOME'#' /etc/init.d/elasticsearch \
 && chmod +x /etc/init.d/elasticsearch


### Logstash

ADD ./logstash-init /etc/init.d/logstash
RUN sed -i -e 's#^LS_HOME=$#LS_HOME='$LOGSTASH_HOME'#' /etc/init.d/logstash \
 && chmod +x /etc/init.d/logstash


### Kibana

ADD ./kibana-init /etc/init.d/kibana
RUN sed -i -e 's#^KIBANA_HOME=$#KIBANA_HOME='$KIBANA_HOME'#' /etc/init.d/kibana \
 && chmod +x /etc/init.d/kibana


###############################################################################
#                               CONFIGURATION
###############################################################################

### configure Elasticsearch

ADD ./elasticsearch.yml ${ES_PATH_CONF}/elasticsearch.yml
ADD ./elasticsearch-default /etc/default/elasticsearch
RUN cp ${ES_HOME}/config/log4j2.properties ${ES_HOME}/config/jvm.options \
    ${ES_PATH_CONF} \
 && chown -R elasticsearch:elasticsearch ${ES_PATH_CONF} \
 && chmod -R +r ${ES_PATH_CONF}


### configure Logstash

# certs/keys for Beats and Lumberjack input
RUN mkdir -p /etc/pki/tls/{certs,private}
ADD ./logstash-beats.crt /etc/pki/tls/certs/logstash-beats.crt
ADD ./logstash-beats.key /etc/pki/tls/private/logstash-beats.key

# pipelines
ADD pipelines.yml ${LOGSTASH_PATH_SETTINGS}/pipelines.yml

# filters
ADD ./logstash-conf/*.conf ${LOGSTASH_PATH_CONF}/conf.d/
ADD ./logstash-conf/databases/*.csv ${LOGSTASH_PATH_CONF}/conf.d/databases/
ADD ./logstash-conf/patterns/*.grok ${LOGSTASH_PATH_CONF}/conf.d/patterns/
ADD ./logstash-conf/templates/*.json ${LOGSTASH_PATH_CONF}/conf.d/templates/


# patterns
ADD ./nginx.pattern ${LOGSTASH_HOME}/patterns/nginx
RUN chown -R logstash:logstash ${LOGSTASH_HOME}/patterns

# Fix permissions
RUN chmod -R +r ${LOGSTASH_PATH_CONF} ${LOGSTASH_PATH_SETTINGS} \
 && chown -R logstash:logstash ${LOGSTASH_PATH_SETTINGS}


### configure logrotate

ADD ./elasticsearch-logrotate /etc/logrotate.d/elasticsearch
ADD ./logstash-logrotate /etc/logrotate.d/logstash
ADD ./kibana-logrotate /etc/logrotate.d/kibana
RUN chmod 644 /etc/logrotate.d/elasticsearch \
 && chmod 644 /etc/logrotate.d/logstash \
 && chmod 644 /etc/logrotate.d/kibana


### configure Kibana

ADD ./kibana.yml ${KIBANA_HOME}/config/kibana.yml

### add in templates and dashboards

RUN wget https://raw.githubusercontent.com/pfelk/pfelk/main/etc/pfelk/scripts/pfelk-template-installer.sh \
 && sudo chmod +x pfelk-template-installer.sh \
 && sudo ./pfelk-template-installer.sh
 
RUN wget https://raw.githubusercontent.com/pfelk/pfelk/main/etc/pfelk/scripts/pfelk-dashboard-installer.sh \
 && sudo chmod +x pfelk-dashboard-installer.sh
 && sudo ./pfelk-dashboard-installer.sh


###############################################################################
#                                   START
###############################################################################

ADD ./start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

EXPOSE 5601 9200 9300 9600 5044
VOLUME /var/lib/elasticsearch

CMD [ "/usr/local/bin/start.sh" ]

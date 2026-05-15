FROM verdaccio/verdaccio:6
USER root
# Install @verdaccio/package-filter into the config directory so Verdaccio
# can find it via the 'plugins' config key.
COPY package.json /verdaccio/conf/package.json
RUN cd /verdaccio/conf && npm install --prefer-offline 2>/dev/null || npm install
USER verdaccio

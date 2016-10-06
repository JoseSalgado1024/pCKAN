#!/bin/sh

# URL for the primary database, in the format expected by sqlalchemy (required
# unless linked to a container called 'db')
: ${DATABASE_URL:=}
# URL for solr (required unless linked to a container called 'solr')
: ${SOLR_URL:=}
# Email to which errors should be sent (optional, default: none)
: ${ERROR_EMAIL:=}

: ${DATASTORE_URL_RO:=}
: ${DATASTORE_URL_RW:=}

set -eu

CONFIG="${CKAN_CONFIG}/${CKAN_CONFIG_FILE}"

abort () {
  echo "$@" >&2
  exit 1
}

write_config () {
  CKAN_IP=$(/sbin/ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}')
  "$CKAN_HOME"/bin/paster make-config ckan "$CONFIG"

  "$CKAN_HOME"/bin/paster --plugin=ckan config-tool "$CONFIG" -e \
      "sqlalchemy.url = ${DATABASE_URL}" \
      "solr_url = ${SOLR_URL}" \
      "ckan.storage_path = /var/lib/ckan" \
      "ckan.plugins = stats text_view image_view recline_view hierarchy_display hierarchy_form gobar_theme datastore datapusher"  \
      "ckan.auth.create_user_via_api = false" \
      "ckan.auth.create_user_via_web = false" \
      "ckan.locale_default = es" \
      "email_to = disabled@example.com" \
      "ckan.datapusher.url = http://${CKAN_IP}:8800" \
      "ckan.datastore.write_url = ${DATASTORE_URL_RW}" \
      "ckan.datastore.read_url = ${DATASTORE_URL_RO}" \
      "ckan.max_resource_size = 300" \
      "error_email_from = ckan@$(hostname -f)" \
      "ckan.site_url = http://${CKAN_IP}"

  if [ -n "$ERROR_EMAIL" ]; then
    sed -i -e "s&^#email_to.*&email_to = ${ERROR_EMAIL}&" "$CONFIG"
  fi
}



link_postgres_url () {
  local user=$DB_ENV_POSTGRES_USER
  local pass=$DB_ENV_POSTGRES_PASS
  local db=$DB_ENV_POSTGRES_DB
  local host=$DB_PORT_5432_TCP_ADDR
  local port=$DB_PORT_5432_TCP_PORT
  DATASTORE_URL_RO="postgresql://$datastore_default:${pass}@${host}:${port}/datastore_default"
  DATASTORE_URL_RW="postgresql://${user}:${pass}@${host}:${port}/datastore_default"
  echo "postgresql://${user}:${pass}@${host}:${port}/${db}"
}

link_solr_url () {
  local host=$SOLR_PORT_8983_TCP_ADDR
  local port=$SOLR_PORT_8983_TCP_PORT
  echo "http://${host}:${port}/solr/ckan"
}

# If we don't already have a config file, bootstrap
if [ ! -e "$CONFIG" ]; then
  if [ -z "$DATABASE_URL" ]; then
    if ! DATABASE_URL=$(link_postgres_url); then
      abort "no DATABASE_URL specified and linked container called 'db' was not found"
    fi
  fi
  if [ -z "$SOLR_URL" ]; then
    if ! SOLR_URL=$(link_solr_url); then
      abort "no SOLR_URL specified and linked container called 'solr' was not found"
    fi
  fi
  write_config
  source /etc/ckan_init.d/ckan_helpers.sh
fi
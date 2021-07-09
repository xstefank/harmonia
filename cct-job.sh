#!/bin/bash
#
#
# Continous Component Testing (CCT)
#
set -eo pipefail

usage() {
  local -r script_name=$(basename "${0}")
  echo "${script_name}"
  echo
  echo "ex: ${script_name}"
  echo
  echo Note that this script requires 3 environment properties set:
  echo "  NEXUS_URL - the URL to the Nexus repository"
  echo "  NEXUS_REPO - the name of the repository in the Nexus repository"
  echo "  NEXUS_CREDENTIALS - the credentials for the Nexus repository in form of <username>:<password>"
}

failRequiredProperty() {
  echo "The required environment property ${1} not set - aborting..."
  exit 1
}

executeCommandWithLog() { echo "\$ $@" ; "$@" ; }

if [ "${1}" = '--help' ] || [ "${1}" = '-h' ]; then
  usage
  exit 0
fi

if [ -z "${NEXUS_URL}" ]; then
  failRequiredProperty "NEXUS_URL"
fi

if [ -z "${NEXUS_REPO}" ]; then
  failRequiredProperty "NEXUS_REPO"
fi

if [ -z "${NEXUS_CREDENTIALS}" ]; then
  failRequiredProperty "NEXUS_CREDENTIALS"
fi

# ensure provided JAVA_HOME, if any, is first in PATH
if [ -n "${JAVA_HOME}" ]; then
  export PATH=${JAVA_HOME}/bin:${PATH}
fi

readonly LOCAL_REPO_DIR=${LOCAL_REPO_DIR:-${WORKSPACE}/maven-local-repository}
readonly MEMORY_SETTINGS=${MEMORY_SETTINGS:-'-Xmx1024m -Xms512m -XX:MaxPermSize=256m'}

readonly MAVEN_SETTINGS_XML=${MAVEN_SETTINGS_XML-'/home/master/settings.xml'}
readonly MAVEN_WAGON_HTTP_POOL=${WAGON_HTTP_POOL:-'false'}
readonly MAVEN_WAGON_HTTP_MAX_PER_ROUTE=${MAVEN_WAGON_HTTP_MAX_PER_ROUTE:-'3'}
readonly SUREFIRE_FORKED_PROCESS_TIMEOUT=${SUREFIRE_FORKED_PROCESS_TIMEOUT:-'90000'}
readonly FAIL_AT_THE_END=${FAIL_AT_THE_END:-'-fae'}
readonly RERUN_FAILING_TESTS=${RERUN_FAILING_TESTS:-'0'}

readonly OLD_RELEASES_FOLDER=${OLD_RELEASES_FOLDER:-/opt/old-as-releases}

readonly FOLDER_DOES_NOT_EXIST_ERROR_CODE='3'

if [ -n "${EXECUTOR_NUMBER}" ]; then
  echo -n "Job run by executor ID ${EXECUTOR_NUMBER} "
fi

if [ -n "${WORKSPACE}" ]; then
  echo -n "inside workspace: ${WORKSPACE}"
fi
echo '.'


if [ -z "${MAVEN_HOME}" ] || [ ! -e "${MAVEN_HOME}/bin/mvn" ]; then
    echo "No Maven Home defined - setting to default: ${DEFAULT_MAVEN_HOME}"
    export MAVEN_HOME=${DEFAULT_MAVEN_HOME}
    if [ ! -d  "${DEFAULT_MAVEN_HOME}" ]; then
      echo "No maven install found (${DEFAULT_MAVEN_HOME}) - downloading one:"
      cd "$(pwd)/tools" || exit "${FOLDER_DOES_NOT_EXIST_ERROR_CODE}"
      MAVEN_HOME="$(pwd)/maven"
      export MAVEN_HOME
      export PATH=${MAVEN_HOME}/bin:${PATH}
      bash ./download-maven.sh
      chmod +x ./*/bin/*
      cd - || exit "${FOLDER_DOES_NOT_EXIST_ERROR_CODE}"
    fi

    command -v mvn
    mvn -version
fi

readonly MAVEN_BIN_DIR=${MAVEN_HOME}/bin
echo "Adding ${MAVEN_BIN_DIR} to PATH:${PATH}."
export PATH=${MAVEN_BIN_DIR}:${PATH}

command -v java
java -version
# shellcheck disable=SC2181
if [ "${?}" -ne 0 ]; then
   echo "No JVM provided - aborting..."
   exit 1
fi

command -v mvn
mvn -version
# shellcheck disable=SC2181
if [ "${?}" -ne 0 ]; then
   echo "No MVN provided - aborting..."
   exit 2
fi

mkdir -p "${LOCAL_REPO_DIR}"

#export MAVEN_OPTS="${MAVEN_OPTS} ${MEMORY_SETTINGS}"
# workaround wagon isseu - https://projects.engineering.redhat.com/browse/SET-20
#export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.wagon.http.pool=${MAVEN_WAGON_HTTP_POOL}"
#export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.wagon.httpconnectionManager.maxPerRoute=${MAVEN_WAGON_HTTP_MAX_PER_ROUTE}"
# using project's maven repository
export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.repo.local=${LOCAL_REPO_DIR}"

if [ -n "${MAVEN_SETTINGS_XML}" ]; then
  readonly MAVEN_SETTINGS_XML_OPTION="-s ${MAVEN_SETTINGS_XML}"
else
  readonly MAVEN_SETTINGS_XML_OPTION=''
fi

# TODO refactoring end

curl -L https://github.com/xstefank/heimdall/raw/main/nexus-component-processor-0.0.1-runner --output nexus-component-processor-0.0.1-runner
chmod +x nexus-component-processor-0.0.1-runner
./nexus-component-processor-0.0.1-runner -l $NEXUS_URL -r $NEXUS_REPO -c $NEXUS_CREDENTIALS
cat component-versions.yml

curl -L https://github.com/xstefank/heimdall/raw/main/component-versions-updater-0.0.1-runner --output component-versions-updater-0.0.1-runner
chmod +x component-versions-updater-0.0.1-runner

#./component-versions-updater-0.0.1-runner ./component-versions.yml ./pom.xml


executeCommandWithLog mvn ${MAVEN_GOALS} ${MAVEN_SETTINGS_XML_OPTION} -Pcct

# clean up
rm ./component-versions.yml
rm ./nexus-component-processor-0.0.1-runner
rm ./component-versions-updater-0.0.1-runner


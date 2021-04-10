#####################BEGIN Do not modify this file, your changes should be in your apps make.sh########################
APP=${APP:=$(echo "STOP you have not set your APP env yet")}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:=001518439974}
ECR_APP=${ECR_APP:=${APP}}
ECR_REGION=${ECR_REGION:=us-west-1}
ECR_REPO=${ECR_REPO:=${AWS_ACCOUNT_ID}.dkr.ecr.${ECR_REGION}.amazonaws.com}

LINT=${LINT:=false} #Valid options are python,python2019,node,false
#When we overrite an image tag, how many previous version should we keep
ARCHIVE_LIMIT=4
ARCHIVE=${ARCHIVE:=true}

DOCKER_EXPERIMENTAL=$(docker version -f '{{.Server.Experimental}}')
DOCKER_FILE=${DOCKER_FILE:=Dockerfile}
DOCKER_BUILD_ARGS=${DOCKER_BUILD_ARGS:=}

#These are set via runtime args
BUILD_NUM="local-$(date +%s)"
CI_BUILD_URL='localhost'
BUILD_TIME=$(date +%s)
GIT_BRANCH=${GIT_BRANCH:=$(git branch --show-current)}
REGION=us-west-1
VPC=false
BUILD_APP=${BUILD_APP:=true}
DEPLOY_APP=${DEPLOY_APP:=false}
ECS_RECYCLE=${ECS_RECYCLE:=true}
UNIT_TEST=${UNIT_TEST:=true}
DRY_RUN=${DRY_RUN:=false}
USE_CACHE=${USE_CACHE:=false}
GIT_SHA=$(git rev-parse HEAD)
CURRENT_TAG=${GIT_SHA}
DEBUG=false
IS_CIRCLECI=false
IS_LOCAL=false
NO_LINT=${NO_LINT:=false}
NO_SQUASH=${NO_SQUASH:=true}
REBUILD_BASE=${REBUILD_BASE:=false}
PROMOTE_BUILD=${PROMOTE_BUILD:=false}
AUTH_ONLY=${AUTH_ONLY:=false}
#The next two are only used for base images
BASE_IMAGE=${BASE_IMAGE:=false}
BASE_IMAGE_SHA=${BASE_IMAGE_SHA:=false}

TIME_STAMP=$(date +%Y-%m-%d_%H-%M-%S)


usage(){
    echo "Usage: $0 [--no-tests] [--no-deploy] [--target={swimlane}]"
    echo ""
    echo "--target specify swimlane to deploy to. Comma separated for multiple. Available options: {dev-multi,dev-blueprint,stage-multi,prod-adecco,prod-preview,prod-multi,prod-sandbox}"
    echo "--archive rotate target app for rollbacks. Defaults: true"
    echo "--auth-only Don't build, test or deploy, just login to ECR. This is helpful when working with docker-compose"
    echo "--promote Instead of building, testing and deploying we promote an image. --target stage promotes dev image to stage, --target prod promotes stage to prod.  This just adds tags onto an existing image to speedup deployments."
    echo "--use-cache Skip the build and instead use the current git sha to find a prebuilt image."
    echo "--no-build Do not run the actual build. This is helpful if you've already built and want to just test or deploy instead."
    echo "--no-deploy Do not deploy, if used with target works as DRY run"
    echo "--no-lint Skip running code linter"
    echo "--no-squash Skip running docker squash to reduce image size"
    echo "--no-tests Skip running Unit Test & Code Coverage"
    echo "--docker-file Dockerfile to use (Default: Dockerfile)"
    echo "--help, -h Show this help screen"
    echo "--debug Show commands"
    exit
}

optspec=":hd-:"
while getopts "$optspec" optchar; do
        case "${optchar}" in
                -)
                        case "${OPTARG}" in
                                archive)
                                        ARCHIVE=true
                                        ;;
                                auth-only)
                                        AUTH_ONLY=true
                                        ;;
                                no-build)
                                        BUILD_APP=false
                                        ;;
                                promote)
                                        PROMOTE_BUILD=true
                                        ;;
                                no-deploy|dry-run|dry_run|dry)
                                        DRY_RUN=true
                                        ;;
                                no-lint|no-linter)
                                        LINT=false
                                        ;;
                                no-squash)
                                        NO_SQUASH=true
                                        ;;
                                squash)
                                        NO_SQUASH=false
                                        ;;
                                no-tests|no-test)
                                        UNIT_TEST=false
                                        ;;
                                docker-file)
                                        DOCKER_FILE="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                                        ;;
                                docker-file=*)
                                        DOCKER_FILE=${OPTARG#*=}
                                        ;;
                                debug)
                                        DEBUG=true
                                        ;;
                                use-cache)
                                        USE_CACHE=true
                                        ;;
                                help)
                                        usage
                                        ;;
                                target)
                                        TARGET="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                                        CURRENT_TAG=${TARGET}
                                        DEPLOY_APP=true
                                        ;;
                                target=*)
                                        TARGET=${OPTARG#*=}
                                        CURRENT_TAG=${TARGET}
                                        DEPLOY_APP=true
                                        ;;
                                *)
                                        if [ "$OPTERR" = 1 ] && [ "${optspec:0:1}" != ":" ]; then
                                                echo "Unknown option --${OPTARG}" >&2
                                        fi
                                        ;;
                        esac;;
                h)
                        usage
                        ;;
                d)
                        DEBUG=true
                        ;;
                *)
                        if [ "$OPTERR" != 1 ] || [ "${optspec:0:1}" = ":" ]; then
                                echo "Non-option argument: '-${OPTARG}'" >&2
                        fi
                        ;;
        esac
done

if [[ ${DEBUG} == true ]]; then
    set -x
    printenv |sort
fi


if [ -z "$(LC_ALL=C type -t ecr_upload)" ]; then

    ecr_upload(){
        if [[ "${DEPLOY_APP}" == true ]]; then
            ARCHIVE=false
            echo -e "\n#### Begin ECR Upload of ${APP}: `date +%X` ####\n"

            #Apply all target tags needed


            GIT_BRANCH=${GIT_BRANCH//\//_}
            if [[ ${BASE_IMAGE} != false ]]
            then
                ecr_tag_push ${APP} ${ECR_APP} retain.${BASE_IMAGE_SHA},${BASE_IMAGE_SHA},process.this.${GIT_BRANCH}.${GIT_SHA}.${BUILD_NUM}.${TIME_STAMP},${GIT_SHA}.${BUILD_NUM},${GIT_BRANCH}_branch_built_at_${TIME_STAMP}
                echo -e "\n# Pushed Base Image to us-west-1 ${APP}: `date +%X` ####\n"
            else
                ecr_tag_push ${APP} ${ECR_APP} process.this.${GIT_BRANCH}.${GIT_SHA}.${BUILD_NUM}.${TIME_STAMP},${GIT_SHA}.${BUILD_NUM},${GIT_BRANCH}_branch_built_at_${TIME_STAMP}
                echo -e "\n# Pushed to us-west-1 ${APP}: `date +%X` ####\n"
    
            fi

            echo -e "\n#### Done ECR Upload of ${APP}: `date +%X` ####\n"
        fi
    }

fi

if [ -z "$(LC_ALL=C type -t ecr_tag_push)" ]; then

    ecr_tag_push(){
        _APP_=$1
        _ECR_APP_=$2
        TAGS=$3

        for TAG in ${TAGS//,/ }; do
            #Before we tag and push, lets archive the current tags if they start
            # with dev, stage or prod
            if [[ "${TAG}" =~ ^(dev|stage|prod) ]] && [[ ${ARCHIVE} == true ]] ; then
                archive_image ${_ECR_APP_} ${TAG}
            fi

            tag="docker tag ${_APP_}:${GIT_SHA} ${ECR_REPO}/${_ECR_APP_}:${TAG}"
            push="docker push ${ECR_REPO}/${_ECR_APP_}:${TAG}"

            if [[ ${DRY_RUN} == true ]];then
                echo -e "DRY RUN: ${tag} && ${push}"
            else
                echo -e "${tag} && ${push}"
                ${tag} && ${push}  > /dev/null
            fi

            if [[ $? != 0 ]]; then
                echo "tag & push failed!"
                post_run 99
            fi
        done
    }

fi




# Override to add your own pre_run
if [ -z "$(LC_ALL=C type -t pre_run_hook)" ]; then
    pre_run_hook(){
        IGNORE_THIS_HOOK=true
    }
fi

# Override to add your own post_run
if [ -z "$(LC_ALL=C type -t post_run_hook)" ]; then
    post_run_hook(){
        IGNORE_THIS_HOOK=true
    }
fi

if [ -z "$(LC_ALL=C type -t pre_run)" ]; then

    pre_run(){
        pre_run_hook
        # Detect Build Number CIRCLE_BUILD_NUM
        if [[ ! -z ${CIRCLE_BUILD_NUM} ]]; then
            echo "Building For CircleCI"
            BUILD_NUM=${CIRCLE_BUILD_NUM}
            CI_BUILD_URL=${CIRCLE_BUILD_URL}
            PR_URL=${CIRCLE_PULL_REQUEST}
            BUILD_USER=${CIRCLE_USERNAME}
            IS_CIRCLECI=true
        else
            echo "Building For local"
            IS_LOCAL=true
            BUILD_USER=${USER}
        fi
        
        APP_VERSION=${GIT_SHA}.${BUILD_NUM}


        if [[ ${NO_LINT} != true ]]; then
            generic_lint
        fi

    }

fi

if [ -z "$(LC_ALL=C type -t generic_lint)" ]; then

    generic_lint(){
        if [[ ${LINT} != "false" ]]; then
            echo -e "#### Begin Linting ${LINT} `date +%X` ####\n"
            
            if [[ ${LINT} == "python" || ${LINT} == "python2019" ]]; then
                if [[ -f "requirements-dev.txt" ]]; then
                    virtualenv /tmp/ENV-$$
                    source /tmp/ENV-$$/bin/activate
                    pip3 install -r requirements-dev.txt
                fi
            fi
            if [[ ${LINT} == "python" ]]; then
                echo "Running yapf"
                yapf -rpd \
                    --exclude=ENV \
                    --exclude=env \
                    --exclude=.docker/src \
                    --exclude=base \
                    --exclude=.docker/packages \
                    .

                if [[ $? != 0 ]]; then
                  echo -e "yapf failed!"
                  post_run 2
                fi
                echo "Running flake8"
                flake8 .

                if [[ $? != 0 ]]; then
                  echo -e "flake8 failed!"
                  post_run 3
                fi
            elif [[ ${LINT} == "python2019" ]]; then
                echo "Running Black"
                black --check .

                if [[ $? != 0 ]]; then
                  echo -e "black linting failed!"
                  post_run 2
                fi
                echo "Running flake8"
                flake8 .

                if [[ $? != 0 ]]; then
                  echo -e "flake8 failed!"
                  post_run 3
                fi
                echo "Running MyPy"
                mypy .

                if [[ $? != 0 ]]; then
                  echo -e "mypy check failed!"
                  post_run 4
                fi

            fi
            echo -e "#### End Linting ${LINT} `date +%X` ####\n"
        fi
    }

fi

if [ -z "$(LC_ALL=C type -t unit_test)" ]; then

    unit_test(){
        #Should we run unit tests?
        if [[ "${UNIT_TEST}" == true ]]; then
                echo -e "#### Override the unit test function in your $0 script to implement unit tests. `date +%X` ####\n"
        fi
    }

fi

if [ -z "$(LC_ALL=C type -t ecr_auth)" ]; then

    ecr_auth(){
        #first thing we must do is login
        command="aws ecr get-login --no-include-email --region us-west-1"
        echo "Logging into ECR ${command}"
        eval `${command}`


        if [[ $? != 0 ]]; then
            echo "Check your AWS Permissions"
            post_run 3
        fi
    }

fi


if [ -z "$(LC_ALL=C type -t build)" ]; then

    build(){
        ecr_auth
        if [[ "${BUILD_APP}" == true ]]; then

            #TODO make --pull a cache arg
            DOCKER_BUILD_ARGS+=" --pull --compress"
            
            if [[ ${NO_SQUASH} == "false" ]]; then            
                if [[ ${DOCKER_EXPERIMENTAL} == "true" ]]; then
                    DOCKER_BUILD_ARGS+=" --squash "
                fi
            fi
            echo -e "#### Begin Building ${APP}:${CURRENT_TAG} `date +%X` ####\n"
            if [[ ${USE_CACHE} == "true" ]]; then
                if [[ "$(docker images -q ${APP}:${GIT_SHA} 2> /dev/null)" == "" ]]; then
                    docker pull ${ECR_REPO}/${ECR_APP}:${GIT_SHA}
                    docker tag ${ECR_REPO}/${ECR_APP}:${GIT_SHA} ${APP}:${GIT_SHA}
                fi
            else
            
                DOCKER_BUILD_CMD="docker build ${DOCKER_BUILD_ARGS} \
                    --build-arg APP_VERSION="${APP_VERSION}" \
                    --build-arg BUILD_TIME="${BUILD_TIME}" \
                    --build-arg GIT_BRANCH="${GIT_BRANCH}" \
                    -f ${DOCKER_FILE} \
                    -t ${APP}:${GIT_SHA} \
                    -t ${APP} ."
                
                echo "# ${DOCKER_BUILD_CMD}"
                ${DOCKER_BUILD_CMD} 

                if [[ $? != 0 ]]; then
                    echo "${APP}:${GIT_SHA} Build failed, bailing"
                    echo "${APP} Build failed, bailing"
                    post_run 99
                fi

                # Lets Squash it if we can
                # pip install docker-squash #This is included in circle_docker_base
                if [[ ${NO_SQUASH} == "false" ]]; then
                    if hash docker-squash 2>/dev/null; then
                        echo "Compressing Image via docker-squash"
                        docker-squash -t ${APP}:${GIT_SHA} ${APP}:latest
                    fi
                fi   
            fi

            echo -e "#### Done Building ${APP}:${CURRENT_TAG} `date +%X` ####\n"
        fi
    }

fi

if [ -z "$(LC_ALL=C type -t promote_build)" ]; then

    promote_build(){
        ecr_auth
        if [[ "${PROMOTE_BUILD}" == true ]]; then
            if [[ ${GIT_BRANCH} == "master" ]] || [[ ${GIT_BRANCH} == "main" ]]; then
                add_ecr_tag ${ECR_APP} dev process.this.${GIT_BRANCH}.${GIT_SHA}.${BUILD_NUM}.${TIME_STAMP}
                add_ecr_tag ${ECR_APP} dev ${GIT_SHA}.${BUILD_NUM}
                add_ecr_tag ${ECR_APP} dev ${GIT_BRANCH}_branch_promoted_at_${TIME_STAMP}

            elif [[ ${GIT_BRANCH} == "deploy" ]]; then
                add_ecr_tag ${ECR_APP} stage process.this.${GIT_BRANCH}.${GIT_SHA}.${BUILD_NUM}.${TIME_STAMP}
                add_ecr_tag ${ECR_APP} stage ${GIT_SHA}.${BUILD_NUM}
                add_ecr_tag ${ECR_APP} stage ${GIT_BRANCH}_branch_promoted_at_${TIME_STAMP}
            fi
        fi
    }

fi

if [ -z "$(LC_ALL=C type -t add_ecr_tag)" ]; then
    #This function adds a tag to an existing image, this can be very useful
    # when promoting an image to another environment

    add_ecr_tag(){
        local ECR_REPO=${1}
        local SRC_TAG=${2}
        local DEST_TAG=${3}

        local MANIFEST=$(aws ecr batch-get-image \
            --repository-name ${ECR_REPO}  \
            --image-ids imageTag=${SRC_TAG} \
            --region ${ECR_REGION} \
            --query 'images[].imageManifest' \
            --output text \
        )

        local IMAGE_DIGEST=$(echo ${MANIFEST} | jq '.config.digest')

        if [ ! -z "${MANIFEST}" ]; then

            tag_command="aws ecr put-image \
              --repository-name ${ECR_REPO} \
              --region ${ECR_REGION} \
              --image-tag ${DEST_TAG} \
              --image-manifest '${MANIFEST}'"

            if [[ ${DRY_RUN} == true ]];then
                echo -e "DRY RUN: ${tag_command}"
            else
                aws ecr put-image \
                  --repository-name ${ECR_REPO} \
                  --image-tag ${DEST_TAG} \
                  --region=${ECR_REGION} \
                  --image-manifest "$MANIFEST" > /dev/null

                TAG_RESULT=$?
                if [[ ${TAG_RESULT} == 255 ]];then
                    echo "Tag ${DEST_TAG} already exists on ${ECR_REPO}:${SRC_TAG} in ${ECR_REGION}"
                else
                    echo "Added tag ${DEST_TAG} to image ${ECR_REPO}:${SRC_TAG} in ${ECR_REGION}"
                fi
            fi
        else
            echo "Failed to find ${ECR_REPO}:${SRC_TAG}"
        fi

    }
fi


if [ -z "$(LC_ALL=C type -t post_run)" ]; then

    post_run(){
        EXIT_CODE=$1
        t=$(timer)
        print_section "Start post_run: ${t}"
        post_run_hook ${EXIT_CODE}
        # If you need to do cleanup, do it here
        if [[ -d ENV-$$ ]]; then
            echo "Removing virtualenv dir: /tmp/ENV-$$"
            rm -Rf /tmp/ENV-$$
        fi

        elapsed=$(timer $t)
        print_section "post_run finished in ${elapsed}"

        exit ${EXIT_CODE}
    }

fi


#Gets a parameter from AWS SSM
if [ -z "$(LC_ALL=C type -t get_ssm_param)" ]; then

    get_ssm_param(){
        PARAM_KEY=$1
        command -v aws >/dev/null 2>&1 || { echo >&2 "I require aws but it's not installed.  Aborting."; post_run 1; }
        aws ssm get-parameters --with-decryption --names ${PARAM_KEY} --region us-west-1 --query 'Parameters[0].[Value]' --output text
    }

fi


if [ -z "$(LC_ALL=C type -t get_deployment_key)" ]; then

    get_deployment_key(){
        # Update with following command to preserve newlines
        # aws ssm put-parameter --name /devops/cicd/deployment_key --type "SecureString"  --overwrite --value="$(cat deploy_key)"

        get_ssm_param  /devops/cicd/deployment_key > deploy_key
        export OLD_SSH_AUTH_SOCK=${SSH_AUTH_SOCK}
        unset SSH_AUTH_SOCK
    }
fi

print_section(){
    _msg=$1
    set +x
    
    if [ ! -z ${TERM} ]; then
        termwidth="$(tput cols 2> /dev/null || echo 200)"
    else
        termwidth="200"
    fi
    mid_padding="$(printf '%0.1s' ' '{1..500})"
    padding="$(printf '%0.1s' -{1..500})"
    printf '%*.*s\n' 0 "${termwidth}" "$padding"
    printf '%*.*s %s %*.*s\n' 0 "$(((termwidth-2-${#1})/2))" "$mid_padding" "$_msg" 0 "$(((termwidth-1-${#1})/2))" "$mid_padding"
    printf '%*.*s\n' 0 "${termwidth}" "$padding"
}

function timer()
{
    if [[ $# -eq 0 ]]; then
        echo $(date '+%s')
    else
        local  stime=$1
        etime=$(date '+%s')
        if [[ -z "$stime" ]]; then stime=$etime; fi
        dt=$((etime - stime))
        ds=$((dt % 60))
        dm=$(((dt / 60) % 60))
        dh=$((dt / 3600))
        printf '%d:%02d:%02d' $dh $dm $ds
    fi
}

rawurlencode() {
  # urlencode <string>
  old_lc_collate=$LC_COLLATE
  LC_COLLATE=C
  
  local length="${#1}"
  for (( i = 0; i < length; i++ )); do
      local c="${1:i:1}"
      case $c in
          [a-zA-Z0-9.~_-]) printf "$c" ;;
          *) printf '%%%02X' "'$c" ;;
      esac
  done
  
  LC_COLLATE=$old_lc_collate
}

trap ctrl_c INT

function ctrl_c() {
        post_run 10
}

#By default pre_run will do the following
# > start the db for unit testing if POSTGRES_TESTS is true
# > Run the linters for python or node apps
if [ -z "$(LC_ALL=C type -t generic_cicd)" ]; then

    generic_cicd(){
        # Start timer
        t=$(timer)
        print_section "Start pre_run: `date +%X`"
        pre_run
        elapsed=$(timer $t)
        print_section "pre_run finished in ${elapsed}"
        if [[ "${AUTH_ONLY}" == true ]]; then
            print_section "Logging into ECR us-west-1 `date +%X`"
            ecr_auth
            rm ${FUNCS_SCRIPT}  || true
            return
        elif [[ "${PROMOTE_BUILD}" == true ]]; then
            t=$(timer)
            print_section "Start Promote ${APP}:${TARGET}/${GIT_SHA} `date +%X`"
            promote_build
            elapsed=$(timer $t)
            print_section "Promote ${APP}:${TARGET}/${GIT_SHA} finished in ${elapsed}"
            rm ${FUNCS_SCRIPT}  || true
            return
        elif [[ "${BUILD_APP}" == true ]]; then
            t=$(timer)
            print_section "Start build ${APP}:${TARGET}/${GIT_SHA} `date +%X`"
            build
            elapsed=$(timer $t)
            print_section "build ${APP}:${TARGET}/${GIT_SHA} finished in ${elapsed}"
        fi

        #Should we run unit tests?
        if [[ "${UNIT_TEST}" == true ]]; then
            t=$(timer)
            print_section "Start Unit Tests: `date +%X`"
            tempresults=`basename $0`
            TMPFILE=`mktemp /tmp/${tempresults}.XXXXXX` || post_run 1
            unit_test |tee $TMPFILE
            UNIT_TEST_RESULT=${PIPESTATUS[0]}


            elapsed=$(timer $t)
            print_section "Unit Tests finished in ${elapsed}"

            if [[ ${UNIT_TEST_RESULT} != 0 ]]; then
              post_run 99
            fi
        fi

        #Are we deploying also?
        if [[ "${DEPLOY_APP}" == true ]]; then
            t=$(timer)
            print_section "Pushing to ECR: `date +%X`"
            ecr_upload
            elapsed=$(timer $t)
            print_section "deploy finished in ${elapsed}"
        fi

        post_run 0
    }
fi

generic_cicd

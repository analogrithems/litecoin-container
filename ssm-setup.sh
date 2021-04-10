#!/bin/bash

yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
mv /etc/amazon/ssm/seelog.xml.template /etc/amazon/ssm/seelog.xml

# This is how the container instance will appear in the aws console
INSTANCE_NAME=${CLUSTER}-${TASK_NAME}
if [[ ${NGINX_HOST} ]]; then
    INSTANCE_NAME="${INSTANCE_NAME}-nginx"
fi

# Getting your containers to use ssm requires an activation code 
# that we use to register our instances with AWS System manager
ssm_setup(){

    read -r -d '' TMP_TAGS <<EOF
    [
    {"Key":"APP_NAME","Value":"${APP_NAME}"},
    {"Key":"APP_VERSION","Value":"${APP_VERSION}"},
    {"Key":"CLUSTER","Value":"${CLUSTER}"},
    {"Key":"HOSTNAME","Value":"${HOSTNAME}"},
    {"Key":"TASK_NAME","Value":"${TASK_NAME}"}
    ]
EOF

    IAM_ROLE=${IAM_ROLE:=AutomationServiceRole}
    TMP_TAGS=${TMP_TAGS//[$'\t\r\n ']}
    read -r -d '' ACTIVATION_CMD <<EOF
        aws ssm create-activation \
          --default-instance-name=${INSTANCE_NAME} \
          --description=${INSTANCE_NAME} \
          --iam-role=${IAM_ROLE} \
          --registration-limit=1 \
          --tags=${TMP_TAGS} \
          --region=${AWS_DEFAULT_REGION}
EOF

    ACTIVATION=$(${ACTIVATION_CMD})
    if [[ $? != 0 ]]; then
      echo "Error creating SSM activation.  Cmd: ${ACTIVATION_CMD}, Result: ${SSM_AGENT_REGISTER}"
    fi

    echo "[ssm_setup] Created SSM activation with Instance Name ${INSTANCE_NAME}"

    ActivationId=$( jq -r  '.ActivationId' <<< "${ACTIVATION}" )
    ActivationCode=$( jq -r  '.ActivationCode' <<< "${ACTIVATION}" )

    SSM_AGENT_CMD="amazon-ssm-agent \
      -register \
      -code ${ActivationCode} \
      -id ${ActivationId} \
      -region ${AWS_DEFAULT_REGION} 2>&1"

    SSM_AGENT_REGISTER=$(${SSM_AGENT_CMD})
    if [[ $? != 0 ]]; then
      echo "Error creating SSM registration! Cmd: ${SSM_AGENT_CMD}, Result: ${SSM_AGENT_REGISTER}"
    fi
    echo "[ssm_setup] Registering Container with SSM"
}

# To make sure we dont get a bunch of instances hanging around after we stop
# this container, we make sure to remove the activation and registration on shutdown
ssm_cleanup()
{
    echo "[ssm_cleanup] Terminated the SSM agent"
    # Now lets try to deregister

    aws ssm deregister-managed-instance --region ${AWS_DEFAULT_REGION} --instance-id ${INSTANCE_ID} 2>&1
    echo "[ssm_cleanup] Removed instance registration ${INSTANCE_NAME} (${INSTANCE_ID}) (exit code: $?)"

    aws ssm delete-activation --region ${AWS_DEFAULT_REGION} --activation-id ${ActivationId} 2>&1
    echo "[ssm_cleanup] Removed activation ${ActivationId} (exit code: $?)"
}

#This function is called when a term or int signal is sent.  It kills ssm-agent
# then calls the ssm_cleanup
handle_term()
{
    INSTANCE_ID=$(jq -r .ManagedInstanceID < /var/lib/amazon/ssm/registration)
    echo "[handle_term] Recieved the kill, stopping SSM Agent and Cleaning up ${INSTANCE_NAME} (${INSTANCE_ID})"
    kill -TERM "${child_pid}" 2>/dev/null
    ssm_cleanup # This will remove the registration and cleanup the activation
}

printf "Starting AWS SSM Agent shell container for %s with version: %s\n" "${APP_NAME}" "${APP_VERSION}"

trap 'handle_term' TERM INT
#Set our prompt
echo 'export PS1="\u@${CLUSTER}/${APP_NAME}:\w\$ "' >> /etc/bashrc
ssm_setup #This creates the activation code and registers the instance

# AWS SSM-Agent likes to write logs to serial port, symlinking it to stdout
echo "[ssm-agent] Starting SSM Agent"
/usr/bin/amazon-ssm-agent &

child_pid=$!
wait ${child_pid}
trap - TERM INT
wait ${child_pid}

exit

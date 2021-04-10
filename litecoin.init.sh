#!/bin/sh
set -e

if [ ! -e "/litecoin/litecoin.conf" ]; then
    touch /litecoin/litecoin.conf

	if [ -z ${ENABLE_WALLET:+x} ]; then
	    echo "disablewallet=1" >> "/litecoin/litecoin.conf"
	fi
	
	if [ ! -z ${MAX_CONNECTIONS:+x} ]; then
	    echo "maxconnections=${MAX_CONNECTIONS}" >> "/litecoin/litecoin.conf"
	fi
	
	if [ ! -z ${RPC_SERVER:+x} ]; then	
	    echo "server=1" >> "/litecoin/litecoin.conf"
	    echo "rpcuser=${RPC_USER}" >> "/litecoin/litecoin.conf"
	    echo "rpcpassword=${RPC_PASSWORD}" >> "/litecoin/litecoin.conf"
	fi
fi

echo "################################################"
echo "# Configuration used: /litecoin/litecoin.conf  #"
echo "################################################"
echo ""
cat /litecoin/litecoin.conf
echo ""
echo "################################################"



#####################################################################
# Function to handle handling SIGTERM and passing SIGQUIT to litecoin parent PID
#####################################################################
function handle_term() {
    echo "Catching SIGTERM and sending SIGQUIT to Litecoin daemon (reference: https://litecoin.info/index.php/Litecoin.conf)"
    kill -QUIT "${litecoin_pid}" 2>/dev/null
}
trap handle_term SIGTERM SIGINT

echo "Starting Litecoin process as user: $(whoami)"
litecoind -datadir=/litecoin -conf=/litecoin/litecoin.conf -pid=/var/tmp/litecoin.pid -printtoconsole "$@"

# Fetch pid for when we need to shutdown
litecoin_pid=$( cat /var/tmp/litecoin.pid | head -1 )
echo "litecoin process started with pid: ${litecoin_pid}"

#####################################################################
# Need to introduce this method to track the actual web server process
# since when using "su" the process started is NOT a child process and therefore
# you cannot "wait" on that pid. Using "tail" to do the needed process-waiting 
# then "wait" on the backgrounded tail command process seems to work fine.
#####################################################################
tail --pid=${litecoin_pid} -f /dev/null &
child_pid=$!
wait ${child_pid}

trap - SIGTERM SIGINT
wait ${child_pid} > /dev/null 2>&1

printf "Stopping Litecoin V.${LITECOIN_VERSION}\n"
exit 0
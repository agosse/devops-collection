#!/bin/bash
#set -x

# Zeusbench Options
ZB_CMD='/opt/riverbed/admin/bin/zeusbench'
#ZB_CMD='/usr/local/zeus/admin/bin/zeusbench'

# The length of time the test runs for.
RUNTIME=30

# Timeout period.
TIMEOUT=40

# The number of idle connections.
IDLE_CONC=100

# The length of time between idle gets.
IDLE_LINGER=1000

# The number of busy connections
BUSY_CONC=1000

# SSH Options
SSH_USER='root'

# Array of SSH Hosts (client)
SSH_HOSTS=()

# Array of SUT URLs
SUT_URL=()

function usage {
echo ""
echo "zb_conc.sh"
echo ""
echo "Usage: zb_conc.sh [options]"
echo ""
echo "Options:"
echo ""
echo "  --runtime=,-r      Length of time to run for (int | \"f\")."
echo "  --idle-conc=,-i    Number of concurrent idle connections."
echo "  --idle-linger=,-l  Length of time between idle GETs."
echo "  --busy-conc=,-b    Number of concurrent busy connections."
echo "  --ssh-user=,-u     SSH user name."
echo "  --ssh-host=,-h     SSH host(s) - use at least once."
echo "  --sut-url=,-s      The URL of the system(s) under test - use at least once."
echo ""
}

# Regex pattern for a URL.
URL_RE="^(ht|f)tp(s?)\:\/\/[0-9a-zA-Z]([-.\w]*[0-9a-zA-Z])*(:(0-9)*)*(\/?)([a-zA-Z0-9\-‌​\.\?\,\'\/\\\+&amp;%\$#_]*)?$"

# Multiple SSH Hosts or URLs?
# New array: ARRAY=()
# Array append: ARRAY+=('foo')
# Array dereference (the whole thing): "${ARRAY[@]}"

params=`getopt -o r:,i:,l:,b:,u:,h:,s: -l runtime:,idle-conc:,idle-linger:,busy-conc:,ssh-user:,ssh-host:,sut-url: -- "$@"`

eval set -- "$params"
while true; do
    case "$1" in
        --runtime ) RUNTIME="$2"; shift 2 ;;
        --idle-conc ) IDLE_CONC="$2"; shift 2 ;;
        --idle-linger ) IDLE_LINGER="$2"; shift 2 ;;
        --busy-conc ) BUSY_CONC="$2"; shift 2 ;;
        --ssh-user ) SSH_USER="$2"; shift 2 ;;
        --ssh-host ) SSH_HOSTS="$2"; shift 2 ;;
        --sut-url ) SUT_URLS+=("$2"); shift 2 ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
done

echo "Runtime: ${RUNTIME}"

echo "Hosts: ${SSH_HOSTS[@]}"
if [ ${#SSH_HOSTS[@]} -eq 0 ]; then
	echo ""
	echo "ERROR: No client machines specified.  See --ssh-hosts."
	usage
	exit 1
fi

if [ ${#SUT_URLS[@]} -eq 0 ]; then
	echo ""
	echo "ERROR: No SUT URLs specified. See --sut-urls."
	usage
	exit 1
fi


# The date today
DATE_STR=`date +%F.%H.%M.%S`

# PERF Options
PERF_TIMEOUT="$((${TIMEOUT}-1))"
PERF_OUT="-o perf.data.poll.${IPS}.${DATE_STR}"
PERF_CMD="perf record ${PERF_OUT} -a -g -e cpu-cycles sleep ${PERF_TIMEOUT}"

# TIME_WAIT Command
TW_CMD="${SSH_CMD}
while [ \"\$tw\" != \"0\" ]; do
	tw=\`grep tw /proc/net/sockstat | cut -d \" \" -f 7\`;
	echo \$tw;
done; sleep 1"

# Options common to both zeusbenches
ZB_COMMON="${ZB_CMD}"
#ZB_COMMON="${ZB_COMMON} -v"
ZB_COMMON="${ZB_COMMON} -k"
ZB_COMMON="${ZB_COMMON} -t ${RUNTIME}"


for SSH_HOST in SSH_HOSTS; do

	SSH_CMD="/usr/bin/ssh -l ${SSH_USER} ${SSH_HOST}"

	# Idle pattern:
	# zeusbench -v -k -t 5 -c 5 -l 1000 <target>
	# Produces: 5 concurrent x 5 seconds with 1s sleep between gets = 25 requests
	# Options specific to the idle zeusbench
	ZB_IDLE="${ZB_COMMON}"
	ZB_IDLE="${ZB_IDLE} -c ${IDLE_CONC}"
	ZB_IDLE="${ZB_IDLE} -l ${IDLE_LINGER}"

	# Busy pattern:
	# zeusbench -v -k -t 5 -c 10000 <target>
	# Produces: 10000 concurrent x 5 seconds with no sleep between gets = lots
	# Options specific to the busy zeusbench
	ZB_BUSY="${ZB_COMMON}"
	ZB_BUSY="${ZB_BUSY} -c ${BUSY_CONC}"

	# Idle connections
	IDLE="${SSH_CMD} ${ZB_IDLE} ${SUT_URLS[@]}"

	# Busy connections
	BUSY="${SSH_CMD} ${ZB_BUSY} ${SUT_URLS[@]}"

	echo "Starting idle connections..."
	${IDLE} & IDLE_PIDS+=$! # Store the PIDs...
	echo "Starting busy connections..."
	${BUSY} & BUSY_PID+=$!

	# Wait for each process to return.
	#wait "${IDLE_PID}"
	#wait "${BUSY_PID}"
	echo "Done."

done

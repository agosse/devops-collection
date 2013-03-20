#!/bin/bash

# Defaults

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
SSH_HOST='testbox'

PARAMS=`getopt -o r:,i:,l:,b:,u:,h:,s: \
-l runtime:,idle-conc:,idle-linger:,busy-conc:,ssh-user:,ssh-host:,sut-url: \
-- "$@"`

eval set -- "${PARAMS}"
while true; do
	case "$1" in
		--runtime ) RUNTIME="$2"; shift 2 ;;
		--idle-conc ) IDLE_CONC="$2"; shift 2 ;;
		--idle-linger ) IDLE_LINGER="$2"; shift 2 ;;
		--busy-conc ) BUSY_CONC="$2"; shift 2 ;;
		--ssh-user ) SSH_USER="$2"; shift 2 ;;
		--ssh-host ) SSH_HOST="$2"; shift 2 ;;
		--sut-url ) ="$2"; shift 2 ;;
		-- ) shift; break ;;
		* ) break ;;
	esac
done

SSH_CMD="/usr/bin/ssh -l ${SSH_USER} ${SSH_HOST}"

# The Date
DATE_STR=`date +%F.%H.%M.%S`

# System Under Test URL
SUT_URL='http://localhost/'

# PERF Options
PERF_TIMEOUT="$((${TIMEOUT}-1))"
PERF_OUT="-o perf.data.poll.${IPS}.${DATE_STR}"
PERF_CMD="perf record ${PERF_OUT} -a -g -e cpu-cycles sleep ${PERF_TIMEOUT}"

# TIME_WAIT Command
#TW_CMD="${SSH_CMD}
#while [ \"\$tw\" != \"0\" ];\
#do\
#tw=\`grep tw /proc/net/sockstat |\
#cut -d \" \" -f 7`;\
#echo \$tw;\
#sleep 1;

# Zeusbench Options
ZB_CMD='/opt/riverbed/admin/bin/zeusbench'
#ZB_CMD='/usr/local/zeus/admin/bin/zeusbench'

# Options common to both zeusbenches
ZB_COMMON="${ZB_CMD}"
#ZB_COMMON="${ZB_COMMON} -v"
ZB_COMMON="${ZB_COMMON} -k"
ZB_COMMON="${ZB_COMMON} -t ${RUNTIME}"

# Options specific to the idle zeusbench
ZB_IDLE="${ZB_COMMON}"
ZB_IDLE="${ZB_IDLE} -c ${IDLE_CONC}"
ZB_IDLE="${ZB_IDLE} -l ${IDLE_LINGER}"

# Options specific to the busy zeusbench
ZB_BUSY="${ZB_COMMON}"
ZB_BUSY="${ZB_BUSY} -c ${BUSY_CONC}"

# Idle pattern:
# zeusbench -v -k -t 5 -c 5 -l 1000 <target>
# Produces: 5 concurrent x 5 seconds with 1s sleep between gets = 25 requests

# Busy pattern:
# zeusbench -v -k -t 5 -c 10000 <target>
# Produces: 10000 concurrent x 5 seconds with no sleep between gets = lots

# Idle connections
IDLE="${SSH_CMD} ${ZB_IDLE} ${SUT_URL}"

# Busy connections
BUSY="${SSH_CMD} ${ZB_BUSY} ${SUT_URL}"

echo "Starting idle connections..."
${IDLE} & IDLE_PID=$! # Store the PIDs...
echo "Starting busy connections..."
${BUSY} & BUSY_PID=$!

# Wait for each process to return.
wait "${IDLE_PID}"
wait "${BUSY_PID}"
echo "Done."

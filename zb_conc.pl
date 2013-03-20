#!/usr/bin/perl -w
use Data::Dumper;
use strict;

sub print_usage();

my $subnets = "10.2.224";

#default to all
my @clients = (77,74,80,82);

my @subnets = (1,3, 5, 6, 7, 9, 10, 11);
my @concs = (100, 1000,3000,5000,7000,9000);
my @ips = (1);
my $proto = 'http';
my $file = '/';
my $ka = '';
my $runperf = 0;
my $timeout = 40;
for my $arg( @ARGV ) {

    if( $arg=~ /^--ips=(\S+)/ ) {
	@ips = split( ',', $1);
    } elsif( $arg =~ /^--proto=(\S+)/ ) {
	$proto = $1;
    } elsif( $arg =~ /^--file=(\S+)/ ) {
	$file = $1;
	if( $file !~ /^\// ) {
	    $file = '/' . $file;
	}
    } elsif( $arg =~ /^--keepalive/ ) {
	$ka = " -k";
    } elsif( $arg =~ /^--perf/ ) {
	$runperf = 1;
    } elsif( $arg =~ /^--timeout=(\d+)/ ) {
	$timeout = $1;
    } elsif( $arg =~ /^--clients=(\S+)/ ) {
	@clients = split( ',', $1 );
    } elsif( $arg =~ /^--subnets=(\S+)/ ) {
	@subnets = split( ',', $1 );
    } elsif( $arg =~ /^--concs=(\S+)/ ) {
	@concs = split( ',', $1 );
    } elsif( $arg =~ /^--?h(elp)?/ ) {
	print_usage();
	exit( 0 );
    } else {
	die "Unexpected argument: '$arg', try --help or -h\n";
    }
}

if( scalar( @clients ) > scalar( @subnets ) ) {
    die "Cannot use all clients (@clients): too few subnets (@subnets)";
}

sub check_tw_sockets();
sub run_zb_conc($);

for my $num_ips ( @ips ) {
    my @concs = ();
    # try hardcoded or user-supplied first
    # make sure the test will complete by waiting until there are no more sockets in TIME_WAIT
    check_tw_sockets();
    # now run for one number of IPs:
    run_zb_conc( $num_ips );
}

sub run_zb_conc($) {
    my( $ips, $conc ) = @_;
    my %fds = (); # ( subnet => cmd_fd )
    my %log_fds = (); # ( subnet => log_fd1, ... )
    my $resps = {}; # { subnet => result, ... }
    my $tput = {}; # { subnet => result, ... }

    my %client_for_subnet=();
    # we have to run one command per subnet, not per client!
    my $client_idx = 0;
    for my $s ( @subnets ) {
	if( $client_idx >= scalar( @clients ) ) {
	    $client_idx = 0;
	}
	my $i = $clients[$client_idx++];
	$client_for_subnet{$s} = $i;
	my $cmd = "ssh root\@$subnet.$i zb_batch1.sh $s $ips $file $proto $timeout $ka 2>&1";
	if( !open( $fds{$s}, "$cmd|" ) ) {
	    die( "Cannot run zb_batch1: $!" );
	} else {
	    print "Started $cmd on subnet $s for client $i\n";
	    if( !open( $log_fds{$s}, '>', "client_$i-subnet${s}_${ips}_zb.log" ) ) {
		die( "Cannot open log file ${s}_${ips}_zb.log: $!" );
	    }
	}
    }

    my $perf_fd = undef;
    # ok zb is running, let's gather profiling data on the STM if required:
    if( $runperf ) {
	my $date_str=`date +%F.%H.%M.%S`; chomp( $date_str );
	print "Using date string '$date_str'\n";
	my $perf_timeout = $timeout -1;
	my $perf_cmd = "perf record -o perf.data.poll.$ips.$date_str -a -g -e cpu-cycles sleep $perf_timeout 2>&1";
	if( !open( $perf_fd, "$perf_cmd |" ) ) {
	    print "@@@@@@@@@@\n@@@@@@@@@@@ Failed to run perf: $! @@@@@@@@@@\n@@@@@@@@@@\n";
	} else {
	    print "Started command '$perf_cmd'\n";
	}
    }
    my $n_results = 0;
    while( scalar( keys( %fds ) ) ) {
	for my $s ( keys( %fds ) ) {
	    my ($fd,$log_fd) = ($fds{$s},$log_fds{$s});
	    my $i = $client_for_subnet{$s};
	    my $line = <$fd>;
	    if( !defined( $line ) ) {
		close( $fd );
		delete( $fds{$s} );
		close( $log_fd );
		delete( $log_fds{$s} );
		next;
	    }
	    print( $log_fd $line );
# Response rate:        92331.766 [responses/sec]
	    if( $line =~ /^Response rate:\s+(\d+\.\d+)\s*\[(responses\/sec)\]/ ) {
		print( "Got result '$1 $2' on subnet $s from client $i\n" );
		push( @{$resps->{$s}}, $1 );
		if( ++$n_results >= scalar( @subnets ) ) {
		    $n_results = 0;
		    print( "\n" );
		}
	    }
# Transfer rate:        7007.409 [MBits/sec] received
	    if( $line =~ /^Transfer rate:\s+(\d+\.\d+)\s*\[(\S+\/sec)\]/ ) {
		print( "Got result '$1 $2' on subnet $s from client $i\n" );
		push( @{$tput->{$s}}, $1 );
	    }
	}
    }

    if( $runperf ) {
	#collect perf fd:
	while( 1 ) {
	    my $line = <$perf_fd>;
	    if( defined( $line ) ) {
		print "[PERF:] $line";
	    } else {
		last;
	    }
	}
	close( $perf_fd );
    }
#print Dumper( $resps );
    my @totals=();
    for my $s ( keys( %{$resps} ) ) {
	my $r = $resps->{$s};
	for my $conc( 0..(scalar( @$r ) -1) ) {
	    $totals[$conc] += $r->[$conc];
	}
    }
    print( "\n\nTotal Resp/s:\n", join( "\n", @totals ), "\n" );

    my @ttotals=();
    for my $s ( keys( %{$tput} ) ) {
	my $t = $tput->{$s};
	for my $conc( 0..(scalar( @$t ) -1) ) {
	    $ttotals[$conc] += $t->[$conc];
	}
    }
    print( "\n\nTotal Mbit/s:\n", join( "\n", @ttotals ), "\n" );
}

sub check_tw_sockets()
{
    for my $client ( @clients ) {
	print "Starting check for TW sockets on client $client...\n";
	my $last_tw = 0;
	my $start = time();
	my $cmd = "ssh root\@$subnet.$client 'while [ \"\$tw\" != \"0\" ]; do tw=`grep tw /proc/net/sockstat | cut -d \" \" -f 7`; echo \$tw; sleep 1; done 2>&1\'";
	if( open( my $fd, "$cmd|" ) ) {
	    #print "Started $cmd\n";
	    while( 1 ) {
		my $line = <$fd>;
		if( defined( $line ) ) {
		    chomp( $line );
		    if( $line ne $last_tw ) {
			$last_tw = $line;
			print $line, "\n";
		    }
		} else {
		    last;
		}
	    }
	    close( $fd );
	} else {
	    die( "Cannot run $cmd: $!" );
	}
	my $elapsed = time() - $start;
	print "No more TWs after $elapsed second(s) ... carry on\n";
    }
}

sub print_usage()
{
    print <<EOF;
Usage: zb_conc.pl [options]

--ips=10

number of IPs to make requests to

--proto=http|https

which protocol to use

--file=/sizes/1k

which file to fetch

--keepalive

turns on keepalive from client to STM (-k option to zeusbench)

--perf

run perf while test is running

--timeout=20

how long in seconds to run the test

--clients=74,77

list of client IPs (last octet in 10.2.224.y)

--subnets=1,3,7,9

list of subnets (third digit in 10.230.x.0/24)

EOF
}

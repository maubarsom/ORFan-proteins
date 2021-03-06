#!/usr/bin/env perl
# $Id: rnacodeOnCluster.pl 2000 2010-06-09 09:34:55Z dmessina $

use strict;
use warnings;
use Getopt::Long;
use File::Spec;
use File::Basename;
#use File::Path qw(make_path);

my ($outdirpath, $jobspernode, $sequential, $debug, $dryrun);
GetOptions( 'outdir:s'      => \$outdirpath,
            'jobspernode:i' => \$jobspernode,
	    'sequential'    => \$sequential,
            'debug'         => \$debug,
            'dryrun'        => \$dryrun,
            );

my $usage = "
rnacodeOnCluster.pl - run RNAcode on a batch of alignments on the cluster

Usage: rnacodeOnCluster.pl --outdir <dirpath> dir_of_seqs1 ... dir_of_seqsN

where dir_of_seqs is a directory with multiple alignment sequence files in it.
NOTE! sequence files must be in clustalw format and end in .aln

--outdir         where output data should be written
--jobspernode    how many alignments to run per node
--sequential     if you want the jobs on a single node to run one after the other
                 (default: the jobs on a single node run in parallel)
--debug          have the cluster send mail
--dryrun         don't actually submit the jobs; just see the commands

";
die $usage unless defined @ARGV;
die "no outdirpath!\n$usage\n" unless defined $outdirpath;
$outdirpath = File::Spec->rel2abs($outdirpath);
if (! -e $outdirpath) {
    die "$outdirpath does not exist!\n";
#    make_path($outdirpath) or die "couldn't create output dir $outdirpath!: $!\n";
}

# Globals
my $bindir = '/afs/pdc.kth.se/home/d/dmessina/bin';
my $exe   = 'RNAcode_x64';
my $exepath = File::Spec->catfile($bindir, $exe);

my $runTime = 239;
my $cmd_separator = $sequential ? ' && ' : ' & ';

my @files;
foreach my $dir (@ARGV) {
    next unless ( -d $dir );    # skip any non-directories
    next if $dir =~ /^\./;      # skip . .. and all other dirs beginning .

    opendir( my $dirhandle, $dir ) or die "couldn't open $dir:$!\n";

    while ( my $entry = readdir($dirhandle) ) {
        if ( $entry =~ /\.aln$/ ) {
            my $path     = $dir . '/' . $entry;
            my $fullpath = File::Spec->rel2abs($path);
            push @files, $fullpath;
        }
    }
    closedir($dirhandle);
}

my @runlist  = ();
my @argslist = ();
my $k        = 0;


# RNAcode_x64 --outfile $PWD/cluster_rnacode_results/$g.rnacode --eps --eps-dir ${g}_eps $f

# prep the execution strings
foreach my $file (@files) {

    my ( $base, $path, $suffix ) = fileparse( $file, qr/\.[^.]*/ );
    my $outbase = $base . '.rnacode';
    my $outfile = File::Spec->catfile($outdirpath, $outbase);
    my $epsbase = $base . '_eps';
    my $epsdir  = File::Spec->catfile($outdirpath, $epsbase);
    my $errbase = $base . '.err';
    my $errfile = File::Spec->catfile($outdirpath, $errbase);
    my $args = "--tabular --outfile $outfile --eps --eps-dir $epsdir ";

    $args = $args . $file . " " . " 2> $errfile ";

    push( @runlist, "$exepath $args" );
}



# each member of the runlist is a job
# submit $jobspernode jobs per node
my $submit_counter = 1;
for ( my $i = 0 ; $i < @runlist ; $i = $i + $jobspernode ) {

    my $command = q{};

#    print "\n";
    for ( my $j = $i ; $j < @runlist && ($j - ($i + $jobspernode - 1) ) < 1 ; $j++ ) {
#	print "i:$i j:$j\n";
        $command = $command . $runlist[$j] . $cmd_separator;
    }

    $command .= ' wait'; # make sure to wait for all the jobs to finish
    chomp($command);

    # submit the command
    my $retval;
    if ($dryrun) {
	print STDERR "\n=== node $submit_counter ==\n";
        print STDERR $command, "\n";
	print STDERR "======\n";
        $retval = 0;
    }
    elsif ($debug) {
        my $command = "esubmit -v -n 1 -t $runTime \"$command\"";
        print STDERR $command, "\n";
        $retval = system($command);
    }
    else {
        $retval = system( "esubmit -v -n 1 -m -t $runTime \"$command\"" );
    }

    # try to notify about submit errors
    if ( $retval > 0 ) { print STDERR $retval, "\t$!\n"; }
    else {
        print STDERR ( "submitted job ", $submit_counter++, "\n" );
    }
}

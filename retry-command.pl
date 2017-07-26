#!/usr/bin/perl

use warnings;
use strict;
use Time::Local;
use Getopt::Long;

my $help;
my $cmd;
my $retry = 3600;
my $spooldir;

Getopt::Long::Configure ("no_ignore_case");
GetOptions(
  "help|h"       => \$help,
  "cmd|c=s"      => \$cmd,
  "retry|r=i"    => \$retry,
  "spooldir|s=s" => \$spooldir,
);

sub usage {
  print "$0 [--help|-h] --cmd|-c [--retry|-r <secs>] --spooldir|-s <dir>\n";
  print "  -h --help           display this help content\n";
  print "  -c --cmd  <cmd>     execute this command on queue contents: substitute {} for filename from spool directory\n";
  print "  -r --retry <secs>   retry failed uplaods every <secs> (default $retry)\n";
  print "  -s --spooldir <dir> pick up work from this directory (e.g. work queue)\n";
}

if ($help) {
  usage();
  exit;
}

if (!defined $cmd || !defined $spooldir) {
  print "Both --spooldir and --cmd must be set\n";
  usage();
  exit 1;
}

my $pattern='-retry\d{14}$';
my $now = time();

#
# List files in spool directory
#
$spooldir =~ s,/$,,g;
opendir (DIR, $spooldir) or die $!;

while (my $file = readdir(DIR)) {
  next if $file eq "." or $file eq "..";
  $file = $spooldir."/".$file;
  print "Candidate file: $file\n";
  my $ignore = 0;
  if ($file =~ m/-retry(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/) {
    #
    # Do we need to re-attempt this file?
    # generate the epoch from above
    #
    my $timestamp = "$1-$2-$3 $4:$5:$6";
    my $epoch = timestamp_to_epoch($timestamp);
    #
    # Is epoch in the future?
    #
    if ($epoch < $now) {
      #
      # We need to do something with this one
      #
      printf("Ready for retry: %s\n",$file);
      #
      my $newfile = $file;
      $newfile =~ s/-retry(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$//;
      printf("mv %s %s\n",$file,$newfile);
      rename($file,$newfile) or die $!;
      $file = $newfile;
    } else {
      #
      # Ignore, not due for retry yet
      #
      $ignore = 1;
    }
  }
  
  if (!$ignore) {
    #
    # Upload
    #
    my $success = 0;
    my $tmpcmd = $cmd;
    $tmpcmd =~ s/{}/$file/g;
    printf("Uploading %s with command [$tmpcmd]\n",$file);
    open(PIPE, $tmpcmd . " </dev/null 2>&1 |" ) or die "Can't exec start command [".$tmpcmd."]: $!";
    while (<PIPE>) {
      my $line;
      $line = $_;
      chomp($line);
      print $line."\n";
    }

    close(PIPE); # will return false if $tmpcmd fails

    my $res =  $?;

    if ($res == -1) {
      printf "\n\t\t\t[FAILED] failed to execute: $!\n";
    } elsif ($res & 127) {
	  printf "\n\t\t\t[FAILED] child died with signal %d, %s coredump\n\n", ($res & 127),  ($res & 128) ? 'with' : 'without';
    } elsif ( $res != 0 ) {
	  printf "\n\t\t\t[FAILED] child exited with value %d\n\n", $res >> 8;
    } else {
      print "\n\t\t\t[OK] with shell return code [$res]\n\n";
      $success = 1;
    }
    
    #
    # Delete if successful, rename if failed
    #
    if ($success) {
      #
      # Delete
      #
      printf("Removing %s\n",$file);
      unlink($file) or die $!;
    } else {
      #
      # Rename to future timestamp
      #
      my $future = $now + 3600;
      my $datestr = epoch_to_timestamp($future);
      $datestr =~ s/ //g;
      $datestr =~ s/://g;
      $datestr =~ s/-//g;
      my $newfile = sprintf("%s-retry%s",$file,$datestr);
      printf("Renaming %s %s\n",$file,$newfile);
      rename($file,$newfile) or die $!;
      $file = $newfile;
    }
  }
}

closedir(DIR);

sub timestamp_to_epoch {
  my $timestamp = shift;
  if ( $timestamp =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/ ) {
    return ( timelocal( $6, $5, $4, $3, $2 - 1, $1 ) );
  }
}

sub epoch_to_timestamp {
  my $epoch = shift;
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime($epoch);
  return(sprintf("%04d-%02d-%02d %02d:%02d:%02d",$year+1900,$month+1,$day,$hour,$min,$sec));
}

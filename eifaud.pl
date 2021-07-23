#!/usr/local/bin/perl -w
#------------------------------------------------------------------------------
# Licensed Materials - Property of IBM (C) Copyright IBM Corp. 2010, 2010
# All Rights Reserved US Government Users Restricted Rights - Use, duplication
# or disclosure restricted by GSA ADP Schedule Contract with IBM Corp
#------------------------------------------------------------------------------

#  perl dup2do.pl
#
#  Create setagentconnection commands to recify duplicate agents.
#  And redo distribution/MSL for renamed agents
#  Create several reports to guide the recovery.
#
#  john alvord, IBM Corporation, 1 May 2020
#  jalvord@us.ibm.com
#
# tested on Windows Strawberry Perl 5.28.1
# Should work on Linux/Unix but not yet tested
#
# $DB::single=2;   # remember debug breakpoint

## todos
##   add support for situation groups

#use warnings::unused; # debug used to check for unused variables
use strict;
use warnings;
use Data::Dumper;               # debug only

my $gVersion = "0.50000";
my $gWin = (-e "C://") ? 1 : 0;    # 1=Windows, 0=Linux/Unix

my $ll;




  # agent suffixes which represent distributed OS Agents
my $oneline;
my $sx;
my $i;

my $tx;                                  # TEMS information
my $temsi = -1;                          # count of TEMS
my @tems = ();                           # Array of TEMS names
my %temsx = ();                          # Hash to TEMS index
my @tems_version = ();                   # TEMS version number

my $mx;                                  # index
my $magenti = -1;                        # count of managing agents
my @magent = ();                         # name of managing agent
my %magentx = ();                        # hash from managing agent name to index
my @magent_subct = ();                   # count of subnode agents
my @magent_sublen = ();                  # length of subnode agent list
my @magent_tems_version = ();            # version of managing agent TEMS
my @magent_tems = ();                    # TEMS name where managing agent reports

my %instanced = (                        # known instanced agents
                   'LO' => 1,
                   'RZ' => 1,
                );

my $oline;
my $opt_all;                              # when 1 dump data for all nodes
my $opt_fn;                               # Input file
my $opt_ofn;                              # Report file


while (@ARGV) {
   if ($ARGV[0] eq "-a") {
      $opt_all = 1;
      shift(@ARGV);
   } else {
      $opt_fn = shift(@ARGV);
   }
}


if (!defined $opt_all) {$opt_all = 1;}
if (!defined $opt_fn) {$opt_fn = "cache.txt";}


die "Cache file $opt_fn not found" if !-e $opt_fn;

$opt_fn =~ /(\S+)\.(\S+)/;

my $part1 = $1;

$opt_ofn = $part1 . ".csv";



my %nodex;
my %sitx;
my %ntx;

my $cache_fn = $opt_fn;
my $cache_fh;
open $cache_fh, "<", $cache_fn || die("Could not open cache report  $cache_fn\n");
my @cachep = <$cache_fh>;                   # Data read once and processed twice
close $cache_fh;

# Collect the Cache data
$ll = 0;
my $rest;
foreach $oneline (@cachep) {
   last if !defined $oneline;
   $ll += 1;
   next if $ll < 5;
   $rest = substr($oneline,1);
   next if length($rest) < 2;
   next if substr($rest,0,11) eq "ITM_Generic";
   my %avx;
   my $chunk;
   while (1) {
      last if $rest eq "END";
      last if $rest eq "";
      $rest =~ /(.*?);(.*)/;
      $chunk = $1;
      $rest = $2;
      next if index($chunk,"=") == -1;
      $chunk =~ /(\S+)=\'(.*)\'/;
      my $atr = $1;
      my $val = $2;
      $avx{$atr} = $val;
      last if $rest eq "END";
   }
   my $isource = $avx{"source"};
   my $inode;
   next if !defined $isource;

   if ($isource eq "ITM") {
      my $isit = $avx{"situation_name"};
      next if !defined $isit;
      $inode = $avx{"sub_source"};
      my $istat = $avx{"situation_status"};
      my $iatom = $avx{"situation_displayitem"};
      my $sit_ref = $sitx{$isit};
      if (!defined $sit_ref) {
         my %sitref = (
                         count => 0,
                         nodes => {},
                         y_cnt => 0,
                         n_cnt => 0,
                         atoms => {},
                      );
         $sit_ref = \%sitref;
         $sitx{$isit} = \%sitref;
      }
      $sit_ref->{count} += 1;
      $sit_ref->{y_cnt} += 1 if $istat eq "Y";
      $sit_ref->{n_cnt} += 1 if $istat eq "N";
      $sit_ref->{atoms}{$iatom} += 1;
      my $node_ref = $sit_ref->{nodes}{$inode};
      if (!defined $node_ref) {
         my %noderef = (
                         count => 0,
                         y_cnt => 0,
                         n_cnt => 0,
                         atoms => {},
                      );
         $node_ref = \%noderef;
         $sit_ref->{nodes}{$inode} = \%noderef;
      }
      $node_ref->{count} += 1;
      $node_ref->{y_cnt} += 1 if $istat eq "Y";
      $node_ref->{n_cnt} += 1 if $istat eq "N";
      $node_ref->{atoms}{$iatom} += 1;

   } elsif ($isource eq "ITM:Signal Event") {
      $inode = $avx{"situation_origin"};
      my $ithrunode = $avx{"situation_thrunode"};
      my $isit = $avx{"situation_name"};
      my $iatom = $avx{"situation_displayitem"};
      $iatom = "" if !defined $iatom;
      my $node_ref = $ntx{$inode};
      if (!defined $node_ref) {
         my %noderef = (
                          count => 0,
                          thrunodes => {},
                          atoms => {},
                          sits => {},
                      );
         $node_ref = \%noderef;
         $ntx{$inode} = \%noderef;
      }
      $node_ref->{count} += 1;
      $node_ref->{thrunodes}{$ithrunode} += 1;
      $node_ref->{sits}{$isit} += 1;
      $node_ref->{atoms}{$iatom} += 1;
   }
}

my $report_fh;
open $report_fh, ">", $opt_ofn or die "can't open $opt_ofn: $!";
print $report_fh "Cache Summary from $opt_fn\n";
print $report_fh "Situation,Count,Y,N,node_count,\n";
print $report_fh ",Node,Count,Y,N,atom_count,atoms,\n";
foreach my $f ( sort {$sitx{$b}->{count} <=> $sitx{$a}->{count}} keys %sitx) {
   my $sit_ref = $sitx{$f};
   $oline = $f . ",";
   $oline .= $sit_ref->{count} . ",";
   $oline .= $sit_ref->{y_cnt} . ",";
   $oline .= $sit_ref->{n_cnt} . ",";
   my $node_ct = scalar keys %{$sit_ref->{nodes}};
   $oline .= $node_ct . ",";
   print $report_fh "$oline\n";
   if ($opt_all == 1) {
      foreach my $g ( sort {$a cmp $b} keys %{$sit_ref->{nodes}}) {
         my $node_ref = $sit_ref->{nodes}{$g};
         $oline = "," . $g . ",";
         $oline .= $node_ref->{count} . ",";
         $oline .= $node_ref->{y_cnt} . ",";
         $oline .= $node_ref->{n_cnt} . ",";
         my $atom_ct = scalar keys %{$node_ref->{atoms}};
         $oline .= $atom_ct . ",";
         my $patoms = "";
         foreach my $h (sort { $a cmp $b } keys %{$node_ref->{atoms}}) {
            $patoms .= $h . " ";
         }
         chop $patoms if $patoms ne "";
         $oline .= $patoms . ",";
         print $report_fh "$oline\n";
      }
   }
}
print $report_fh "\n";
print $report_fh "Cache Signal report from $opt_fn\n";
print $report_fh "Node,Count,Sits,Atoms,Thrunodes,\n";
foreach my $f ( sort {$ntx{$b}->{count} <=> $ntx{$a}->{count}} keys %ntx) {
   my $node_ref = $ntx{$f};
   $oline = $f . ",";
   $oline .= $node_ref->{count} . ",";
   my $psits = "";
   foreach my $g (sort { $a cmp $b } keys %{$node_ref->{sits}}) {
      $psits.= $g . "[" . $node_ref->{sits}{$g} . "] ";
   }
   chop $psits if $psits ne "";
   $oline .= $psits . ",";
   my $atm_ct = scalar keys %{$node_ref->{atoms}};
   $oline .= $atm_ct . ",";
   my $pthru = "";
   foreach my $g (sort { $a cmp $b } keys %{$node_ref->{thrunodes}}) {
      $pthru .= $g . "[" . $node_ref->{thrunodes}{$g} . "] ";
   }
   chop $pthru if $pthru ne "";
   $oline .= $pthru . ",";
   print $report_fh "$oline\n";
}

close $report_fh;
exit 0;

# 0.50000 - initial cut

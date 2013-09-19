#!/pro/bin/perl

use strict;
use warnings;

use Getopt::Long qw(:config bundling nopermute);
my $check = 0;
my $opt_v = 0;
GetOptions (
    "c|check"		=> \$check,
    "v|verbose:1"	=> \$opt_v,
    ) or die "usage: $0 [--check]\n";

use lib "sandbox";
use genMETA;
my $meta = genMETA->new (
    from    => "lib/GSM/Gnokii.pm",
    verbose => $opt_v,
    );

{   open my $mh, "<", "META.yml" or die "META.yml: $!\n";
    $meta->from_data (do { local $/; <$mh> });
    }

if ($check) {
    $meta->check_encoding ();
    $meta->check_required ();
    $meta->check_minimum ([ "t", "Gnokii.pm", "Makefile.PL" ]);
    $meta->check_minimum ("5.010", [ "examples" ]);
    }
elsif ($opt_v) {
    $meta->print_yaml ();
    }
else {
    $meta->fix_meta ();
    }

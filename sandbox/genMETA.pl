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

$meta->from_data (<DATA>);

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

__END__
--- #YAML:1.0
name:                    GSM-Gnokii
version:                 VERSION
abstract:                Perl API to libgnokii
license:                 perl
author:              
    - H.Merijn Brand <h.m.brand@xs4all.nl>
generated_by:            Author
distribution_type:       module
provides:
    GSM::Gnokii:
        file:            Gnokii.pm
        version:         VERSION
requires:     
    perl:                5.008004
    Carp:                0
    DynaLoader:          0
    Data::Peek:          0.32
    JSON:                0
recommends:     
    perl:                5.014001
    Data::Peek:          0.34
configure_requires:
    ExtUtils::MakeMaker: 0
build_requires:
    Config:              0
test_requires:
    Test::Harness:       0
    Test::More:          0.88
    Test::NoWarnings:    0
test_recommends:
    Test::More:          0.98
resources:
    license:             http://dev.perl.org/licenses/
    repository:          http://repo.or.cz/w/GSM-Gnokii.git
meta-spec:
    version:             1.4
    url:                 http://module-build.sourceforge.net/META-spec-v1.4.html

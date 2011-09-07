#!/pro/bin/perl

use strict;
use warnings;
use autodie;

open my $fh, "<", "OPs.list";
my %done = map { m/(\w+)/; ($1 => 0) } <$fh>;
open my $xs, "<", "Gnokii.xs";
while (<$xs>) {
    my @ops = (m/\b (GN_OP_\w+) \b/xg) or next;
    @done{@ops} = (1) x scalar @ops;
    }

my @color = ("todo", "done");
my @ch = ("-", "<strong>*</strong>");
my @ops = sort keys %done;
foreach my $r (0..24) {
    foreach my $c (0 .. 3) {
	my $o = $ops[$c * 25 + $r] // last;
	my $s = $done{$o} // 0;
	print qq{\t  <td class="$color[$s]">$ch[$s]&nbsp;&nbsp;$o</td>\n};
	}
    print "\t  </tr>\n\t<tr>\n";
    }

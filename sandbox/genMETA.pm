#!/pro/bin/perl

package genMETA;

our $VERSION = "1.04-20130212";

use 5.014;
use warnings;
use Carp;

use List::Util qw( first );
use Encode qw( encode decode );
use Term::ANSIColor qw(:constants);
use Test::CPAN::Meta::YAML::Version;
use CPAN::Meta::Converter;
use Test::MinimumVersion;
use Test::More ();
use Parse::CPAN::Meta;
use File::Find;
use YAML::Syck;
use Data::Peek;
use Text::Diff;
use JSON::PP;

sub new
{
    my $package = shift;
    return bless { @_ }, $package;
    } # new

sub version_from
{
    my ($self, $src) = @_;

    $self->{mfpr} = {};
    if (open my $mh, "<", "Makefile.PL") {
	my $mf = do { local $/; <$mh> };

	if ($mf =~ m{\b NAME         \s*=>\s* ["'] (\S+) ['"]}x) {
	    $self->{name} = $1;
	    $self->{name} =~ m/-/ and
		warn RED, "NAME in Makefile.PL contains a -", RESET, "\n";
	    $self->{name} =~ s/::/-/g;
	    }
	if ($mf =~ m{\b DISTNAME     \s*=>\s* ["'] (\S+) ['"]}x) {
	    $self->{name} = $1;
	    }

	if ($mf =~ m{\b VERSION_FROM \s*=>\s* ["'] (\S+) ['"]}x) {
	    my $from = $1;
	    -f $from or
		die RED, "Makefile wants version from nonexisten $from", RESET, "\n";
	    $self->{from} //= $from;
	    $from eq $self->{from} or
		die RED, "VERSION_FROM mismatch Makefile.PL / YAML", RESET, "\n";
	    }

	if ($mf =~ m[\b PREREQ_PM    \s*=>\s* \{ ( [^}]+ ) \}]x) {
	    my @pr = split m/\n/ => $1;
	    $self->{mfpr} = { map { (m{ \b ["']? (\S+?) ['"]? \s*=>\s* ["']? ([-0-9._]+) ['"]? }x) } grep !m/^\s*#/ => @pr };
	    }

	$mf =~ m{--format=ustar} or
	    warn RED, "TARFLAGS macro is missing", RESET, "\n";
	}

    $src //= $self->{from} or croak "No file to extract version from";

    my $version;
    open my $pm, "<", $src or croak "Cannot read $src";
    while (<$pm>) {
	m/^(?:our\s+)? \$VERSION \s*=\s* ["']? ([-0-9._]+) ['"]? \s*;\s*$/x or next;
	$version = $1;
	last;
	}
    close $pm;
    $version or croak "Cannot extract VERSION from $src\n";
    $self->{version} = $version;
    return $version
    } # version_from

sub from_data
{
    my ($self, @data) = @_;
    $self->{version} or $self->version_from ();
    s/VERSION/$self->{version}/g for @data;
    $self->{yml} = \@data;
    $self->check_yaml ();
    return @data;
    } # from_data

sub check_encoding
{
    my $self = shift;
    my @tf   = grep m{^(?: change | readme | .*\.pod )}ix => glob "*";
    (my $tf = join ", " => @tf) =~ s/.*\K, / and /;
    
    print "Check if $tf are still valid UTF8 ...\n";
    foreach my $tf (@tf) {
	open my $fh, "<", $tf or croak "$tf: $!\n";
	my @c = <$fh>;
	my $c = join "" => @c;
	my @e;
	my $s = decode ("utf-8", $c, sub { push @e, shift; });
	if (@e) {
	    my @l;
	    my $n = 0;
	    for (@c) {
		$n++;
		eval { decode ("utf-8", $_, 1) };
		$@ or next;
		$@ =~ s{ at /\S+ line \d+.*}{};
		print BLUE, "$tf:$n\t$_\t$@", RESET;
		}
	    croak "$tf is not valid UTF-8\n";
	    }
	my $u = encode ("utf-8", $s);
	$c eq $u and next;

	my $n;
	$n = 1; $c =~ s/^/$n++ . "\t"/gem;
	$n = 1; $u =~ s/^/$n++ . "\t"/gem;
	croak "$tf: recode makes content differ\n". diff \$c, \$u;
	}
    } # check_encoding

sub check_required
{
    my $self = shift;
    
    my $yml = $self->{h} or croak "No YAML to check";

    warn "Check required and recommended module versions ...\n";
    BEGIN { $V::NO_EXIT = $V::NO_EXIT = 1 } require V;
    my %req = map { %{$yml->{$_}} } grep m/requires/   => keys %{$yml};
    my %rec = map { %{$yml->{$_}} } grep m/recommends/ => keys %{$yml};
    if (my $of = $yml->{optional_features}) {
	foreach my $f (values %{$of}) {
	    my %q = map { %{$f->{$_}} } grep m/requires/   => keys %{$f};
	    my %c = map { %{$f->{$_}} } grep m/recommends/ => keys %{$f};
	    @req{keys %q} = values %q;
	    @rec{keys %c} = values %c;
	    }
	}
    my %vsn = ( %req, %rec );
    delete @vsn{qw( perl version )};
    for (sort keys %vsn) {
	if (my $mfv = delete $self->{mfpr}{$_}) {
	    $req{$_} eq $mfv or
		die RED, "PREREQ mismatch for $_ Makefile.PL ($mfv) / YAML ($req{$_})", RESET, "\n";
	    }
	$vsn{$_} eq "0" and next;
	my $v = V::get_version ($_);
	$v eq $vsn{$_} and next;
	printf STDERR "%s%-35s %-6s => %s%s%s\n", BLUE, $_, $vsn{$_}, GREEN, $v, RESET;
	}
    if (my @mfpr = sort keys %{$self->{mfpr}}) {
	die RED, "Makefile.PL requires @mfpr, YAML does not", RESET, "\n";
	}

    find (sub {
	$File::Find::dir  =~ m{^blib\b}			and return;
	$File::Find::name =~ m{(?:^|/)Bundle/.*\.pm}	or  return;
	if (open my $bh, "<", $_) {
	    warn "Check bundle module versions $File::Find::name ...\n";
	    while (<$bh>) {
		my ($m, $dv) = m/^([A-Za-z_:]+)\s+([0-9.]+)\s*$/ or next;
		my $v = $m eq $self->{name} ? $self->{version} : V::get_version ($m);
		$v eq $dv and next;
		printf STDERR "%s%-35s %-6s => %s%s%s\n", BLUE, $m, $dv, GREEN, $v, RESET;
		}
	    }
	}, glob "*");

    if (ref $self->{h}{provides}) {
	print "Check distribution module versions ...\n";
	foreach my $m (sort keys %{$self->{h}{provides}}) {
	    $m eq $self->{name} and next;
	    my $ev = $self->{h}{provides}{$m}{version};
	    printf "  Expect %5s for %-32s ", $ev, $m;
	    my $fn = $self->{h}{provides}{$m}{file};
	    if (open my $fh, "<", $fn) {
		my $fv;
		while (<$fh>) {
		    m/\bVERSION\s*=\s*["']?([-0-9.]+)/ or next;
		    $fv = $1;
		    print $fv eq $ev ? "ok\n" : RED." mismatch, module has $1".RESET."\n";
		    last;
		    }
		defined $fv or print " .. no version defined\n";
		}
	    else {
		print " .. cannot open $fn: $!\n";
		}
	    }
	}
    } # check_required

sub check_yaml
{
    my $self = shift;

    my @yml = @{$self->{yml}} or croak "No YAML to check";

    warn "Checking generated YAML ...\n";
    my $h;
    my $yml = join "", @yml;
    eval { $h = Load ($yml) };
    $@ and croak "$@\n";
    $self->{name} //= $h->{name};
    $self->{name} eq  $h->{name} or
	die RED, "NAME mismatch Makefile.PL / YAML", RESET, "\n";
    $self->{name} =~ s/-/::/g;
    warn "Checking for $self->{name}-$self->{version}\n";

    $self->{verbose} and print Dump $h;

    my $t = Test::CPAN::Meta::YAML::Version->new (data => $h);
    $t->parse () and
	croak join "\n", "Test::CPAN::Meta::YAML reported failure:", $t->errors, "";

    eval { Parse::CPAN::Meta::Load ($yml) };
    $@ and croak "$@\n";

    $self->{h}    = $h;
    $self->{yaml} = $yml;
    } # check_yaml

sub check_minimum
{
    my $self = shift;
    my $reqv = $self->{h}{requires}{perl};
    my $locs;

    for (@_) {
	if (ref $_ eq "ARRAY") {
	    $locs = { paths => $_ };
	    }
	elsif (ref $_ eq "HASH") {
	    $locs = $_;
	    }
	else {
	    $reqv = $_;
	    }
	}
    my $paths = (join ", " => @{($locs // {})->{paths} // []}) || "default paths";

    $reqv or croak "No minimal required version for perl";
    print "Checking if $reqv is still OK as minimal version for $paths\n";
    # All other minimum version checks done in xt
    Test::More::subtest "Minimum perl version $reqv" => sub {
	all_minimum_version_ok ($reqv, $locs);
	} or warn RED, "\n### Use 'perlver --blame' on the failing file(s)\n\n", RESET;
    } # check_minimum

sub print_yaml
{
    my $self = shift;
    print @{$self->{yml}};
    } # print_yaml

sub fix_meta
{
    my $self = shift;

    # Do not change anything here anymore
    } # fix_meta

1;

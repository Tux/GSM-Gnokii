use ExtUtils::MakeMaker;
use Config;

my $gnokii_lib = "";
my $gnokii_inc = "";

if (exists $ENV{GNOKII_DIR} && -d $ENV{GNOKII_DIR}) {
    my $gdir = $ENV{GNOKII_DIR};
    $gnokii_lib = join " " => map { "-L$gdir$_" } "", "common/.libs";
    $gnokii_inc = "-I$gdir/include -I$gdir/gnokii";
    }
else {
    my $ext = $Config{dlext};
    grep { -x "$_/libgnokii.$Config{dlext}" ||
	   -x "$_/libgnokii.a"
	 } split m/\s+/ => $Config{libpth} or
	die "libgnokii not found. Unpack and compile, and set \$GNOKII_DIR\n";
    }

WriteMakefile (
    NAME		=> "GSM::Gnokii",
    VERSION_FROM	=> "Gnokii.pm",
    PREREQ_PM		=> {},
    LIBS		=> [ "$gnokii_lib -lgnokii" ],
    TYPEMAPS		=> [ "perlobject.map" ],
    DEFINE		=> "",
    INC			=> $gnokii_inc,
    );

1;

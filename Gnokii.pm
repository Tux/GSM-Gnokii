package GSM::Gnokii;

require 5.008004;
use strict;
use warnings;
use Carp;

require Exporter;
require DynaLoader;
use AutoLoader;

our @ISA = qw(Exporter DynaLoader);

our %EXPORT_TAGS = ( all => [ qw( ) ] );
our @EXPORT_OK   = ( @{ $EXPORT_TAGS{all} } );
our @EXPORT      = qw( );
our $VERSION     = "0.03";

my @MEMORYTYPES = qw(
    ME SM FD ON EN DC RC MC LD MT TA CB IN OU AR TE
    F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12 F13 F14 F15 F16 F17 F18 F19 F20
    );

sub new
{
    my $gsm  = bless {
# TODO:
#	device		=> "00:11:22:33:44:55",
#	model		=> "3109",
#
#	connection	=> "bluetooth",
#	initlength	=> 0,
#	use_locking	=> "no",
#	serial_baudrate	=> 19200,
#	smsc_timeout	=> 10,
#	allow_breakage	=> 0,
#	bindir		=> "/usr/sbin/",
#	TELEPHONE	=> "0612345678",
#	debug		=> "off",
#	rlpdebug	=> "off",
#	xdebug		=> "off",
	}, "GSM::Gnokii";
    $gsm;
    } # new

sub AUTOLOAD
{
    our $AUTOLOAD;
    (my $constname = $AUTOLOAD) =~ s/.*:://;
    croak "& not defined" if $constname eq "constant";
    my $val = constant ($constname, @_ ? $_[0] : 0);
    if ($!) {
	if ($! =~ m/Invalid/ || $!{EINVAL}) {
	    $AutoLoader::AUTOLOAD = $AUTOLOAD;
	    goto &AutoLoader::AUTOLOAD;
	    }
	croak "Your vendor has not defined GSM::Gnokii macro $constname";
	}
    {	no strict "refs";
	*$AUTOLOAD = sub () { $val };
	}
    goto &$AUTOLOAD;
    }

bootstrap GSM::Gnokii $VERSION;

sub connect
{
    my ($self, $options) = @_;

    $self->{connection}   = $self->Initialize ();
    $self->{MEMORY_TYPES} = \@MEMORYTYPES;
    $self;
    } # connect

sub DESTROY
{
    my $self = shift;

    $self->{connection} and $self->connection->disconnect ();
    } # DESTROY

1;
__END__

=head1 NAME

GSM::Gnokii - Perl extension libgnokii

=head1 SYNOPSIS

  use GSM::Gnokii;
  
  $gsm = GSM::Gnokii->new ();
  $gsm->connect ();

  my $date_time    = $gsm->GetDateTime ();
  my $memory_state = $gsm->GetMemoryStatus ();
  my $address_book = $gsm->ReadPhoneBook ("ME", 1, 0);

=head1 DESCRIPTION

GSM::Gnokii is a driver module to interface Perl with libgnokii.

=head1 METHODS

Most data used in below examples is made up and does not necessarily
reflect existing values.

=head2 new

...

=head2 connect

Connect to the phone.

=head2 GetProfiles (start, end)

Returns a reference to a list of hashes with profile information, like:

  number           => 1,
  name             => "Tux",
  defaultname      => "Default",
  call_alert       => "Ringing",
  ringtonenumber   => 3,
  volume_level     => "Level 5",
  message_tone     => "Beep once",
  keypad_tone      => "Level 2",
  warning_tone     => "Off",
  vibration        => "On",
  caller_groups    => 2,
  automatic_answer => "Off",

Note that at some models, requesting profile information outside of the
known range might cause the phone to power off.

My own phone timed out on all C<GetProfile> requests.

=head2 GetDateTime

Returns a reference to a hash with two elements, like:

  date             => "2011-01-23 17:22:37",
  timestamp        => 1295799757,

=head2 GetAlarm

Returns a reference to a hash with alarm info, like:

  alarm            => "07:25",
  state            => "off",

=head2 GetMemoryStatus

Returns a reference to a list of memory status entries, like:

  dcfree           =>   236,
  dcused           =>    20,
  enfree           => 12544,
  enused           =>     0,
  fdfree           => 12544,
  fdused           =>     0,
  mcfree           =>   493,
  mcused           =>    19,
  onfree           =>    15,
  onused           =>     0,
  phonefree        =>  1902,
  phoneused        =>    98,
  rcfree           =>   748,
  rcused           =>    20,
  simfree          =>   250,
  simused          =>     0,

=head2 GetPowerStatus

Returns a reference to a hash with power related information like:

  level            => "42.8571434020996094",
  source           => "battery",

=head2 GetPhonebook (type, start, end)

Returns a reference to an array of PhoneBook entries. Each entry has
been filled with as much as data as available from the entry in the
phone.

The C<type> argument reflects the memory type. See "MEMORYTYPES" below.
The C<start> argument is the first entry to retrieve. Counting starts
at 1, not 0. The C<end> argument may be C<0>, meaning "to the end".

An addressbook entry looks somewhat like:

  memorytype       => "ME",
  location         => 38,
  number           => "+31612345678",
  name             => "John Doe",
  group            => 5,
  person           => {
    formal_name      => "Sr. J. Doe",
    formal_suffix    => "Zzz",
    given_name       => "John",
    family_name      => "Doe",
    additional_names => "Aldrick",
    },
  address          => {
    postal           => "P.O. Box 123",
    extended_address => "Whereever",
    street           => "Memory Lane 123",
    city             => "Duckstad",
    state_province   => "N/A",
    zipcode          => "1234AA",
    country          => "Verwegistan",
    },
  birthday         => "1961-12-31",
  date             => "1970-01-01",
  ext_group        => 21,
  e_mail           => 'john.doe@some.where.com',
  home_address     => "Camper 23",
  note             => "This entry reflects imaginary data",
  tel_home         => "+31201234567",
  tel_cell         => "+31612345678",
  tel_fax          => "+31201234568",
  tel_work         => "+31201234569",
  tel_none         => "+31201234570",
  tel_common       => "+31201234571",
  tel_general      => "+31201234571",
  url              => "http://www.some.where.com",

=head2 GetSpeedDial (number)

Returns a reference to a hash with the information needed to get to
the number used:

  number           =>  2,
  location         => 23,
  memory           => "ME",

To get the address book entry to the speed dial, use

  my $ab = $gsm->GetPhonebook ("ME", 23, 23);

=head2 GetIMEI

Returns a reference to a hash with the IMEI data, like:

  imei             => "345634563456678",
  manufacturer     => "Nokia",
  model            => "RM-274",
  revision         => "V 07.21",

=head2 GetRF

Returns a reference to a hash with the RF data, like:

  level            => 100,
  unit             =>   5,

=head2 GetSMSCenter (start, end)

Returns a reference to a list of SMS Center information hashes like:

  id               => 1,
  name             => "KPN",
  defaultname      => -1,
  format           => "Text",
  validity         => "72 hours"
  type             => 145,
  smscnumber       => "+31612345679",
  recipienttype    => 0,
  recipientnumber  => "",

=head2 GetSMSFolderList

Returns a reference to a list of hashes containing SMS Folder info, like:

  location         => 1,
  memorytype       => "IN",
  name             => "SMS Inbox",
  count            => 42,

=head2 GetSMSStatus

Returns a reference to the SMS status info, like:

  read             => 73,
  unread           =>  0,

=head2 GetSMS (memorytype, location)

Returns a reference to a hash with the SMS data, like:

  memorytype       => "IN",
  location         => 3,
  date             => "0000-00-00 00:00:00",
  sender           => "+31612345678",
  smsc             => "",
  smscdate         => "2010-07-12 20:10:35",
  status           => "read",
  text             => "This is fake data, enjoy!",
  timestamp        => -1,

=head2 GetNetworkInfo

Returns a reference to a hash with the network information, like:

  cellid           => "b56f",
  countryname      => "Netherlands",
  lac              => 1127,
  name             => "KPN",
  networkcode      => "204 08",

=head2 GetRingtoneList

Returns a reference to a hash with ringtone list information, like:

  count            =>   1,
  userdef_count    =>  10,
  userdef_location => 231,

=head2 GetRingtone (location)

Returns a reference to a hash with ringtone information, like:

  location         => 1,
  length           => 15,
  name             => 'Tones',
  ringtone         => "\002J:UQ\275\271\225\314\004",

=head2 GetCalendarNotes (start, end)

Returns a reference to a list of calendar note hashes, like:

  location         => 1,
  type             => "MEETING",
  text             => "Be there or be fired",
  alarm            => "2011-11-11 11:11:11",
  date             => "2010-10-10 10:10:10",

=head2 GetWapSettings (location)

Returns a reference to a hash with the WAP settings for given location, like:

  location         => 1,
  name             => "Default",
  home             => "http://p3rl.org",
  session          => "temporary",
  security         => "yes",
  bearer           => "GPRS",
  gsm_data_auth    => "secure",
  call_type        => "analog",
  call_speed       => "automatic",
  number           => 1,
  gsm_data_login   => "automatic",
  gsm_data_ip      => "10.11.12.13",
  gsm_data_user    => "johndoe",
  gsm_data_pass    => "secret",
  gprs_connection  => "secure",
  gprs_auth        => "secure",
  gprs_login       => "automatic",
  access_point     => "w3_foo",
  gprs_ip          => "14.15.16.17",
  gprs_user        => "johndoe",
  gprs_pass        => "fidelity",
  sms_servicenr    => "+31612345678",
  sms_servernr     => 456,

=head2 GetWapBookmark (location)

Returns a reference to a hash with WAP bookmark information, like:

  location         => 1,
  name             => "perl",
  url              => "http://p3rl.org",

=head1 MEMORYTYPES

The supported memory types are the ones that gnokii supports on the
different phone models, notably:

  ME  Internal memory of the mobile equipment
  SM  SIM card memory
  FD  Fixed dial numbers
  ON  Own numbers
  EN  Emergency numbers
  DC  Dialled numbers
  RC  Received calls
  MC  Missed calls
  LD  Last dialed numbers

For SMS, these are likely to be valid:

  IN  SMS Inbox
  OU  SMS Outbox, sent items
  OUS SMS Outbox, items to be sent
  AR  SMS Archive
  DR  SMS Drafts
  TE  SMS Templates
  F1  SMS Folder 1 (..20)

=head1 AUTHOR

H.Merijn Brand 

Author of GSMD::Gnokii is Konstantin Agouros. gnokii@agouros.de
His code served as a huge inspiration to create this module.

=head1 SEE ALSO

gnokii(1), GSMI, GSMD::Gnokii

=cut

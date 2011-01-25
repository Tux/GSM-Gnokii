#!/pro/bin/perl

use strict;
use warnings;
use autodie;

use Test::More;
use Data::Peek;
use List::Util qw( first );
use GSM::Gnokii;

my $gsm  = GSM::Gnokii->new ()->connect;

ok (my $get = {
    DateTime	=> $gsm->GetDateTime (),
    Memory	=> $gsm->GetMemoryStatus (),
    Power	=> $gsm->GetPowerStatus (),
    PhoneBookME	=> $gsm->ReadPhonebook ("ME", 1, 0),
    PhoneBookSM	=> $gsm->ReadPhonebook ("SM", 1, 0),
    SpeedDial_2	=> $gsm->GetSpeedDial (2),
    IMEI	=> $gsm->GetIMEI (),
    RF		=> $gsm->GetRF (),
    NetworkInfo	=> $gsm->GetNetworkInfo (),
    SMSCenter	=> $gsm->GetSMSCenter (1, 99),
    Alarm	=> $gsm->GetAlarm (),
    RingtoneList=> $gsm->GetRingtoneList (),
    Ringtone	=> $gsm->GetRingtone (1),
    SMSStatus	=> $gsm->GetSMSStatus (),
    SMSFolders	=> $gsm->GetSMSFolderList (),
    SMS_1	=> $gsm->GetSMS ("IN", 1),
    CalNotes	=> $gsm->GetCalendarNotes (0, 4),
    WAPSettings	=> $gsm->GetWapSettings (2),
    }, "Execute Get methods");

DDumper $get;

if (my @me = grep { $_->{name} eq "Merijn GS" } @{$get->{PhoneBookME}}) {
    my $err = $gsm->SendSMS ({
	destination	=> $me[0]{number},
	smscindex	=> 1,
	report		=> 1,
	eightbit	=> 1,
	message		=> "Sent from perl",
	});
    DDumper ({ err => $err, gsm => $gsm });
    }

done_testing;

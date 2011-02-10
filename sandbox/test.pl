#!/pro/bin/perl

use strict;
use warnings;
use autodie;

use GSM::Gnokii;
use Data::Peek;
use Time::Local;

my $gsm = GSM::Gnokii->new ({ verbose => 9 })->connect ();

my $command = shift // "";

if ($command eq "CreateSMSFolder") {
    my $err = $gsm->CreateSMSFolder ("Xut");
    my $sfl = $gsm->GetSMSFolderList ();
    DDumper {
	err => $gsm->{ERROR},
	ret => $err,
	sms => $sfl,
	};
    if (my $fid = map { $_->{location} } grep { $_->{name} eq "Xut" } @$sfl) {
	$err = $gsm->DeleteSMSFolder ($fid);
	$sfl = $gsm->GetSMSFolderList ();
	DDumper {
	    err => $gsm->{ERROR},
	    ret => $err,
	    sms => $sfl,
	    };
	}
    }

if ($command eq "WritePBE") {
    my $err = $gsm->WritePhonebookEntry ({
	memorytype	=> "ME",
	number		=> "+31612345678",
	location	=> 0,
	name		=> "XXX Test",
	caller_group	=> 3,	# "Work"
	person		=> {			# Doesn't work
	    family_name	=> "Doe",
	    given_name	=> "John",
	    },
	address		=> {			# Doesn't work
	    street	=> "Main road 1",
	    city	=> "Paris",
	    postal	=> "BC 1234-ACE",
	    },
	birthday	=> "2001-02-03",	# TODO
	date		=> "2011-02-03",	# TODO
	ext_group	=> 3,			# TODO
	e_mail		=> "test\@test.org",
	home_address	=> "Caravan 3a",	# Doesn't work
	nickname	=> "Johnny",
	note		=> "Remove this entry asap",
	tel_none	=> "+31600000000",	# FAIL
	tel_common	=> "+31600000001",	# FAIL
	tel_home	=> "+31600000002",
	tel_cell	=> "+31600000003",
	tel_fax		=> "+31600000004",
	tel_work	=> "+31600000006",
	tel_general	=> "+31600000010",	# FAIL
	company		=> "Testing Inc.",
	url		=> "http://www.test.org",
	});
    my $new = $err ? $gsm->GetPhonebook ("ME", $err, $err) : "FAIL";
    DDumper {
	err => $gsm->{ERROR},
	ret => $err,
	new => $new,
	};
    }

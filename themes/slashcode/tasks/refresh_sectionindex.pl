#!/usr/bin/perl -w
#
# $Id$
#
# SlashD Task (c) OSDN 2001
#
# Description: refreshes the static "sectionindex_display" template for use
# in HTML output.


use strict;
my $me = 'refresh_sectionindex.pl';

use vars qw( %task );

$task{$me}{timespec} = '1-30,55-59/3 * * * *';
$task{$me}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user) = @_;
	my $sections = $slashdb->getSectionInfo();

	my $new_template = slashDisplay('sectionindex', {
		sections => $sections,
	}, 1);

	my $tpid = $slashdb->getTemplateByName('sectionindex_display','tpid');
	my(%template) = ( 
		name => 'sectionindex_display',
		tpid => $tpid, 
		template => $new_template,
	);
	# If it exists, we update it, if not, we create it.
	if ($tpid) {
		$slashdb->setTemplate($tpid, \%template);
	} else {
		$slashdb->createTemplate(\%template);
	}

	slashdLog(sprintf "$me: %d sections refreshed", scalar @{$sections});
};

1;


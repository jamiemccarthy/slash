#!/usr/bin/perl -w

use strict;

use vars qw( %task $me );

# Remember that timespec goes by the database's time, which should be
# GMT if you installed everything correctly.  So 6:07 AM GMT is a good
# sort of midnightish time for the Western Hemisphere.  Adjust for
# your audience and admins.
$task{$me}{timespec} = '7 6 * * *';
$task{$me}{timespec_panic_2} = ''; # if major panic, dailyStuff can wait
$task{$me}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user) = @_;
	my($backupdb);
	if ($constants->{backup_db_user}) {
		$backupdb  = getObject('Slash::DB', $constants->{backup_db_user});
	} else {
		$backupdb = $slashdb;
	}

	unless($slashdb) {
		slashdLog('No database to run adminmail against');
		return;
	}

	slashdLog('Send Admin Mail Begin');
	my $count = $backupdb->countDaily();

	# homepage hits are logged as either '' or 'shtml'
	$count->{'index'}{'index'} += delete $count->{'index'}{''};
	$count->{'index'}{'index'} += delete $count->{'index'}{'shtml'};
	# these are 404s
	delete $count->{'index.html'};

	my $sdTotalHits = $backupdb->getVar('totalhits', 'value');

	$sdTotalHits = $sdTotalHits + $count->{'total'};
	$backupdb->setVar("totalhits", $sdTotalHits);

	$backupdb->updateStamps();

	my $email = <<EOT;
$constants->{sitename} Stats for yesterday

     total $count->{'total'}
    unique $count->{'unique'}
total hits $sdTotalHits
  homepage $count->{'index'}{'index'}
   indexes
EOT

	for (keys %{$count->{'index'}}) {
		$email .= "\t   $_=$count->{'index'}{$_}\n"
	}

	$email .= "\n-----------------------\n";


	for my $key (sort { $count->{'articles'}{$b} <=> $count->{'articles'}{$a} } keys %{$count->{'articles'}}) {
		my $value = $count->{'articles'}{$key};

 		my $story = $backupdb->getStory($key, ['title', 'uid']);

		$email .= sprintf("%s\t%s %s by %s\n",
			$value, $key, substr($story->{'title'}, 0, 30),
			$backupdb->getUser($story->{uid}, 'nickname')
		) if $story->{'title'} && $story->{uid} && $value > 100;
	}

	$email .= "\n-----------------------\n";
	$email .= `$constants->{slashdir}/bin/tailslash -u $virtual_user -y today`;
	$email .= "\n-----------------------\n";

	# Send a message to the site admin.
	for (@{$constants->{stats_reports}}) {
		sendEmail($_, "$constants->{sitename} Stats Report", $email, 'bulk');
	}
	slashdLog('Send Admin Mail End');

	return ;
};

1;


#!/usr/bin/perl -w

###############################################################################
# hof.pl - this page displays statistics about stories posted to the site 
# 
# Copyright (C) 1997 Rob "CmdrTaco" Malda
# malda@slashdot.org
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
#
#  $Id$
###############################################################################
use strict;
use Slash;
use Slash::Display;
use Slash::Utility;

##################################################################
sub main {
	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();
	my $section = getSection($form->{section});

	header(getData('head'), $section->{section});

	my(@topcomments, $topcomments);
	$topcomments = $slashdb->getCommentsTop($form->{sid});
	for (@$topcomments) {
		my $top = $topcomments[@topcomments] = {};
		# leave as "aid" for now
		@{$top}{qw(section sid aid title pid subj cdate sdate uid cid score)} = @$_;
		my $user_email = $slashdb->getUser($top->{uid}, ['fakeemail', 'nickname']);
		@{$top}{'fakeemail', 'nickname'} = @{$user_email}{'fakeemail', 'nickname'};
	}

	slashDisplay('main', {
		width		=> '98%',
		actives		=> $slashdb->countStories(),
		visited		=> $slashdb->countStoriesStuff(),
		activea		=> $slashdb->countStoriesAuthors(),
		activep		=> $slashdb->countPollquestions(),
		currtime	=> scalar localtime,
		topcomments	=> \@topcomments,
	});

# this is commented out ... ?
# 	if (0) {  #  only do this in static mode
# 		print "<P>";
# 		titlebar("100%", "Most Popular Slashboxes");
# 		my $boxes = $I{dbobject}->getDescription('sectionblocks');
# 		my(%b, %titles);
# 
# 		while (my($bid, $title) = each %$boxes) {
# 			$b{$bid} = 1;
# 			$titles{$bid} = $title;
# 		}
# 
# 
# 		#Something tells me we could simplify this with some 
# 		# thought -Brian
# 		foreach my $bid (keys %b) {
# 			$b{$bid} = $I{dbobject}->countUsersIndexExboxesByBid($bid);
# 		}
# 
# 		my $x;
# 		foreach my $bid (sort { $b{$b} <=> $b{$a} } keys %b) {
# 			$x++;
# 			$titles{$bid} =~ s/<(.*?)>//g;
# 			print <<EOT;
# 
# <B>$b{$bid}</B> <A HREF="$I{rootdir}/users.pl?op=preview&bid=$bid">$titles{$bid}</A><BR>
# EOT
# 			last if $x > 10;
# 		}
# 	}

	writeLog('hof');
	footer($form->{ssi});
}

#################################################################
createEnvironment();
main();

1;

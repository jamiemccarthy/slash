# This code is a part of Slash, which is Copyright 1997-2001 OSDN, and
# released under the GPL.  See README and COPYING for more information.
# $Id$

package Slash::Display::Provider;

=head1 NAME

Slash::Display::Provider - Template Toolkit provider for Slash

=head1 SYNOPSIS

	use Slash::Display::Provider;
	my $template = Template->new(
		LOAD_TEMPLATES	=> [ Slash::Display::Provider->new ]
	);


=head1 DESCRIPTION

This here module provides templates to a Template Toolkit processor
by way of the Slash API (which basically means that it grabs templates
from the blocks table in the database).  It caches them, too.  It also
can process templates passed in as text, like the base Provider module,
but this one will create a unique name for the "anonymous" template so
it can be cached.  Overriden methods include C<fetch>, C<_load>,
and C<_refresh>.

=cut

use strict;
use vars qw($REVISION $VERSION $DEBUG);
use base qw(Template::Provider);
use Slash::Utility;
use Template::Provider;

($REVISION)	= ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;
($VERSION)	= $REVISION =~ /^(\d+\.\d+)/;
$DEBUG		= $Template::Provider::DEBUG || 0 unless defined $DEBUG;

# BENDER: Oh, no room for Bender, huh?  Fine.  I'll go build my own lunar
# lander.  With blackjack.  And hookers.  In fact, forget the lunar lander
# and the blackjack!  Ah, screw the whole thing.

use constant PREV => 0;
use constant NAME => 1;
use constant DATA => 2; 
use constant LOAD => 3;
use constant NEXT => 4;

# store names for non-named templates by using text of template as
# hash key
my($anon_num, %anon_template);
sub _get_anon_name {
	my($text) = @_;
	return $anon_template{$text} if exists $anon_template{$text};
	return $anon_template{$text} = 'anon_' . ++$anon_num; 
}

sub fetch {
	my($self, $text) = @_;
	my($name, $data, $error, $slot, $size);
	$size = $self->{ SIZE };

	# if reference, then get a unique name to cache by
	if (ref $text eq 'SCALAR') {
		$text = $$text;
		print STDERR "fetch text : $text\n" if $DEBUG > 2;
		$name = _get_anon_name($text);

	# if regular scalar, get proper template ID ("name") from DB
	} else {
		my $slashdb = getCurrentDB();
		$name = $slashdb->getTemplateByName($text, 'tpid');
		print STDERR "fetch text : $text\n" if $DEBUG > 1;
		undef $text;
	}

	# caching disabled so load and compile but don't cache
	if (defined $size && !$size) {
		print STDERR "fetch($name) [nocache]\n" if $DEBUG;
		($data, $error) = $self->_load($name, $text);
		($data, $error) = $self->_compile($data) unless $error;
		$data = $data->{ data } unless $error;

	# cached entry exists, so refresh slot and extract data
	} elsif ($name && ($slot = $self->{ LOOKUP }{ $name })) {
		print STDERR "fetch($name) [cached:$size]\n" if $DEBUG;
		($data, $error) = $self->_refresh($slot);
		$data = $slot->[ DATA ] unless $error;

	# nothing in cache so try to load, compile and cache
	} else {
		print STDERR "fetch($name) [uncached:$size]\n" if $DEBUG;
		($data, $error) = $self->_load($name, $text);
		($data, $error) = $self->_compile($data) unless $error;
		$data = $self->_store($name, $data) unless $error;
	}

	return($data, $error);
}

sub _load {
	my($self, $name, $text) = @_;
	my($data, $error, $now, $time, $slashdb);
	$now = time;
	$time = 0;

	print STDERR "_load(@_[1 .. $#_])\n" if $DEBUG;

	if (! defined $text) {
		$slashdb = getCurrentDB();
		# in arrayref so we also get _modtime
		my $temp = $slashdb->getTemplate($name, ['template']);
		$text = $temp->{template};
		$time = $temp->{_modtime};
	}

	$data = {
		name	=> $name,
		text	=> $text,
		'time'	=> $time,
		load	=> $now,
	};

	return($data, $error);
}

# hm, refresh is almost what we want, except we want to override
# the logic for deciding whether to reload ... can that be determined
# without reimplementing the whole method?
sub _refresh {
	my($self, $slot) = @_;
	my($head, $file, $data, $error, $slashdb);
	$slashdb = getCurrentDB();

	print STDERR "_refresh([ @$slot ])\n" if $DEBUG;

	# compare load time with current _modtime from API to see if
	# its modified and we need to reload it
	if ($slot->[ DATA ]{modtime}) {
		my $temp = $slashdb->getTemplate($slot->[ NAME ], ['tpid']);
		if ($slot->[ DATA ]{modtime} < $temp->{_modtime}) {
			print STDERR "refreshing cache file ", $slot->[ NAME ], "\n"
				if $DEBUG;

			($data, $error) = $self->_load($slot->[ NAME ]);
			($data, $error) = $self->_compile($data) unless $error;
			$slot->[ DATA ] = $data->{ data } unless $error;
		}
	}

	# i know it is not a huge amount of cycles, but i wish
	# we didn't have to bother with LRU stuff if SIZE is undef,
	# but we don't want to break other methods that also use it

	# remove existing slot from usage chain...
	if ($slot->[ PREV ]) {
		$slot->[ PREV ][ NEXT ] = $slot->[ NEXT ];
	} else {
		$self->{ HEAD } = $slot->[ NEXT ];
	}

	if ($slot->[ NEXT ]) {
		$slot->[ NEXT ][ PREV ] = $slot->[ PREV ];
	} else {
		$self->{ TAIL } = $slot->[ PREV ];
	}

	# ... and add to start of list
	$head = $self->{ HEAD };
	$head->[ PREV ] = $slot if $head;
	$slot->[ PREV ] = undef;
	$slot->[ NEXT ] = $head;
	$self->{ HEAD } = $slot;

	return($data, $error);
}

1;

__END__


=head1 BUGS

=over 4

=item *

Crap, I think right now caching is not done per virtual host.

=item *

I am not sure how useful the caching is right now, especially the LRU
part.  Rethink.

=item *

We need to find a way to speed up execution of cached templates, if
possible.

=back


=head1 SEE ALSO

Template(3), Template::Provider(3), Slash(3), Slash::Utility(3),
Slash::Display(3).

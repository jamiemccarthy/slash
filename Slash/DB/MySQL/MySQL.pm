# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

package Slash::DB::MySQL;
use strict;
use Digest::MD5 'md5_hex';
use HTML::Entities;
use Slash::Utility;
use URI ();
use vars qw($VERSION);
use base 'Slash::DB';
use base 'Slash::DB::Utility';

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

# BENDER: I hate people who love me.  And they hate me.

# For the getDecriptions() method
my %descriptions = (
	'sortcodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='$_[1]'") },

	'generic'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='$_[2]'") },

	'statuscodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='statuscodes'") },

	'tzcodes'
		=> sub { $_[0]->sqlSelectMany('tz,off_set', 'tzcodes') },

	'tzdescription'
		=> sub { $_[0]->sqlSelectMany('tz,description', 'tzcodes') },

	'dateformats'
		=> sub { $_[0]->sqlSelectMany('id,description', 'dateformats') },

	'datecodes'
		=> sub { $_[0]->sqlSelectMany('id,format', 'dateformats') },

	'discussiontypes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='discussiontypes'") },

	'commentmodes'
		=> sub { $_[0]->sqlSelectMany('mode,name', 'commentmodes') },

	'threshcodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='threshcodes'") },

	'postmodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='postmodes'") },

	'isolatemodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='isolatemodes'") },

	'issuemodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='issuemodes'") },

	'vars'
		=> sub { $_[0]->sqlSelectMany('name,name', 'vars') },

	'topics'
		=> sub { $_[0]->sqlSelectMany('tid,alttext', 'topics') },

	'topics_all'
		=> sub { $_[0]->sqlSelectMany('tid,alttext', 'topics') },

	'maillist'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='maillist'") },

	'session_login'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='session_login'") },

	'displaycodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='displaycodes'") },

	'commentcodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='commentcodes'") },

	'sections'
		=> sub { $_[0]->sqlSelectMany('section,title', 'sections', 'isolate=0', 'order by title') },

	'static_block'
		=> sub { $_[0]->sqlSelectMany('bid,bid', 'blocks', "$_[2] >= seclev AND type != 'portald'") },

	'portald_block'
		=> sub { $_[0]->sqlSelectMany('bid,bid', 'blocks', "$_[2] >= seclev AND type = 'portald'") },

	'color_block'
		=> sub { $_[0]->sqlSelectMany('bid,bid', 'blocks', "type = 'color'") },

	'authors'
		=> sub { $_[0]->sqlSelectMany('U.uid,U.nickname', 'users as U, users_param as P', "P.name = 'author' AND U.uid = P.uid and P.value = 1") },

	'admins'
		=> sub { $_[0]->sqlSelectMany('uid,nickname', 'users', 'seclev >= 100') },

	'users'
		=> sub { $_[0]->sqlSelectMany('uid,nickname', 'users') },

	'templates'
		=> sub { $_[0]->sqlSelectMany('tpid,name', 'templates') },

	'templatesbypage'
		=> sub { $_[0]->sqlSelectMany('tpid,name', 'templates', "page = '$_[2]'") },

	'templatesbysection'
		=> sub { $_[0]->sqlSelectMany('tpid,name', 'templates', "section = '$_[2]'") },

	'pages'
		=> sub { $_[0]->sqlSelectMany('distinct page,page', 'templates') },

	'templatesections'
		=> sub { $_[0]->sqlSelectMany('distinct section, section', 'templates') },

	'sectionblocks'
		=> sub { $_[0]->sqlSelectMany('bid,title', 'blocks', 'portal=1') },

	'plugins'
		=> sub { $_[0]->sqlSelectMany('value,description', 'site_info', "name='plugin'") },

	'site_info'
		=> sub { $_[0]->sqlSelectMany('name,value', 'site_info', "name != 'plugin'") },

	'topic-sections'
		=> sub { $_[0]->sqlSelectMany('section,1', 'section_topics', "tid = '$_[2]'") },

	'forms'
		=> sub { $_[0]->sqlSelectMany('value,value', 'site_info', "name = 'form'") },

);

########################################################
sub _whereFormkey {
	my($self, $formkey_id) = @_;
	my $where;

	my $user = getCurrentUser();
	# anonymous user without cookie, check host, not formkey id
	if ($user->{anon_id} && ! $user->{anon_cookie}) {
		$where = "ipid = '$user->{ipid}'";
	} else {
		$where = "id='$formkey_id'";
	}

	return $where;
};

########################################################
# Notes:
#  formAbuse, use defaults as ENV, be able to override
#  	(pudge idea).
#  description method cleanup. (done)
#  fetchall_rowref vs fetch the hashses and push'ing
#  	them into an array (good arguments for both)
#	 break up these methods into multiple classes and
#   use the dB classes to override methods (this
#   could end up being very slow though since the march
#   is kinda slow...).
#	 the getAuthorEdit() methods need to be refined
########################################################

########################################################
sub init {
	my($self) = @_;
	# These are here to remind us of what exists
	$self->{_storyBank} = {};
	$self->{_codeBank} = {};
	$self->{_sectionBank} = {};
	$self->{_boxes} = {};
	$self->{_sectionBoxes} = {};
}

#######################################################
# Wrapper to get the latest ID from the database
sub getLastInsertId {
	my($self, $table, $col) = @_;
	my($answer) = $self->sqlSelect('LAST_INSERT_ID()');
	return $answer;
}

########################################################
# Yes, this is ugly, and we can ditch it in about 6 months
# Turn off autocommit here
sub sqlTransactionStart {
	my($self, $arg) = @_;
	$self->sqlDo($arg);
}

########################################################
# Put commit here
sub sqlTransactionFinish {
	my($self) = @_;
	$self->sqlDo("UNLOCK TABLES");
}

########################################################
# In another DB put rollback here
sub sqlTransactionCancel {
	my($self) = @_;
	$self->sqlDo("UNLOCK TABLES");
}

########################################################
# Bad need of rewriting....
sub createComment {
	my($self, $comment, $user, $pts, $default_user) = @_;
	# why no quote() anymore?
	my $header = $comment->{sid};
	my $cid;

	my $signature = md5_hex($comment->{postercomment});
	my $uid = $comment->{postanon} ? $default_user : $user->{uid};
	# Basically, this makes sure that the thread is not
	# been set read only -Brian
	return -1 if ($self->getDiscussion($header, 'type') == 2);

	my $insline = "INSERT into comments (sid,pid,date,ipid,subnetid,subject,uid,points,signature) values ($header," .
		$self->sqlQuote($comment->{pid}) . ",now(),'$user->{ipid}','$user->{subnetid}'," .
		$self->sqlQuote($comment->{postersubj}) . ", $uid, $pts, '$signature')";

	if ($self->sqlDo($insline)) {
		$cid = $self->getLastInsertId();
	} else {
		errorLog("$DBI::errstr $insline");
		return -1;
	}

	$self->sqlInsert('comment_text', {
			cid	=> $cid,
			comment	=>  $comment->{postercomment},
	});

	if (getCurrentStatic('mysql_heap_table')) {
		my $insline = "INSERT into comment_heap (sid,cid,pid,date,ipid,subnetid,subject,uid,points,signature) values ($header,$cid," .
			$self->sqlQuote($comment->{pid}) . ",now(),'$user->{ipid}','$user->{subnetid}'," .
			$self->sqlQuote($comment->{postersubj}) . ", $uid, $pts, '$signature')";
		$self->sqlDo($insline) or errorLog("$DBI::errstr $insline");
	}

	return $cid;
}

########################################################
sub setModeratorLog {
	my($self, $cid, $sid, $uid, $val, $reason) = @_;
	$self->sqlInsert("moderatorlog", {
		uid => $uid,
		val => $val,
		sid => $sid,
		cid => $cid,
		reason  => $reason,
		-ts => 'now()'
	});
}

########################################################
#this is broke right now -Brian
sub getMetamodComments {
	my($self, $id, $uid, $num_comments) = @_;

	my $table = 'comments';
	if (getCurrentStatic('mysql_heap_table')) {
		$table = 'comment_heap';
	}

	my $sth = $self->sqlSelectMany(
		"$table.cid,date," .
		"subject,comment,users.uid as uid,
		sig,pid,$table.sid as sid,
		moderatorlog.id as id,title,moderatorlog.reason as modreason,
		$table.reason",
		"$table,comment_text,users,users_info,moderatorlog,stories",
		"stories.sid=$table.sid AND moderatorlog.sid=$table.sid AND
		moderatorlog.cid=$table.cid AND moderatorlog.id>$id AND
		$table.uid!=$uid AND users.uid=$table.uid AND
		users.uid=users_info.uid AND users.uid!=$uid AND
		moderatorlog.uid!=$uid AND moderatorlog.reason<8 LIMIT $num_comments"
	);

	my $comments = [];
	while (my $comment = $sth->fetchrow_hashref) {
		# Anonymize comment that is to be metamoderated.
		@{$comment}{qw(nickname uid points sig)} = ('-', -1, 0, '');
		push @$comments, $comment;
	}
	$sth->finish;

	formatDate($comments);
	return $comments;
}

########################################################
sub getModeratorCommentLog {
	my($self, $sid, $cid) = @_;
# why was this removed?  -- pudge
#				"moderatorlog.active=1
# Probably by accident. -Brian

	my $table = 'comments';
	if (getCurrentStatic('mysql_heap_table')) {
		$table = 'comment_heap';
	}
	my $comments = $self->sqlSelectMany("$table.sid as sid,
				 $table.cid as cid,
				 $table.points as score,
				 moderatorlog.uid as uid,
				 users.nickname as nickname,
				 moderatorlog.val as val,
				 moderatorlog.reason as reason,
				 moderatorlog.ts as ts,
				 moderatorlog.active as active",
				"moderatorlog, users, $table",
				"moderatorlog.sid='$sid'
			     AND moderatorlog.cid=$cid
			     AND moderatorlog.uid=users.uid
			     AND $table.sid=moderatorlog.sid
			     AND $table.cid=moderatorlog.cid",
				"ORDER BY ts"
	);
	my(@comments, $comment);
	push @comments, $comment while ($comment = $comments->fetchrow_hashref);
	return \@comments;
}

########################################################
sub getModeratorLogID {
	my($self, $cid, $sid, $uid) = @_;
	my($mid) = $self->sqlSelect(
		"id", "moderatorlog",
		"uid=$uid and cid=$cid and sid='$sid'"
	);
	return $mid;
}

########################################################
sub unsetModeratorlog {
	my($self, $uid, $sid, $max, $min) = @_;
	my $cursor = $self->sqlSelectMany("cid,val", "moderatorlog",
			"uid=$uid and sid=$sid"
	);
	my @removed;

	while (my($cid, $val, $active, $max, $min) = $cursor->fetchrow){
		# We undo moderation even for inactive records (but silently for
		# inactive ones...)
		$self->sqlDo("delete from moderatorlog where
			cid=$cid and uid=$uid"
		);

		# If moderation wasn't actually performed, we should not change
		# the score.
		next if ! $active;

		# Insure scores still fall within the proper boundaries
		my $scorelogic = $val < 0
			? "points < $max"
			: "points > $min";
		$self->sqlUpdate(
			"comments",
			{ -points => "points+" . (-1 * $val) },
			"cid=$cid AND $scorelogic"
		);
		if (getCurrentStatic('mysql_heap_table')) {
			$self->sqlUpdate(
				"comment_heap",
				{ -points => "points+" . (-1 * $val) },
				"cid=$cid AND $scorelogic"
			);
		}
		push(@removed, $cid);
	}

	return \@removed;
}

########################################################
sub deleteSectionTopicsByTopic {
	my($self, $tid) = @_;

	$self->sqlDo("DELETE FROM section_topics WHERE tid=$tid");
}

########################################################
sub createSectionTopic {
	my($self, $section, $tid) = @_;

	$self->sqlDo("INSERT INTO section_topics VALUES (section, tid) ('$section','$tid')");
}

########################################################
sub getSectionTopicsNamesBySection {
	my($self, $section) = @_;

	my $answer = $self->sqlSelectColArrayref('topics.alttext', 'topics,section_topics', " section_topics.section = '$section' AND section_topics.tid = topics.tid");

	return $answer;
}

########################################################
sub getContentFilters {
	my($self, $formname, $field) = @_;

	my $field_string = $field ne '' ? " AND field = '$field'" : " AND field != ''";

	my $filters = $self->sqlSelectAll("*", "content_filters",
		"regex != '' $field_string and form = '$formname'");
	return $filters;
}

########################################################
sub createPollVoter {
	my($self, $qid, $aid) = @_;

	$self->sqlInsert("pollvoters", {
		qid	=> $qid,
		id	=> md5_hex($ENV{REMOTE_ADDR} . $ENV{HTTP_X_FORWARDED_FOR}),
		-'time'	=> 'now()',
		uid	=> $ENV{SLASH_USER}
	});

	$self->sqlDo("update pollquestions set
		voters=voters+1 where qid=$qid");
	$self->sqlDo("update pollanswers set votes=votes+1 where
		qid=$qid and aid=$aid");
}

########################################################
sub createSubmission {
	my($self, $submission) = @_;
	return unless $submission;

	$submission->{ipid} = getCurrentUser('ipid');
	$submission->{subnetid} = getCurrentUser('subnetid');

	my($sec, $min, $hour, $mday, $mon, $year) = localtime;
	my $subid = "$hour$min$sec.$mon$mday$year";

	$submission->{'-time'} = 'now()';
	$submission->{'subid'} = $subid;
	$self->sqlInsert('submissions', $submission);

	return $subid;
}

#################################################################
sub getStoryDiscussions {
	my($self) = @_;
	my $discussion = $self->sqlSelectAll("discussions.sid,discussions.title,discussions.url",
		"discussions,stories ",
		"displaystatus > -1 and discussions.sid=stories.sid and time <= now() and type = 0 ",
		"order by time desc LIMIT 50"
	);

	return $discussion;
}

#################################################################
# Less then 2, ince 2 would be a read only discussion
sub getDiscussions {
	my($self) = @_;
	my $discussion = $self->sqlSelectAll("id,title,url",
		"discussions",
		"type < 2 AND ts <= now()",
		"order by ts desc LIMIT 50"
	);

	return $discussion;
}

########################################################
# Handles admin logins (checks the sessions table for a cookie that
# matches).  Called during authentication
sub getSessionInstance {
	my($self, $uid, $session_in) = @_;
	my $admin_timeout = getCurrentStatic('admin_timeout');
	my $session_out = '';

	if ($session_in) {
		# CHANGE DATE_ FUNCTION
		$self->sqlDo("DELETE from sessions WHERE now() > DATE_ADD(lasttime, INTERVAL $admin_timeout MINUTE)");

		my $session_in_q = $self->{_dbh}->quote($session_in);

		my($uid) = $self->sqlSelect(
			'uid',
			'sessions',
			"session=$session_in_q"
		);

		if ($uid) {
			$self->sqlDo("DELETE from sessions WHERE uid = '$uid' AND " .
				"session != $session_in_q"
			);
			$self->sqlUpdate('sessions', {-lasttime => 'now()'},
				"session = $session_in_q"
			);
			$session_out = $session_in;
		}
	}
	if (!$session_out) {
		my($title) = $self->sqlSelect('lasttitle', 'sessions',
			"uid=$uid"
		);
		$title ||= "";

		$self->sqlDo("DELETE FROM sessions WHERE uid=$uid");

		$self->sqlInsert('sessions', { -uid => $uid,
			-logintime => 'now()', -lasttime => 'now()',
			lasttitle => $title }
		);
		$session_out = $self->getLastInsertId('sessions', 'session');
	}
	return $session_out;

}

########################################################
sub setContentFilter {
	my($self, $formname) = @_;

	my $form = getCurrentForm();

	$self->sqlUpdate("content_filters", {
			regex		=> $form->{regex},
			form		=> $formname,
			modifier	=> $form->{modifier},
			field		=> $form->{field},
			ratio		=> $form->{ratio},
			minimum_match	=> $form->{minimum_match},
			minimum_length	=> $form->{minimum_length},
			err_message	=> $form->{err_message},
		}, "filter_id=$form->{filter_id}"
	);
}

########################################################
# Only Slashdot uses this method
sub setSectionExtra {
	my($self, $full, $story) = @_;

	if ($full && $self->sqlTableExists($story->{section}) && $story->{section}) {
		my $extra = $self->sqlSelectHashref('*', $story->{section}, "sid='$story->{sid}'");
		for (keys %$extra) {
			$story->{$_} = $extra->{$_};
		}
	}

}

########################################################
# This creates an entry in the accesslog
sub createAccessLog {
	my($self, $op, $dat) = @_;

	my $uid;
	if ($ENV{SLASH_USER}) {
		$uid = $ENV{SLASH_USER};
	} else {
		$uid = getCurrentStatic('anonymous_coward_uid');
	}

	my $ipid = getCurrentUser('ipid');
	my $subnetid = getCurrentUser('subnetid');

	$self->sqlInsert('accesslog', {
		host_addr	=> $ipid,
		subnetid	=> $subnetid,
		dat		=> $dat,
		uid		=> $uid,
		op		=> $op,
		-ts		=> 'now()',
		query_string	=> $ENV{QUERY_STRING} || '0',
		user_agent	=> $ENV{HTTP_USER_AGENT} || '0',
	}, 1);

	if ($dat =~ /\//) {
		$self->sqlUpdate('stories', { -hits => 'hits+1' },
			'sid=' . $self->{_dbh}->quote($dat)
		);
		if (getCurrentStatic('mysql_heap_table')) {
			$self->sqlUpdate('story_heap', { -hits => 'hits+1' },
				'sid=' . $self->{_dbh}->quote($dat)
			);
		}
	}
}

########################################################
# pass in additional optional descriptions
sub getDescriptions {
	my($self, $codetype, $optional, $flag, $altdescs) =  @_;
	return unless $codetype;
	my $codeBank_hash_ref = {};
	# I am extending this, without the extension the cache was
	# not always returning the right data -Brian
	my $cache = '_getDescriptions_' . $codetype . $optional . $altdescs;

	if ($flag) {
		undef $self->{$cache};
	} else {
		return $self->{$cache} if $self->{$cache};
	}

	$altdescs ||= {};
	my $descref = $altdescs->{$codetype} || $descriptions{$codetype};

	my $sth = $descref->(@_);
	while (my($id, $desc) = $sth->fetchrow) {
		$codeBank_hash_ref->{$id} = $desc;
	}
	$sth->finish;

	$self->{$cache} = $codeBank_hash_ref if getCurrentStatic('cache_enabled');
	return $codeBank_hash_ref;
}

########################################################
# Get user info from the users table.
# If you don't pass in a $script, you get everything
# which is handy for you if you need the entire user

# why not just axe this entirely and always get all the data? -- pudge
# Worry about access times. Realize that when MySQL has row level
# locking that we can combine all of the user table (except param)
# into one table again. -Brian

sub getUserInstance {
	my($self, $uid, $script) = @_;

	my $user;
	unless ($script) {
		$user = $self->getUser($uid);
		return $user || undef;
	}

	$user = $self->sqlSelectHashref('*', 'users',
		' uid = ' . $self->{_dbh}->quote($uid)
	);
	return undef unless $user;
	my $user_extra = $self->sqlSelectHashref('*', "users_prefs", "uid=$uid");
	while (my($key, $val) = each %$user_extra) {
		$user->{$key} = $val;
	}

	# what is this for?  it appears to want to do the same as the
	# code above ... but this assigns a scalar to a scalar ...
	# perhaps `@{$user}{ keys %foo } = values %foo` is wanted?  -- pudge
#	$user->{ keys %$user_extra } = values %$user_extra;

#	if (!$script || $script =~ /index|article|comments|metamod|search|pollBooth/)
	{
		my $user_extra = $self->sqlSelectHashref('*', "users_comments", "uid=$uid");
		while (my($key, $val) = each %$user_extra) {
			$user->{$key} = $val;
		}
	}

	# Do we want the index stuff?
#	if (!$script || $script =~ /index/)
	{
		my $user_extra = $self->sqlSelectHashref('*', "users_index", "uid=$uid");
		while (my($key, $val) = each %$user_extra) {
			$user->{$key} = $val;
		}
	}

	return $user;
}

########################################################
sub deleteUser {
	my($self, $uid) = @_;
	return unless $uid;
	$self->setUser($uid, {
		bio		=> '',
		nickname	=> 'deleted user',
		matchname	=> 'deleted user',
		realname	=> 'deleted user',
		realemail	=> '',
		fakeemail	=> '',
		newpasswd	=> '',
		homepage	=> '',
		passwd		=> '',
		sig		=> '',
		seclev		=> 0
	});
	$self->sqlDo("DELETE FROM users_param WHERE uid=$uid");
}

########################################################
# Get user info from the users table.
sub getUserAuthenticate {
	my($self, $user, $passwd, $kind) = @_;
	my($uid, $cookpasswd, $newpass, $dbh, $user_db,
		$cryptpasswd, @pass);

	return unless $user && $passwd;

	# if $kind is 1, then only try to auth password as plaintext
	# if $kind is 2, then only try to auth password as encrypted
	# if $kind is undef or 0, try as encrypted
	#	(the most common case), then as plaintext
	my($EITHER, $PLAIN, $ENCRYPTED) = (0, 1, 2);
	my($UID, $PASSWD, $NEWPASSWD) = (0, 1, 2);
	$kind ||= $EITHER;

	# RECHECK LOGIC!!  -- pudge

	$dbh = $self->{_dbh};
	$user_db = $dbh->quote($user);
	$cryptpasswd = encryptPassword($passwd);
	@pass = $self->sqlSelect(
		'uid,passwd,newpasswd',
		'users',
		"uid=$user_db"
	);

	# try ENCRYPTED -> ENCRYPTED
	if ($kind == $EITHER || $kind == $ENCRYPTED) {
		if ($passwd eq $pass[$PASSWD]) {
			$uid = $pass[$UID];
			$cookpasswd = $passwd;
		}
	}

	# try PLAINTEXT -> ENCRYPTED
	if (($kind == $EITHER || $kind == $PLAIN) && !defined $uid) {
		if ($cryptpasswd eq $pass[$PASSWD]) {
			$uid = $pass[$UID];
			$cookpasswd = $cryptpasswd;
		}
	}

	# try PLAINTEXT -> NEWPASS
	if (($kind == $EITHER || $kind == $PLAIN) && !defined $uid) {
		if ($passwd eq $pass[$NEWPASSWD]) {
			$self->sqlUpdate('users', {
				newpasswd	=> '',
				passwd		=> $cryptpasswd
			}, "uid=$user_db");
			$newpass = 1;

			$uid = $pass[$UID];
			$cookpasswd = $cryptpasswd;
		}
	}

	# return UID alone in scalar context
	return wantarray ? ($uid, $cookpasswd, $newpass) : $uid;
}

########################################################
# Make a new password, save it in the DB, and return it.
sub getNewPasswd {
	my($self, $uid) = @_;
	my $newpasswd = changePassword();
	$self->sqlUpdate('users', {
		newpasswd => $newpasswd
	}, 'uid=' . $self->{_dbh}->quote($uid));
	return $newpasswd;
}


########################################################
# Get user info from the users table.
# May be worth it to cache this at some point
sub getUserUID {
	my($self, $name) = @_;

#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# We need to add BINARY to this
# as is, it may be a security flaw
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	my($uid) = $self->sqlSelect('uid', 'users',
		'nickname=' . $self->{_dbh}->quote($name)
	);

	return $uid;
}

#################################################################
sub getCommentsByUID {
	my($self, $uid, $min) = @_;

	my $table = "comments";
	if (getCurrentStatic('mysql_heap_table')) {
		$table = 'comment_heap';
	}
	my $sqlquery = "SELECT pid,sid,cid,subject,date,points "
			. " FROM $table WHERE uid=$uid "
			. " ORDER BY date DESC LIMIT $min,50 ";

	my $sth = $self->{_dbh}->prepare($sqlquery);
	$sth->execute;
	my($comments) = $sth->fetchall_arrayref;
	formatDate($comments, 4);
	return $comments;
}

#################################################################
sub getCommentsByNetID {
	my($self, $id, $min) = @_;

	my $table = "comments";
	if (getCurrentStatic('mysql_heap_table')) {
		$table = 'comment_heap';
	}
	my $sqlquery = "SELECT pid,sid,cid,subject,date,points "
			. " FROM $table WHERE ipid='$id' "
			. " ORDER BY date DESC LIMIT $min,50 ";

	my $sth = $self->{_dbh}->prepare($sqlquery);
	$sth->execute;
	my($comments) = $sth->fetchall_arrayref;
	formatDate($comments, 4);
	return $comments;
}

#################################################################
sub getCommentsBySubnetID{
	my($self, $subnetid, $min) = @_;

	my $table = "comments";
	if (getCurrentStatic('mysql_heap_table')) {
		$table = 'comment_heap';
	}
	my $sqlquery = "SELECT pid,sid,cid,subject,date,points "
			. " FROM $table WHERE subnetid='$subnetid' "
			. " ORDER BY date DESC LIMIT $min,50 ";

	my $sth = $self->{_dbh}->prepare($sqlquery);
	$sth->execute;
	my($comments) = $sth->fetchall_arrayref;
	formatDate($comments, 4);
	return $comments;
}

#################################################################
# Just create an empty content_filter
sub createContentFilter {
	my($self, $formname) = @_;

	$self->sqlInsert("content_filters", {
		regex		=> '',
		form		=> $formname,
		modifier	=> '',
		field		=> '',
		ratio		=> 0,
		minimum_match	=> 0,
		minimum_length	=> 0,
		err_message	=> ''
	});

	my $filter_id = $self->getLastInsertId('content_filters', 'filter_id');

	return $filter_id;
}

sub checkEmail {
	my($self, $email) = @_;

	# Returns count of users matching $email.
	return ($self->sqlSelect('count(uid)', 'users',
		'realemail=' . $self->{_dbh}->quote($email)))[0];
}

#################################################################
# Replication issue. This needs to be a two-phase commit.
sub createUser {
	my($self, $matchname, $email, $newuser) = @_;
	return unless $matchname && $email && $newuser;

	return if ($self->sqlSelect(
		"count(uid)", "users",
		"matchname=" . $self->{_dbh}->quote($matchname)
	))[0] || $self->checkEmail($email);

	$self->sqlInsert("users", {
		uid		=> '',
		realemail	=> $email,
		nickname	=> $newuser,
		matchname	=> $matchname,
		seclev		=> 1,
		passwd		=> encryptPassword(changePassword())
	});

# This is most likely a transaction problem waiting to
# bite us at some point. -Brian
	my $uid = $self->getLastInsertId('users', 'uid');
	return unless $uid;
	$self->sqlInsert("users_info", {
		uid 			=> $uid,
		-lastaccess		=> 'now()',
	});
	$self->sqlInsert("users_prefs", { uid => $uid });
	$self->sqlInsert("users_comments", { uid => $uid });
	$self->sqlInsert("users_index", { uid => $uid });

	# All param fields should be set here, as some code may not behave
	# properly if the values don't exist.
	#
	# You know, I know this might be slow, but maybe this thing could be
	# initialized by a template? Wild thought, but that would prevent
	# site admins from having to edit CODE to set this stuff up.
	#
	#	- Cliff
	# Initialize the expiry variables...
	# ...users start out as registered...
	# ...the default email view is to SHOW email address...
	my $constants = getCurrentStatic();
	$self->setUser($uid, {
		'registered'		=> 1,
		'expiry_comm'		=> $constants->{min_expiry_comm},
		'expiry_days'		=> $constants->{min_expiry_days},
		'user_expiry_comm'	=> $constants->{min_expiry_comm},
		'user_expiry_days'	=> $constants->{min_expiry_days},
		'emaildisplay'		=> 2,
	});

	return $uid;
}


########################################################
# Do not like this method -Brian
sub setVar {
	my($self, $name, $value) = @_;
	if (ref $value) {
		$self->sqlUpdate('vars', {
			value		=> $value->{'value'},
			description	=> $value->{'description'}
		}, 'name=' . $self->sqlQuote($name));
	} else {
		$self->sqlUpdate('vars', {
			value		=> $value
		}, 'name=' . $self->sqlQuote($name));
	}
}

########################################################
sub setSession {
	my($self, $name, $value) = @_;
	$self->sqlUpdate('sessions', $value, 'uid=' . $self->{_dbh}->quote($name));
}

########################################################
sub setBlock {
	_genericSet('blocks', 'bid', '', @_);
}

########################################################
sub setDiscussion {
	_genericSet('discussions', 'id', '', @_);
}

########################################################
sub setDiscussionBySid {
	_genericSet('discussions', 'sid', '', @_);
}

########################################################
sub setPollQuestion {
	_genericSet('pollquestions', 'qid', '', @_);
}

########################################################
sub setTemplate {
	for (qw| page name section |) {
		next unless $_[2]->{$_};
		if ($_[2]->{$_} =~ /;/) {
			errorLog("A semicolon was found in the $_ while trying to update a template");
			return;
		}
	}
	_genericSet('templates', 'tpid', '', @_);
}

########################################################
sub getCommentCid {
	my($self, $sid, $cid) = @_;
	my $table = "comments";
	if (getCurrentStatic('mysql_heap_table')) {
		$table = 'comment_heap';
	}
	my($scid) = $self->sqlSelectAll('cid', $table, "sid='$sid' and pid='$cid'");

	return $scid;
}

########################################################
sub deleteComment {
	my($self, $sid, $cid) = @_;
	if ($cid) {
		$self->sqlDo("DELETE FROM comments WHERE cid=$cid");
		$self->sqlDo("DELETE FROM comment_text WHERE cid=$cid");
		if (getCurrentStatic('mysql_heap_table')) {
			$self->sqlDo("DELETE FROM comment_heap WHERE cid=$cid");
		}
	} else {
		my $table = "comments";
		if (getCurrentStatic('mysql_heap_table')) {
			$table = 'comment_heap';
		}
		my $ids = $self->sqlSelectAll('cid', $table, "sid='$sid'");
		$self->sqlDo("DELETE FROM comments WHERE sid=" .  $self->{_dbh}->quote($sid));
		for (@$ids) {
			$self->sqlDo("DELETE FROM comment_text WHERE cid=$_->[0]");
		}
		if (getCurrentStatic('mysql_heap_table')) {
			$self->sqlDo("DELETE FROM $table WHERE sid=" .  $self->{_dbh}->quote($sid));
		}
		$self->sqlDo("UPDATE stories SET writestatus=10 WHERE sid='$sid'");
	}
}

########################################################
sub getCommentPid {
	my($self, $sid, $cid) = @_;

	my $table = "comments";
	if (getCurrentStatic('mysql_heap_table')) {
		$table = 'comment_heap';
	}

	$self->sqlSelect('pid', $table,
		"sid='$sid' and cid=$cid");
}

########################################################
sub setSection {
# We should perhaps be passing in a reference to F here. More
# thought is needed. -Brian
	my($self, $section, $qid, $title, $issue, $isolate, $artcount) = @_;
	my $section_dbh = $self->{_dbh}->quote($section);
	my($count) = $self->sqlSelect("count(*)", "sections", "section=$section_dbh");
	my($ok1, $ok2);

	# This is a poor attempt at a transaction I might add. -Brian
	# I need to do this diffently under Oracle
	unless ($count) {
		$self->sqlDo("INSERT into sections (section) VALUES($section_dbh)");
		$ok1++ unless $self->{_dbh}->errstr;
	}

	$self->sqlUpdate('sections', {
			qid		=> $qid,
			title		=> $title,
			issue		=> $issue,
			isolate		=> $isolate,
			artcount	=> $artcount
		}, "section=$section_dbh"
	);
	$ok2++ unless $self->{_dbh}->errstr;

	return($count, $ok1, $ok2);
}

########################################################
sub setStoryCount {
	my($self, $sid, $count) = @_;
	return unless $sid;

	$self->sqlUpdate('stories', {
		-commentcount	=> "commentcount-$count",
		writestatus	=> 1
	}, 'sid=' . $self->sqlQuote($sid));

	if (getCurrentStatic('mysql_heap_table')) {
		$self->sqlUpdate('story_heap', {
			-commentcount	=> "commentcount-$count",
			writestatus	=> 1
		}, 'sid=' . $self->sqlQuote($sid));
	}
}

########################################################
sub getSectionTitle {
	my($self) = @_;
	my $sth = $self->{_dbh}->prepare("SELECT section,title FROM sections ORDER BY section");
	$sth->execute;
	my $sections = $sth->fetchall_arrayref;
	$sth->finish;

	return $sections;
}

########################################################
# Long term, this needs to be modified to take in account
# of someone wanting to delete a submission that is
# not part in the form
sub deleteSubmission {
	my($self, $subid) = @_;
	my $uid = getCurrentUser('uid');
	my $form = getCurrentForm();
	my %subid;

	if ($form->{subid}) {
		$self->sqlUpdate("submissions", { del => 1 },
			"subid=" . $self->{_dbh}->quote($form->{subid})
		);
		$self->setUser($uid,
			{ -deletedsubmissions => 'deletedsubmissions+1' }
		);
		$subid{$form->{subid}}++;
	}

	foreach (keys %{$form}) {
		next unless /(.*)_(.*)/;
		my($t, $n) = ($1, $2);
		if ($t eq "note" || $t eq "comment" || $t eq "section") {
			$form->{"note_$n"} = "" if $form->{"note_$n"} eq " ";
			if ($form->{$_}) {
				my %sub = (
					note	=> $form->{"note_$n"},
					comment	=> $form->{"comment_$n"},
					section	=> $form->{"section_$n"}
				);

				if (!$sub{note}) {
					delete $sub{note};
					$sub{-note} = 'NULL';
				}

				$self->sqlUpdate("submissions", \%sub,
					"subid=" . $self->{_dbh}->quote($n));
			}
		} else {
			my $key = $n;
			$self->sqlUpdate("submissions", { del => 1 },
				"subid='$key'");
			$self->setUser($uid,
				{ -deletedsubmissions => 'deletedsubmissions+1' }
			);
			$subid{$n}++;
		}
	}

	return keys %subid;
}

########################################################
sub deleteSession {
	my($self, $uid) = @_;
	return unless $uid;
	$uid = defined($uid) || getCurrentUser('uid');
	if (defined $uid) {
		$self->sqlDo("DELETE FROM sessions WHERE uid=$uid");
	}
}

########################################################
sub deleteAuthor {
	my($self, $uid) = @_;
	$self->sqlDo("DELETE FROM sessions WHERE uid=$uid");
}

########################################################
sub deleteTopic {
	my($self, $tid) = @_;
	$self->sqlDo('DELETE from topics WHERE tid=' . $self->{_dbh}->quote($tid));
}

########################################################
sub revertBlock {
	my($self, $bid) = @_;
	my $db_bid = $self->{_dbh}->quote($bid);
	my $block = $self->{_dbh}->selectrow_array("SELECT block from backup_blocks WHERE bid=$db_bid");
	$self->sqlDo("update blocks set block = $block where bid = $db_bid");
}

########################################################
sub deleteBlock {
	my($self, $bid) = @_;
	$self->sqlDo('DELETE FROM blocks WHERE bid =' . $self->{_dbh}->quote($bid));
}

########################################################
sub deleteTemplate {
	my($self, $tpid) = @_;
	$self->sqlDo('DELETE FROM templates WHERE tpid=' . $self->{_dbh}->quote($tpid));
}

########################################################
sub deleteSection {
	my($self, $section) = @_;
	$self->sqlDo("DELETE from sections WHERE section='$section'");
}

########################################################
sub deleteContentFilter {
	my($self, $id) = @_;
	$self->sqlDo("DELETE from content_filters WHERE filter_id = $id");
}

########################################################
sub saveTopic {
	my($self) = @_;
	my $form = getCurrentForm();
	my($rows) = $self->sqlSelect('count(*)', 'topics', 'tid=' . $self->{_dbh}->quote($form->{tid}));
	if ($rows == 0) {
		$self->sqlInsert('topics', {
			tid	=> $form->{tid},
			image	=> $form->{image},
			alttext	=> $form->{alttext},
			width	=> $form->{width},
			height	=> $form->{height}
		});
	}

	$self->sqlUpdate('topics', {
			image	=> $form->{image},
			alttext	=> $form->{alttext},
			width	=> $form->{width},
			height	=> $form->{height}
		}, 'tid=' . $self->{_dbh}->quote($form->{tid})
	);
}

##################################################################
sub saveBlock {
	my($self, $bid) = @_;
	my($rows) = $self->sqlSelect('count(*)', 'blocks',
		'bid=' . $self->{_dbh}->quote($bid)
	);

	my $form = getCurrentForm();
	if ($form->{save_new} && $rows > 0) {
		return $rows;
	}

	if ($rows == 0) {
		$self->sqlInsert('blocks', { bid => $bid, seclev => 500 });
	}

	my($portal, $retrieve) = (0, 0);

	# this is to make sure that a  static block doesn't get
	# saved with retrieve set to true
	$form->{retrieve} = 0 if $form->{type} ne 'portald';

	$form->{block} = $self->autoUrl($form->{section}, $form->{block})
		unless $form->{type} eq 'template';

	if ($rows == 0 || $form->{blocksavedef}) {
		$self->sqlUpdate('blocks', {
			seclev		=> $form->{bseclev},
			block		=> $form->{block},
			description	=> $form->{description},
			type		=> $form->{type},
			ordernum	=> $form->{ordernum},
			title		=> $form->{title},
			url		=> $form->{url},
			rdf		=> $form->{rdf},
			section		=> $form->{section},
			retrieve	=> $form->{retrieve},
			portal		=> $form->{portal},
		}, 'bid=' . $self->{_dbh}->quote($bid));
		$self->sqlUpdate('backup_blocks', {
			block		=> $form->{block},
		}, 'bid=' . $self->{_dbh}->quote($bid));
	} else {
		$self->sqlUpdate('blocks', {
			seclev		=> $form->{bseclev},
			block		=> $form->{block},
			description	=> $form->{description},
			type		=> $form->{type},
			ordernum	=> $form->{ordernum},
			title		=> $form->{title},
			url		=> $form->{url},
			rdf		=> $form->{rdf},
			section		=> $form->{section},
			retrieve	=> $form->{retrieve},
			portal		=> $form->{portal},
		}, 'bid=' . $self->{_dbh}->quote($bid));
	}


	return $rows;
}

########################################################
sub saveColorBlock {
	my($self, $colorblock) = @_;
	my $form = getCurrentForm();

	my $db_bid = $self->{_dbh}->quote($form->{color_block} || 'colors');

	if ($form->{colorsave}) {
		# save into colors and colorsback
		$self->sqlUpdate('blocks', {
				block => $colorblock,
			}, "bid = $db_bid"
		);

	} elsif ($form->{colorsavedef}) {
		# save into colors and colorsback
		$self->sqlUpdate('blocks', {
				block => $colorblock,
			}, "bid = $db_bid"
		);
		$self->sqlUpdate('backup_blocks', {
				block => $colorblock,
			}, "bid = $db_bid"
		);

	} elsif ($form->{colororig}) {
		# reload original version of colors
		my $block = $self->{_dbh}->selectrow_array("SELECT block FROM backup_blocks WHERE bid = $db_bid");
		$self->sqlDo("UPDATE blocks SET block = $block WHERE bid = $db_bid");
	}
}

########################################################
sub getSectionBlock {
	my($self, $section) = @_;
	my $block = $self->sqlSelectAll("section,bid,ordernum,title,portal,url,rdf,retrieve",
		"blocks", "section=" . $self->{_dbh}->quote($section),
		"ORDER by ordernum"
	);

	return $block;
}

########################################################
sub getSectionBlocks {
	my($self) = @_;

	my $blocks = $self->sqlSelectAll("bid,title,ordernum", "blocks", "portal=1", "order by bid");

	return $blocks;
}

########################################################
sub getAuthorDescription {
	my($self) = @_;
	my $authors = $self->sqlSelectAll("count(*) as c, uid",
		"stories", '', "GROUP BY uid ORDER BY c DESC"
	);

	return $authors;
}

########################################################
# This method does not follow basic guidlines
sub getPollVoter {
	my($self, $id) = @_;

	my $md5 = md5_hex($ENV{REMOTE_ADDR} . $ENV{HTTP_X_FORWARDED_FOR});
	my($voters) = $self->sqlSelect('id', 'pollvoters',
		"qid=$id AND id='$md5' AND uid=$ENV{SLASH_USER}"
	);

	return $voters;
}

########################################################
# Yes, I hate the name of this. -Brian
sub savePollQuestion {
	my($self, $poll) = @_;
	$poll->{voters} ||= "0";
	if ($poll->{qid}) {
		$self->sqlUpdate("pollquestions", {
			question	=> $poll->{question},
			voters		=> $poll->{voters},
			topic		=> $poll->{topic},
			sid		=> $poll->{sid},
			-date		=>'now()'
		});
	} else {
		$self->sqlInsert("pollquestions", {
			question	=> $poll->{question},
			voters		=> $poll->{voters},
			topic		=> $poll->{topic},
			sid		=> $poll->{sid},
			uid		=> getCurrentUser('uid'),
			-date		=>'now()'
		});
		$poll->{qid} = $self->getLastInsertId();
	}

	$self->setVar("currentqid", $poll->{qid}) if $poll->{currentqid};

	# Loop through 1..8 and insert/update if defined
	for (my $x = 1; $x < 9; $x++) {
		if ($poll->{"aid$x"}) {
			$self->sqlReplace("pollanswers", {
				aid	=> $x,
				qid	=> $poll->{qid},
				answer	=> $poll->{"aid$x"},
				votes	=> $poll->{"votes$x"}
			});

		} else {
			$self->sqlDo("DELETE from pollanswers WHERE qid=$poll->{qid} and aid=$x");
		}
	}
	return $poll->{qid};
}

########################################################
# A note, this does not remove the issue of a story
# still having a poll attached to it (orphan issue)
sub deletePoll {
	my($self, $qid) = @_;

	$self->sqlDo("DELETE from pollanswers WHERE qid=$qid");
	$self->sqlDo("DELETE from pollquestions WHERE qid=$qid");
	$self->sqlDo("DELETE from pollvoters WHERE qid=$qid");
}

########################################################
sub getPollQuestionList {
	my($self, $time) = @_;
	my $questions = $self->sqlSelectAll("qid, question, date",
		"pollquestions order by date DESC LIMIT $time,20");

	formatDate($questions, 2, 2, '%F'); # '%A %B %E' || '%F'

	return $questions;
}

########################################################
sub getPollAnswers {
	my($self, $id, $val) = @_;
	my $values = join ',', @$val;
	my $answers = $self->sqlSelectAll($values, 'pollanswers', "qid=$id", 'ORDER by aid');

	return $answers;
}

########################################################
sub getPollQuestions {
# This may go away. Haven't finished poll stuff yet
#
	my($self, $limit) = @_;

	$limit = 25 if (!defined($limit));

	my $poll_hash_ref = {};
	my $sql = "SELECT qid,question FROM pollquestions ORDER BY date DESC ";
	$sql .= " LIMIT $limit " if $limit;
	my $sth = $self->{_dbh}->prepare_cached($sql);
	$sth->execute;
	while (my($id, $desc) = $sth->fetchrow) {
		$poll_hash_ref->{$id} = $desc;
	}
	$sth->finish;

	return $poll_hash_ref;
}

########################################################
sub deleteStory {
	my($self, $sid) = @_;
	$self->sqlUpdate('stories', { writestatus => 5 },
		'sid=' . $self->{_dbh}->quote($sid)
	);

	$self->sqlDo("DELETE from discussions WHERE sid = '$sid'");
}

########################################################
# for slashd
sub deleteStoryAll {
	my($self, $sid) = @_;
	my $db_sid = $self->sqlQuote($sid);

	$self->sqlDo("DELETE from stories where sid=$db_sid");
	$self->sqlDo("DELETE from story_text where sid=$db_sid");
	if (getCurrentStatic('mysql_heap_table')) {
		$self->sqlDo("DELETE from story_heap where sid=$db_sid");
	}
}

########################################################
sub setStory {
	my($self, $sid, $hashref) = @_;
	my(@param, %update_tables, $cache);
	# ??? should we do this?  -- pudge
	my $table = 'stories';
	my $table_prime = 'sid';
	my $param_table = 'story_param';
	my $tables = [qw(
		stories story_text
	)];

	$cache = _genericGetCacheName($self, $tables);

	for (keys %$hashref) {
		(my $clean_val = $_) =~ s/^-//;
		my $key = $self->{$cache}{$clean_val};
		if ($key) {
			push @{$update_tables{$key}}, $_;
		} else {
			push @param, [$_, $hashref->{$_}];
		}
	}

	for my $table (keys %update_tables) {
		my %minihash;
		for my $key (@{$update_tables{$table}}){
			$minihash{$key} = $hashref->{$key}
				if defined $hashref->{$key};
		}
		$self->sqlUpdate($table, \%minihash, 'sid=' . $sid, 1);
		if (getCurrentStatic('mysql_heap_table') and $table eq 'stories') {
			$self->sqlUpdate('story_heap', \%minihash, 'sid=' . $sid, 1);
		}
	}

	for (@param)  {
		$self->sqlReplace($param_table, {
			sid	=> $sid,
			name	=> $_->[0],
			value	=> $_->[1]
		}) if defined $_->[1];
	}
}

########################################################
sub getSubmissionLast {
	my($self, $id, $formname) = @_;

	my $where = $self->_whereFormkey($id);
	my($last_submitted) = $self->sqlSelect(
		"max(submit_ts)",
		"formkeys",
		"$where AND formname = '$formname'");
	$last_submitted ||= 0;

	return $last_submitted;
}


########################################################
sub updateFormkeyId {
	my($self, $formname, $formkey, $anon, $uid, $rlogin, $upasswd) = @_;

	if ($uid != $anon && $rlogin && length($upasswd) > 1) {
		$self->sqlUpdate("formkeys", {
			id	=> $uid,
			uid	=> $uid,
		}, "formname='$formname' AND uid = $anon AND formkey=" .
			$self->{_dbh}->quote($formkey));
	}
}

########################################################
sub createFormkey {
	my($self, $formname, $id, $sid) = @_;
	my $form = getCurrentForm();
	my $ipid = getCurrentUser('ipid');

	# save in form object for printing to user
	$form->{formkey} = getFormkey();

	# insert the fact that the form has been displayed, but not submitted at this point
	$self->sqlInsert('formkeys', {
		formkey		=> $form->{formkey},
		formname 	=> $formname,
		id 		=> $id,
		sid		=> $sid,
		uid		=> $ENV{SLASH_USER},
		ipid		=> $ipid,
		value		=> 0,
		ts		=> time()
	});
}

########################################################
sub checkFormkey {
	my($self, $formkey_earliest, $formname, $formkey_id, $formkey) = @_;

	my $where = $self->_whereFormkey($formkey_id);
	my($is_valid) = $self->sqlSelect('count(*)', 'formkeys',
		'formkey = ' . $self->{_dbh}->quote($formkey) .
		" AND $where " .
		"AND ts >= $formkey_earliest AND formname = '$formname'");

	errorLog(<<EOT) unless $is_valid;

SELECT count(*) FROM formkeys WHERE formkey = '$formkey' AND $where \
	AND ts >=  $formkey_earliest AND formname = '$formname'
EOT

	return $is_valid;
}

##################################################################
sub checkTimesPosted {
	my($self, $formname, $max, $id, $formkey_earliest) = @_;

	my $where = $self->_whereFormkey($id);
	my($times_posted) = $self->sqlSelect(
		"count(*) as times_posted",
		'formkeys',
		"$where AND submit_ts >= $formkey_earliest AND formname = '$formname'");

	return $times_posted >= $max ? 0 : 1;
}

##################################################################
# the form has been submitted, so update the formkey table
# to indicate so
sub formSuccess {
	my($self, $formkey, $cid, $length) = @_;

	# update formkeys to show that there has been a successful post,
	# and increment the value from 0 to 1 (shouldn't ever get past 1)
	# meaning that yes, this form has been submitted, so don't try i t again.
	$self->sqlUpdate("formkeys", {
			-value          => 'value+1',
			cid             => $cid,
			submit_ts       => time(),
			content_length  => $length,
		}, "formkey=" . $self->{_dbh}->quote($formkey)
	);
}

##################################################################
sub formFailure {
	my($self, $formkey) = @_;
	$self->sqlUpdate("formkeys", {
			value   => -1,
		}, "formkey=" . $self->{_dbh}->quote($formkey)
	);
}

##################################################################
# logs attempts to break, fool, flood a particular form
sub createAbuse {
	my($self, $reason, $script_name, $query_string, $uid, $ipid, $subnetid) = @_;

	my $user = getCurrentUser();
	$uid      ||= $user->{uid};
	$ipid     ||= $user->{ipid};
	$subnetid ||= $user->{subnetid};

	# logem' so we can banem'
	$self->sqlInsert("abusers", {
		uid		=> $uid,
		ipid		=> $ipid,
		subnetid	=> $subnetid,
		pagename	=> $script_name,
		querystring	=> $query_string || '',
		reason		=> $reason,
		-ts		=> 'now()',
	});
}

##################################################################
sub setExpired {
	my($self, $uid) = @_;

	if  (! $self->checkExpired($uid)) {
		$self->setUser($uid, { expired => 1});
		$self->sqlInsert('accesslist', {
			-uid		=> $uid,
			formname 	=> 'comments', 
			-readonly	=> 1,
			-ts		=> 'now()',
			reason		=> 'expired'
		}) if $uid ;
	}
}

##################################################################
sub setUnexpired {
	my($self, $uid) = @_;

	if ($self->checkExpired($uid)) {
		$self->setUser($uid, { expired => 0});
		my $sql = "WHERE uid = $uid AND reason = 'expired' AND formname = 'comments'";
		$self->sqlDo("DELETE from accesslist $sql") if $uid;
	}
}

##################################################################
sub checkExpired {
	my($self, $uid) = @_;

	my $where = "uid = $uid AND readonly = 1 AND reason = 'expired'";

	$self->sqlSelect(
		"readonly",
		"accesslist", $where
	);
}

##################################################################
sub checkReadOnly {
	my($self, $formname, $user) = @_;

	my $curuser = getCurrentUser();
	my $constants = getCurrentStatic();

	my $where = '';

	# please check to make sure this is what you want;
	# isAnon already checks for numeric uids -- pudge
	if ($user->{uid} && $user->{uid} =~ /^\d+$/) {
		if (!isAnon($user->{uid})) {
			$where = "uid = $user->{uid}";
		} else {
			$where = "ipid = '$curuser->{ipid}'";
		}
	} elsif ($user->{md5id}) {
		$where = "(ipid = '$user->{md5id}' OR subnetid = '$user->{md5id}')";

	} elsif ($user->{ipid}) {
		$where = "ipid = '$user->{ipid}'";

	} elsif ($user->{subnetid}) {
		$where = "subnetid = '$user->{subnetid}'";
	} else {
		$where = "ipid = '$curuser->{ipid}'";
	}

	$where .= " AND readonly = 1 AND formname = '$formname' AND reason != 'expired'";

	$self->sqlSelect("readonly", "accesslist", $where);
}

##################################################################
sub getUIDList {
	my($self, $column, $id) = @_;

	my $fields = { ipid => 'ipid', subnetid => 'subnetid' };
	my $where = "WHERE $fields->{$column} = '$id'";
	$self->sqlSelectAll("DISTINCT uid ", "comments $where");
}

##################################################################
sub getNetIDList {
	my($self, $id) = @_;
	my $where = "WHERE uid = '$id'";
	$self->sqlSelectAll("DISTINCT ipid", "comments $where");
}

##################################################################
sub getReadOnlyReason {
	my($self, $formname, $user) = @_;

	my $constants = getCurrentStatic();
	my $ref = {};
	my($reason,$where) = ('','');

	if ($user) {
		if ($user->{uid} =~ /^\d+$/ && !isAnon($user->{uid})) {
			$where = "WHERE uid = $user->{uid}";
		} elsif ($user->{ipid}) {
			$where = "WHERE ipid = '$user->{ipid}'";
		} elsif ($user->{subnetid}) {
			$where = "WHERE subnetid = '$user->{subnetid}'";
		} else {
			$where = "WHERE uid = $user->{uid}";
		}
	} else {
		$user = $self->getCurrentUser();
		$where = "WHERE (ipid = '$user->{ipid}' OR subnetid = '$user->{subnetid}')";
	}

	$where .= " AND readonly = 1 AND formname = '$formname' AND reason != 'expired'";

	$ref = $self->sqlSelectAll("reason", "accesslist $where");

	for (@$ref) {
		if ($reason eq '') {
			$reason = $_->[0];
		} elsif ($reason ne $_->[0]) {
			$reason = 'multiple';
			return($reason);
		}
	}

	return($reason);
}

##################################################################
sub setReadOnly {
	# do not use this method to set/unset expired
	my($self, $formname, $user, $flag, $reason) = @_;

	return if $reason eq 'expired';

	my $constants = getCurrentStatic();
	my $rows;

	my $where = '/* setReadOnly WHERE clause */';

	if ($user) {
		if ($user->{uid} =~ /^\d+$/ && !isAnon($user->{uid})) {
			$where .= "uid = $user->{uid}";

		} elsif ($user->{ipid}) {
			$where = "ipid = '$user->{ipid}'";

		} elsif ($user->{subnetid}) {
			$where = "subnetid = '$user->{subnetid}'";
		}

	} else {
		$user = getCurrentUser();
		$where = "(ipid = '$user->{ipid}' OR subnetid = '$user->{subnetid}')";
	}

	$where .= " AND formname = '$formname' AND reason != 'expired'";

	$rows = $self->sqlSelect("count(*) FROM accesslist WHERE $where AND readonly = 1");
	$rows ||= 0;

	if ($flag == 0 && $rows > 0) {
		$self->sqlDo("DELETE from accesslist WHERE $where");
	} else { 
		if ($reason && $rows == 1) {
			my $return = $self->sqlUpdate("accesslist", {
				-readonly	=> $flag,
			 	reason		=> $reason,
			}, $where);

			return $return ? 1 : 0;
		} else {
			my $return = $self->sqlInsert("accesslist", {
				-uid		=> $user->{uid},
				ipid		=> $user->{ipid},
				subnetid	=> $user->{subnetid},
				formname	=> $formname,
				-ts		=> "now()",
				-readonly	=> $flag,
				reason		=> $reason
			});
			return $return ? 1 : 0;
		}
	}
}

##################################################################
# Check to see if the form already exists
sub checkForm {
	my($self, $formkey, $formname) = @_;
	$self->sqlSelect(
		"value,submit_ts",
		"formkeys", "formkey='$formkey' and formname = '$formname'"
	);
}

##################################################################
# Current admin users
sub currentAdmin {
	my($self) = @_;
	my $aids = $self->sqlSelectAll('nickname,lasttime,lasttitle', 'sessions,users',
		'sessions.uid=users.uid GROUP BY sessions.uid'
	);

	return $aids;
}

########################################################
#
sub getTopNewsstoryTopics {
	my($self, $all) = @_;
	my $when = "AND to_days(now()) - to_days(time) < 14" unless $all;
	my $order = $all ? "ORDER BY alttext" : "ORDER BY cnt DESC";
	my $table = getCurrentStatic('mysql_heap_table') ? 'story_heap' : 'stories';
	my $topics = $self->sqlSelectAll("topics.tid, alttext, image, width, height, count(*) as cnt", "topics,$table",
		"topics.tid=$table.tid
		$when
		GROUP BY topics.tid
		$order"
	);

	return $topics;
}

##################################################################
# Get poll
sub getPoll {
	my($self, $qid) = @_;

	my $sth = $self->{_dbh}->prepare_cached("
			SELECT question,answer,aid,votes  from pollquestions, pollanswers
			WHERE pollquestions.qid=pollanswers.qid AND
			pollquestions.qid=$qid
			ORDER BY pollanswers.aid
	");
	$sth->execute;
	my $polls = $sth->fetchall_arrayref;
	$sth->finish;

	return $polls;
}

##################################################################
sub getSubmissionsSections {
	my($self) = @_;
	my $del = getCurrentForm('del');

	my $hash = $self->sqlSelectAll("section,note,count(*)", "submissions WHERE del=$del GROUP BY section,note");

	return $hash;
}

##################################################################
# Get submission count
sub getSubmissionsPending {
	my($self, $uid) = @_;
	my $submissions;

	if ($uid) {
		$submissions = $self->sqlSelectAll("time, subj, section, tid, del", "submissions", "uid=$uid");
	} else {
		$uid = getCurrentUser('uid');
		$submissions = $self->sqlSelectAll("time, subj, section, tid, del", "submissions", "uid=$uid");
	}
	return $submissions;
}

##################################################################
# Get submission count
sub getSubmissionCount {
	my($self, $articles_only) = @_;
	my($count);
	if ($articles_only) {
		($count) = $self->sqlSelect('count(*)', 'submissions',
			"(length(note)<1 or isnull(note)) and del=0" .
			" and section='articles'"
		);
	} else {
		($count) = $self->sqlSelect("count(*)", "submissions",
			"(length(note)<1 or isnull(note)) and del=0"
		);
	}
	return $count;
}

##################################################################
# Get all portals
sub getPortals {
	my($self) = @_;
	my $strsql = "SELECT block,title,blocks.bid,url
		   FROM blocks
		  WHERE section='index'
		    AND portal > -1
		  GROUP BY bid
		  ORDER BY ordernum";

	my $sth = $self->{_dbh}->prepare($strsql);
	$sth->execute;
	my $portals = $sth->fetchall_arrayref;

	return $portals;
}

##################################################################
# Get standard portals
sub getPortalsCommon {
	my($self) = @_;
	return($self->{_boxes}, $self->{_sectionBoxes}) if keys %{$self->{_boxes}};
	$self->{_boxes} = {};
	$self->{_sectionBoxes} = {};
	my $sth = $self->sqlSelectMany(
			'bid,title,url,section,portal,ordernum',
			'blocks',
			'',
			'ORDER BY ordernum ASC'
	);
	# We could get rid of tmp at some point
	my %tmp;
	while (my $SB = $sth->fetchrow_hashref) {
		$self->{_boxes}{$SB->{bid}} = $SB;  # Set the Slashbox
		next unless $SB->{ordernum} > 0;  # Set the index if applicable
		push @{$tmp{$SB->{section}}}, $SB->{bid};
	}
	$self->{_sectionBoxes} = \%tmp;
	$sth->finish;

	return($self->{_boxes}, $self->{_sectionBoxes});
}

##################################################################
sub countCommentsBySid {
	my($self, $sid) = @_;
	my $table = "comments";
	if (getCurrentStatic('mysql_heap_table')) {
		$table = 'comment_heap';
	}
	return $self->sqlCount($table, "sid=$sid");
}

##################################################################
sub countCommentsBySidUID {
	my($self, $sid, $uid) = @_;
	my $table = "comments";
	if (getCurrentStatic('mysql_heap_table')) {
		$table = 'comment_heap';
	}
	return $self->sqlCount($table, "sid=$sid AND uid=$uid");
}

##################################################################
sub countCommentsBySidPid {
	my($self, $sid, $pid) = @_;
	my $table = "comments";
	if (getCurrentStatic('mysql_heap_table')) {
		$table = 'comment_heap';
	}
	return $self->sqlCount($table, "sid=$sid AND pid=$pid");
}

##################################################################
# Search on block comparison! No way, easier on everything
# if we just do a match on the signature (AKA MD5 of the comment)
# -Brian
sub findCommentsDuplicate {
	my($self, $sid, $comment) = @_;
	my $signature = md5_hex($comment);
	my $table = "comments";
	if (getCurrentStatic('mysql_heap_table')) {
		$table = 'comment_heap';
	}
	return $self->sqlCount($table, "sid=$sid AND signature='$signature'");
}

##################################################################
# counts the number of stories
sub countStory {
	my($self, $tid) = @_;
	my($value) = $self->sqlSelect("count(*)", "stories", "tid=" . $self->{_dbh}->quote($tid));

	return $value;
}

##################################################################
sub checkForMetaModerator {
	my($self, $user) = @_;
	return unless $user->{willing};
	return if $user->{is_anon};
	return if $user->{karma} < 0;
	my($d) = $self->sqlSelect('to_days(now()) - to_days(lastmm)',
		'users_info', "uid = '$user->{uid}'");
	return unless $d;
	my($tuid) = $self->sqlSelect('count(*)', 'users');
	return if $user->{uid} >
		  $tuid * $self->getVar('m2_userpercentage', 'value');
	# what to do with I hash here?
	return 1;  # OK to M2
}

##################################################################
sub getAuthorNames {
	my($self) = @_;
	my $authors = $self->getDescriptions('authors');
	my @authors;
	for (values %$authors){
		push @authors, $_;
	}

	return [sort(@authors)];
}

##################################################################
# Oranges to Apples. Would it be faster to grab some of this
# data from the cache? Or is it just as fast to grab it from
# the database?
sub getStoryByTime {
	my($self, $sign, $story, $isolate, $section) = @_;
	my($where);
	my $user = getCurrentUser();

	my $order = $sign eq '<' ? 'DESC' : 'ASC';
	if ($isolate) {
		$where = 'AND section=' . $self->{_dbh}->quote($story->{'section'})
			if $isolate == 1;
	} else {
		$where = 'AND displaystatus=0';
	}

	$where .= "   AND tid not in ($user->{'extid'})" if $user->{'extid'};
	$where .= "   AND uid not in ($user->{'exaid'})" if $user->{'exaid'};
	$where .= "   AND section not in ($user->{'exsect'})" if $user->{'exsect'};
	$where .= "   AND sid != '$story->{'sid'}'";

	my $time = $story->{'time'};
	my $table = getCurrentStatic('mysql_heap_table') ? 'story_heap' : 'stories';
	my $returnable = $self->sqlSelectHashref(
			'title, sid, section', $table,
			"time $sign '$time' AND writestatus >= 0 AND time < now() $where",
			"ORDER BY time $order LIMIT 1"
	);

	return $returnable;
}

########################################################
sub countStories {
	my($self) = @_;
	my $stories = $self->sqlSelectAll("sid,title,section,commentcount,users.nickname",
		"stories,users", "stories.uid=users.uid", "ORDER BY commentcount DESC LIMIT 10"
	);
	return $stories;
}

########################################################
sub setModeratorVotes {
	my($self, $uid, $metamod) = @_;
	$self->sqlUpdate("users_info", {
		-m2unfairvotes	=> "m2unfairvotes+$metamod->{unfair}",
		-m2fairvotes	=> "m2fairvotes+$metamod->{fair}",
		-lastmm		=> 'now()',
		lastmmid	=> 0
	}, "uid=$uid");
}

########################################################
sub setMetaMod {
	my($self, $m2victims, $flag, $ts) = @_;

	my $constants = getCurrentStatic();
	my $returns = [];

	# Update $muid's Karma
	$self->sqlTransactionStart("LOCK TABLES users_info WRITE, metamodlog WRITE");
	for (keys %{$m2victims}) {
		my $muid = $m2victims->{$_}[0];
		my $val = $m2victims->{$_}[1];
		next unless $val;
		push(@$returns , [$muid, $val]);

		my $mmid = $_;
		if ($muid && $val && !$flag) {
			if ($val eq '+') {
				$self->sqlUpdate("users_info", { -m2fair => "m2fair+1" }, "uid=$muid");
				# There is a limit on how much karma you can get from M2.
				$self->sqlUpdate("users_info", { -karma => "karma+1" },
					"$muid=uid and karma<$constants->{m2_maxbonus}");
			} elsif ($val eq '-') {
				$self->sqlUpdate("users_info", { -m2unfair => "m2unfair+1" },
					"uid=$muid");
				$self->sqlUpdate("users_info", { -karma => "karma-1" },
					"$muid=uid and karma>$constants->{badkarma}");
			}
		}
		# Time is now fixed at form submission time to ease 'debugging'
		# of the moderation system, ie 'GROUP BY uid, ts' will give
		# you the M2 votes for a specific user ordered by M2 'session'
		$self->sqlInsert("metamodlog", {
			-mmid => $mmid,
			-uid  => $ENV{SLASH_USER},
			-val  => ($val eq '+') ? 1 : -1,
			-ts   => "from_unixtime($ts)",
			-flag => $flag
		});
	}
	$self->sqlTransactionFinish();

	return $returns;
}

########################################################
sub getModeratorLast {
	my($self, $uid) = @_;
	my $last = $self->sqlSelectHashref(
		"(to_days(now()) - to_days(lastmm)) as lastmm, lastmmid",
		"users_info",
		"uid=$uid"
	);

	return $last;
}

########################################################
# No, this is not API, this is pretty specialized
sub getModeratorLogRandom {
	my($self) = @_;
	my $m2 = getCurrentStatic('m2_comments');
	my($min, $max) = $self->sqlSelect("min(id),max(id)", "moderatorlog");
	return $min + int rand($max - $min - $m2);
}

########################################################
sub countUsers {
	my($self) = @_;
	my($users) = $self->sqlSelect("count(*)", "users");
	return $users;
}

########################################################
sub countStoriesTopHits {
	my($self) = @_;
	my $stories = $self->sqlSelectAll("sid,title,section,hits,users.nickname",
		"stories,users", "stories.uid=users.uid",
		"ORDER BY hits DESC LIMIT 10"
	);
	return $stories;
}

########################################################
sub countStoriesAuthors {
	my($self) = @_;
	my $authors = $self->sqlSelectAll("count(*) as c, nickname, homepage",
		"stories, users", "users.uid=stories.uid",
		"GROUP BY stories.uid ORDER BY c DESC LIMIT 10"
	);
	return $authors;
}

########################################################
sub countPollquestions {
	my($self) = @_;
	my $pollquestions = $self->sqlSelectAll("voters,question,qid", "pollquestions",
		"1=1", "ORDER by voters DESC LIMIT 10"
	);
	return $pollquestions;
}

########################################################
sub createVar {
	my($self, $name, $value, $desc) = @_;
	$self->sqlInsert('vars', {name => $name, value => $value, description => $desc});
}

########################################################
sub deleteVar {
	my($self, $name) = @_;

	$self->sqlDo("DELETE from vars WHERE name=" .
		$self->{_dbh}->quote($name));
}

########################################################
# I'm not happy with this method at all
sub setCommentCleanup {
	my($self, $val, $sid, $reason, $modreason, $cid) = @_;
	# Grab the user object.
	my $user = getCurrentUser();
	my $constants = getCurrentStatic();
	my($cuid, $ppid, $subj, $points, $oldreason) = $self->getComments($sid, $cid);

	my $strsql = "SET
		points=points$val,
		reason=$reason,
		lastmod=$user->{uid}
		WHERE sid=" . $self->{_dbh}->quote($sid)."
		AND cid=$cid
		AND points " .
			($val < 0 ? " > $constants->{comment_minscore}" : "") .
			($val > 0 ? " < $constants->{comment_maxscore}" : "");

	$strsql .= " AND lastmod<>$user->{uid}"
		unless $user->{seclev} >= 100 && $constants->{authors_unlimited};

	if ($val ne "+0" && $self->sqlDo("UPDATE comments $strsql")) {
		if (getCurrentStatic('mysql_heap_table')) {
			$self->sqlDo("UPDATE comment_heap $strsql")
		}
		$self->setModeratorLog($cid, $sid, $user->{uid}, $val, $modreason);

		# Adjust comment posters karma
		if ($cuid != $constants->{anonymous_coward}) {
			if ($val > 0) {
				$self->sqlUpdate("users_info", {
						-karma	=> "karma$val",
						-upmods	=> 'upmods+1',
					}, "uid=$cuid AND karma < $constants->{maxkarma}"
				);
			} elsif ($val < 0) {
				$self->sqlUpdate("users_info", {
						-karma		=> "karma$val",
						-downmods	=> 'downmods+1',
					}, "uid=$cuid AND karma > $constants->{minkarma}"
				);
			}
		}

		# Adjust moderators total mods
		$self->sqlUpdate(
			"users_info",
			{ -totalmods => 'totalmods+1' },
			"uid=$user->{uid}"
		);

		# And deduct a point.
		$user->{points} = $user->{points} > 0 ? $user->{points} - 1 : 0;
		$self->sqlUpdate(
			"users_comments",
			{ -points=>$user->{points} },
			"uid=$user->{uid}"
		);
		return 1;
	}
	return;
}

########################################################
sub countUsersIndexExboxesByBid {
	my($self, $bid) = @_;
	my($count) = $self->sqlSelect("count(*)", "users_index",
		qq!exboxes like "%'$bid'%" !
	);

	return $count;
}

########################################################
sub getCommentReply {
	my($self, $sid, $pid) = @_;
	my $table = "comments";
	if (getCurrentStatic('mysql_heap_table')) {
		$table = 'comment_heap';
	}
	my $reply = $self->sqlSelectHashref("date, subject,$table.points as points,
		comment_text.comment as comment,realname,nickname,
		fakeemail,homepage,$table.cid as cid,sid,users.uid as uid",
		"$table,comment_text,users,users_info,users_comments",
		"sid=$sid
		AND $table.cid=$pid
		AND users.uid=users_info.uid
		AND users.uid=users_comments.uid
		AND $table.cid=comment_text.cid
		AND users.uid=$table.uid"
	) || {};

	formatDate([$reply]);
	return $reply;
}

########################################################
sub getCommentsForUser {
	my($self, $sid, $cid) = @_;

	my $table = 'comments';
	if (getCurrentStatic('mysql_heap_table')) {
		$table = 'comment_heap';
	}

	my $user = getCurrentUser();
	my $sql = "SELECT cid,date,
				subject,nickname,homepage,fakeemail,
				users.uid as uid,sig,
				$table.points as points,pid,sid,
				lastmod, reason
			   FROM $table,users
			  WHERE sid=" . $self->{_dbh}->quote($sid) . "
			    AND $table.uid=users.uid";
	if ($user->{hardthresh}) {
		$sql .= "    AND (";
		$sql .= "	$table.points >= " . $self->{_dbh}->quote($user->{threshold});
		$sql .= "     OR $table.uid=$user->{uid}" unless $user->{is_anon};
		$sql .= "     OR cid=$cid" if $cid;
		$sql .= "	)";
	}
	$sql .= "	  ORDER BY ";
	$sql .= "$table.points DESC, " if $user->{commentsort} eq '3';
	$sql .= " cid ";
	$sql .= ($user->{commentsort} == 1 || $user->{commentsort} == 5) ? 'DESC' : 'ASC';


	my $thisComment = $self->{_dbh}->prepare_cached($sql) or errorLog($sql);
	$thisComment->execute or errorLog($sql);
	my $comments = [];
	while (my $comment = $thisComment->fetchrow_hashref){
		$comment->{comment} = $self->_getCommentText($comment->{cid});
		push @$comments, $comment;
	}
	formatDate($comments);
	return $comments;
}

########################################################
# This is here to save us a database lookup when drawing comment pages.
# 
# Couldn't this go faster by having getCommentsForUser() (10 lines up) collect a list
# of all the cid's it needs (i.e. doesn't already have in cache) and then grabbing them
# all with one SELECT?  SELECT cid,comment_text FROM comment WHERE cid IN (2,3,5,7...);
# - Jamie
sub _getCommentText {
	my($self, $cid) = @_;
	if ($self->{_comment_text} && $self->{_comment_text}{$cid}) {
		return $self->{_comment_text}{$cid};
	}

	$self->{_comment_text}{$cid} = $self->sqlSelect('comment', 'comment_text', 'cid='. $cid);
	return $self->{_comment_text}{$cid};
}

########################################################
sub getComments {
	my($self, $sid, $cid) = @_;
	my $table = 'comments';
	if (getCurrentStatic('mysql_heap_table')) {
		$table = 'comment_heap';
	}
	$self->sqlSelect("uid,pid,subject,points,reason",
		$table, "cid=$cid and sid=$sid"
	);
}

########################################################
sub getStoriesEssentials {
	my($self, $section, $limit, $tid, $section_display) = @_;
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	$section ||= $user->{currentSection};
	$section_display ||= $form->{section};

	$limit ||= $section eq 'index'
		? $user->{maxstories}
		: $self->getSection($section, 'artcount');

	my $table = getCurrentStatic('mysql_heap_table') ? 'story_heap' : 'stories';
	my $columns = 'sid, uid, commentcount, title, section, time, hits, hitparade';

	my $where = "1=1 AND time<now() "; # Mysql's Optimize gets 1 = 1";
	$where .= "AND displaystatus=0 " unless $form->{section};
	$where .= "AND (displaystatus>=0 AND section='$section') " if $section_display;
	$where .= "AND tid='$tid' " if $tid;

	# User Config Vars
	$where .= "AND tid not in ($user->{extid}) "		if $user->{extid};
	$where .= "AND uid not in ($user->{exaid}) "		if $user->{exaid};
	$where .= "AND section not in ($user->{exsect}) "	if $user->{exsect};

	# Order
	my $other = "ORDER BY time DESC ";

	# We need to check up on this later for performance -Brian
	my(@stories, $count);
	my $cursor = $self->sqlSelectMany($columns, $table, $where, $other)
		or errorLog("error in getStoriesEssentials columns $columns table $table where $where other $other");

	while (my $row = $cursor->fetchrow_hashref) {

		# We'll end up with these keys (sample values):
		# yyyy (2001)		MM (06)		dd (21)
		# hh (13)		mm (27)		ss (11)
		# mon ("Jun")		day (20010621)	wordytime ("Sunday June 21 12:34 PM")
		my @timesplit = split /\D+/, $row->{'time'};
		for my $i (0..$#timesplit) {
			$row->{ (qw( yyyy MM dd hh mm ss ))[$i] } = $timesplit[$i];
		}
		formatDate([ $row ], 'time', 'day', '%Q');

		# If we're not back to the day the user asked for, skip it.
		next if $form->{issue} and $row->{day} > $form->{issue};

		$row->{mon} = ${Date::Manip::Lang}{${Date::Manip::Cnf}{Language}}{MonL}[$row->{MM}-1];
		formatDate([ $row ], 'time', 'wordytime', '%A %B %d %I %M %p');
		push @stories, $row;
		last if ++$count >= $limit;

	}
	$cursor->finish;

	return \@stories;
}

########################################################
# This is going to blow chunks -Brian
sub getCommentsTop {
	my($self, $sid) = @_;
	my $user = getCurrentUser();
	my $table = "comments";
	if (getCurrentStatic('mysql_heap_table')) {
		$table = 'comment_heap';
	}
	my $where = "stories.sid=$table.sid and stories.uid=users.uid";
	$where .= " AND stories.sid=" . $self->{_dbh}->quote($sid) if $sid;
	my $stories = $self->sqlSelectAll("section, stories.sid, users.nickname, title, pid, subject,"
		. "date, time, $table.uid, cid, points"
		, "stories, $table, users"
		, $where
		, " ORDER BY points DESC, date DESC LIMIT 10 ");

	formatDate($stories, 6);
	formatDate($stories, 7);
	return $stories;
}

########################################################
# This makes me nervous... we grab, and they get
# deleted? I may move the delete to the setQuickies();
sub getQuickies {
	my($self) = @_;
# This is doing nothing (unless I am just missing the point). We grab
# them and then null them? -Brian
#  my($stuff) = $self->sqlSelect("story", "submissions", "subid='quickies'");
#	$stuff = "";
	$self->sqlDo("DELETE FROM submissions WHERE subid='quickies'");
	my $stuff;

	my $submission = $self->sqlSelectAll("subid,subj,email,name,story",
		"submissions", "note='Quik' and del=0"
	);

	return $submission;
}

########################################################
sub setQuickies {
	my($self, $content) = @_;
	$self->sqlInsert("submissions", {
		subid	=> 'quickies',
		subj	=> 'Generated Quickies',
		email	=> '',
		name	=> '',
		-'time'	=> 'now()',
		section	=> 'articles',
		tid	=> 'quickies',
		story	=> $content,
		uid	=> getCurrentStatic('anonymous_coward_uid'),
	});
}

########################################################
# What an ugly method
sub getSubmissionForUser {
	my($self) = @_;
	my $form = getCurrentForm();
	my $user = getCurrentUser();

	my $sql = "SELECT subid,subj,time,tid,note,email,name,section,comment,submissions.uid,karma FROM submissions,users_info";
	$sql .= "  WHERE submissions.uid=users_info.uid AND $form->{del}=del AND (";
	$sql .= $form->{note} ? "note=" . $self->{_dbh}->quote($form->{note}) : "isnull(note)";
	$sql .= "		or note=' ' " unless $form->{note};
	$sql .= ")";
	$sql .= "		and tid='$form->{tid}' " if $form->{tid};
	$sql .= "         and section=" . $self->{_dbh}->quote($user->{section}) if $user->{section};
	$sql .= "         and section=" . $self->{_dbh}->quote($form->{section}) if $form->{section};
	$sql .= "	  ORDER BY time";

	my $cursor = $self->{_dbh}->prepare($sql);
	$cursor->execute;

	my $submission = $cursor->fetchall_arrayref;

	formatDate($submission, 2, 2, '%m/%d  %H:%M');

	return $submission;
}

########################################################
sub getTrollAddress {
	my($self) = @_;

	my $ipid = getCurrentUser('ipid');
	my $table = "comments";
	if (getCurrentStatic('mysql_heap_table')) {
		$table = 'comment_heap';
	}
	my($badIP) = $self->sqlSelect("sum(val)", "$table,moderatorlog",
			"$table.sid=moderatorlog.sid AND $table.cid=moderatorlog.cid
			AND ipid ='$ENV{REMOTE_ADDR}' AND moderatorlog.active=1
			AND (to_days(now()) - to_days(ts) < 3) GROUP BY ipid"
	);

	return $badIP;
}

########################################################
sub getTrollUID {
	my($self) = @_;
	my $user = getCurrentUser();
	my $table = "comments";
	if (getCurrentStatic('mysql_heap_table')) {
		$table = 'comment_heap';
	}
	my($badUID) = $self->sqlSelect("sum(val)", "$table,moderatorlog",
		"$table.cid=moderatorlog.cid
		AND $table.uid=$user->{uid} AND moderatorlog.active=1
		AND (to_days(now()) - to_days(ts) < 3)  GROUP BY $table.uid"
	);

	return $badUID;
}


########################################################
sub createDiscussion {
	my($self, $sid, $title, $time, $url, $topic,  $type) = @_;

	#If no type is specified we assume the value is zero
	$type ||= 0;
	$sid ||= '';

	$self->sqlInsert('discussions', {
		sid	=> $sid,
		title	=> $title,
		ts	=> $time,
		url	=> $url,
		topic	=> $topic,
		type	=> $type,
		uid	=> getCurrentUser('uid'),
	});

	return $self->getLastInsertId();
}

########################################################
sub createStory {
	my($self, $story) = @_;
	unless ($story) {
		$story ||= getCurrentForm();
	}
	#Create a sid
	my($sec, $min, $hour, $mday, $mon, $year) = localtime;
	$year = $year % 100;
	# yes, this format is correct, don't change it :-)
	my $sid = sprintf('%02d/%02d/%02d/%02d%0d2%02d',
		$year, $mon+1, $mday, $hour, $min, $sec);

	# If this came from a submission, update submission and grant
	# Karma to the user
	my $suid;
	if ($story->{subid}) {
		my $constants = getCurrentStatic();
		my($suid) = $self->sqlSelect(
			'uid', 'submissions',
			'subid=' . $self->{_dbh}->quote($story->{subid})
		);

		# i think i got this right -- pudge
		my($userkarma) = $self->sqlSelect('karma', 'users_info', "uid=$suid");
		my $newkarma = (($userkarma + $constants->{submission_bonus})
			> $constants->{maxkarma})
				? $constants->{maxkarma}
				: "karma+$constants->{submission_bonus}";
		$self->sqlUpdate('users_info', { -karma => $newkarma }, "uid=$suid")
			if !isAnon($suid);

		$self->sqlUpdate('users_info',
			{ -karma => 'karma + 3' },
			"uid=$suid"
		) if !isAnon($suid);

		$self->sqlUpdate('submissions',
			{ del=>2 },
			'subid=' . $self->{_dbh}->quote($story->{subid})
		);
	}

	my $data = {
		sid		=> $sid,
		uid		=> $story->{uid},
		tid		=> $story->{tid},
		dept		=> $story->{dept},
		'time'		=> $story->{'time'},
		title		=> $story->{title},
		section		=> $story->{section},
		writestatus	=> $story->{writestatus},
		displaystatus	=> $story->{displaystatus},
		commentstatus	=> $story->{commentstatus}
	};

	my $text = {
		sid		=> $sid,
		bodytext	=> $story->{bodytext},
		introtext	=> $story->{introtext},
		relatedtext	=> $story->{relatedtext},
	};

	$self->sqlInsert('stories', $data);
	$self->sqlInsert('story_text', $text);
	if (getCurrentStatic('mysql_heap_table')) {
		$self->sqlInsert('story_heap', $data);
	}
	$self->_saveExtras($story);

	return $sid;
}

##################################################################
sub updateStory {
	my($self) = @_;
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();
	$self->sqlUpdate('discussions', {
		sid	=> $form->{sid},
		title	=> $form->{title},
		url	=> "$constants->{rootdir}/article.pl?sid=$form->{sid}",
		ts	=> $form->{'time'},
	}, 'sid = ' . $self->{_dbh}->quote($form->{sid}));

	$self->sqlUpdate('stories', {
		uid		=> $form->{uid},
		tid		=> $form->{tid},
		dept		=> $form->{dept},
		'time'		=> $form->{'time'},
		title		=> $form->{title},
		section		=> $form->{section},
		writestatus	=> $form->{writestatus},
		displaystatus	=> $form->{displaystatus},
		commentstatus	=> $form->{commentstatus}
	}, 'sid=' . $self->{_dbh}->quote($form->{sid}));

	$self->sqlUpdate('story_text', {
		bodytext	=> $form->{bodytext},
		introtext	=> $form->{introtext},
		relatedtext	=> $form->{relatedtext},
	}, 'sid=' . $self->{_dbh}->quote($form->{sid}));

	$self->sqlDo('UPDATE stories SET time=now() WHERE sid='
		. $self->{_dbh}->quote($form->{sid})
	) if $form->{fastforward} eq 'on';
	$self->_saveExtras($form);
}

########################################################
# Now, the idea is to not cache here, since we actually
# cache elsewhere (namely in %Slash::Apache::constants)
sub getSlashConf {
	my($self) = @_;
	# get all the data, yo
	my %conf = map { $_->[0], $_->[1] }
		@{ $self->sqlSelectAll('name, value', 'vars') };

	# the rest of this function is where is where we fix up
	# any bad or missing data in the vars table
	$conf{rootdir}		||= "//$conf{basedomain}";
	$conf{absolutedir}	||= "http://$conf{basedomain}";
	$conf{basedir}		||= $conf{datadir} . "/public_html";
	$conf{imagedir}		||= "$conf{rootdir}/images";
	$conf{rdfimg}		||= "$conf{imagedir}/topics/topicslash.gif";
	$conf{cookiepath}	||= URI->new($conf{rootdir})->path . '/';
	$conf{maxkarma}		= 999  unless defined $conf{maxkarma};
	$conf{minkarma}		= -999 unless defined $conf{minkarma};
	$conf{expiry_exponent}	= 1 unless defined $conf{expiry_exponent};
	# For all fields that it is safe to default to -1 if their
	# values are not present...
	for (qw[min_expiry_days max_expiry_days min_expiry_comm max_expiry_comm]) {
		$conf{$_}	= -1 unless exists $conf{$_};
	}

	# no trailing newlines on directory variables
	# possibly should rethink this for basedir,
	# since some OSes don't use /, and if we use File::Spec
	# everywhere this won't matter, but still should be do
	# it for the others, since they are URL paths
	# -- pudge
	for (qw[rootdir absolutedir imagedir basedir]) {
		$conf{$_} =~ s|/+$||;
	}

	$conf{m2_mincheck} = defined($conf{m2_mincheck})
				? $conf{m2_mincheck}
				: int $conf{m2_comments} / 3;

	if (!$conf{m2_maxbonus} || $conf{m2_maxbonus} > $conf{maxkarma}) {
		# this was changed on slashdot in 6/2001
		# $conf{m2_maxbonus} = int $conf{goodkarma} / 2;
		$conf{m2_maxbonus} = 1; 
	}

	my $fixup = sub {
		return [
			map {(
				s/^\s+//,
				s/\s+$//,
				$_
			)[-1]}
			split /\|/, $_[0]
		] if $_[0];
	};

	$conf{fixhrefs} = [];  # fix later
	$conf{stats_reports} = $fixup->($conf{stats_reports}) ||
		[$conf{adminmail}];

	$conf{submit_categories} = $fixup->($conf{submit_categories}) ||
		[];

	$conf{approvedtags} = $fixup->($conf{approvedtags}) ||
		[qw(B I P A LI OL UL EM BR TT STRONG BLOCKQUOTE DIV)];

	$conf{lonetags} = $fixup->($conf{lonetags}) ||
		[];

	$conf{reasons} = $fixup->($conf{reasons}) ||
		[
			'Normal',	# "Normal"
			'Offtopic',	# Bad Responses
			'Flamebait',
			'Troll',
			'Redundant',
			'Insightful',	# Good Responses
			'Interesting',
			'Informative',
			'Funny',
			'Overrated',	# The last 2 are "Special"
			'Underrated'
		];

	$conf{badreasons} = 4 unless defined $conf{badreasons};

	return \%conf;
}

##################################################################
sub autoUrl {
	my $self = shift;
	my $section = shift;
	local $_ = join ' ', @_;
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	s/([0-9a-z])\?([0-9a-z])/$1'$2/gi if $form->{fixquotes};
	s/\[(.*?)\]/linkNode($1)/ge if $form->{autonode};

	my $initials = substr $user->{nickname}, 0, 1;
	my $more = substr $user->{nickname}, 1;
	$more =~ s/[a-z]//g;
	$initials = uc($initials . $more);
	my($now) = timeCalc('epoch ' . time(), '%m/%d %H:%M %p %Z', 0);

	# Assorted Automatic Autoreplacements for Convenience
	s|<disclaimer:(.*)>|<B><A HREF="/about.shtml#disclaimer">disclaimer</A>:<A HREF="$user->{homepage}">$user->{nickname}</A> owns shares in $1</B>|ig;
	s|<update>|<B>Update: <date></B> by <author>|ig;
	s|<date>|$now|g;
	s|<author>|<B><A HREF="$user->{homepage}">$initials</A></B>:|ig;
	s/\[%(.*?)%\]/$self->getUrlFromTitle($1)/exg;

	# Assorted ways to add files:
	s|<import>|importText()|ex;
	s/<image(.*?)>/importImage($section)/ex;
	s/<attach(.*?)>/importFile($section)/ex;
	return $_;
}

##################################################################
# autoUrl & Helper Functions
# Image Importing, Size checking, File Importing etc
sub getUrlFromTitle {
	my($self, $title) = @_;
	my($sid) = $self->sqlSelect('sid', 'stories',
		qq[title like "\%$title%"],
		'order by time desc LIMIT 1'
	);
	my $rootdir = getCurrentStatic('rootdir');
	return "$rootdir/article.pl?sid=$sid";
}

##################################################################
# Should this really be in here?
# this should probably return time() or something ... -- pudge
# Well, the only problem with that is that we would then
# be trusting all machines to be timed to the database box.
# How safe is that? And I like our sysadmins :) -Brian
sub getTime {
	my($self) = @_;
	my($now) = $self->sqlSelect('now()');

	return $now;
}

##################################################################
# Should this really be in here? -- krow
# dunno ... sigh, i am still not sure this is best
# (see getStories()) -- pudge
# As of now, getDay is only used in Slash.pm getOlderStories() -- jamie
sub getDay {
#	my($self) = @_;
#	my($now) = $self->sqlSelect('to_days(now())');
	my $yesterday = timeCalc('epoch ' . time, '%Q');
	return $yesterday;
}

##################################################################
sub getStoryList {
	my($self) = @_;

	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my $table = getCurrentStatic('mysql_heap_table') ? 'story_heap' : 'stories';
	# CHANGE DATE_ FUNCTIONS
	my $sql = qq[SELECT hits, commentcount, sid, title, uid, time, name, section,
			displaystatus,writestatus
			FROM $table,topics
			WHERE $table.tid=topics.tid];
	$sql .= "	AND section='$user->{section}'" if $user->{section};
	$sql .= "	AND section='$form->{section}'" if $form->{section} && !$user->{section};
	$sql .= "	AND time < DATE_ADD(now(), interval 72 hour) " if $form->{section} eq "";
	$sql .= "	ORDER BY time DESC";

	my $cursor = $self->{_dbh}->prepare($sql);
	$cursor->execute;
	my $list = $cursor->fetchall_arrayref;

	return $list;
}

##################################################################
sub getPollVotesMax {
	my($self, $id) = @_;
	my($answer) = $self->sqlSelect("max(votes)", "pollanswers", "qid=$id");
	return $answer;
}

##################################################################
# Probably should make this private at some point
sub _saveExtras {
	my($self, $form) = @_;
	return unless $self->sqlTableExists($form->{section});
	my $extras = $self->sqlSelectColumns($form->{section});
	my $E;

	for (@$extras) { $E->{$_} = $form->{$_} }

	if ($self->sqlUpdate($form->{section}, $E, "sid='$form->{sid}'") eq '0E0') {
		$self->sqlInsert($form->{section}, $E);
	}
}

########################################################
# We make use of story_heap if it exists, it will be much
# faster than stories.
sub getStory {
	my($self, $id, $val, $cache_flag) = @_;
	# Lets see if we can use story_heap
	my $table = getCurrentStatic('mysql_heap_table') ? 'story_heap' : 'stories';
	# We need to expire stories
	_genericCacheRefresh($self, $table, getCurrentStatic('story_expire'));
	my $table_cache = '_' . $table . '_cache';
	my $table_cache_time= '_' . $table . '_cache_time';

	my $type;
	if (ref($val) eq 'ARRAY') {
		$type = 0;
	} else {
		$type  = $val ? 1 : 0;
	}

	if ($type) {
		return $self->{$table_cache}{$id}{$val}
			if (keys %{$self->{$table_cache}{$id}} and !$cache_flag);
	} else {
		if (keys %{$self->{$table_cache}{$id}} && !$cache_flag) {
			my %return = %{$self->{$table_cache}{$id}};
			return \%return;
		}
	}
# At this point its not in the cache so we go grab
# the entity.
# BTW, we avoid the join here. Sure, its two calls to
# the db but why do a join if it is not needed?
	my($append, $answer, $db_id);
	$db_id = $self->sqlQuote($id);
	$answer = $self->sqlSelectHashref('*', $table, "sid=$db_id");
	$append = $self->sqlSelectHashref('*', 'story_text', "sid=$db_id");
	for (keys %$append) {
		$answer->{$_} = $append->{$_};
	}
	$append = $self->sqlSelectAll('name,value', 'story_param', "sid=$db_id");
	for (@$append) {
		$answer->{$_->[0]} = $_->[1];
	}

# We save the entity
	$self->{$table_cache}{$id} = $answer;
	$self->{$table_cache_time} = time();

	if ($type) {
		return $self->{$table_cache}{$id}{$val};
	} else {
		if ($self->{$table_cache}{$id}) {
			my %return = %{$self->{$table_cache}{$id}};
			return \%return;
		} else {
			return;
		}
	}
}

########################################################
# Why would you ever want to call this? If you only
# wanted the meta data, didn't want to worry
# about cache. -Brian
sub getNewStory {
	my $table = getCurrentStatic('mysql_heap_table') ? 'story_heap' : 'stories';
	my $answer = _genericGet($table, 'sid', '', @_);
	return $answer;
}

########################################################
sub getAuthor {
	my($self, $id, $values, $cache_flag) = @_;
	my $table = 'authors';
	my $table_cache = '_' . $table . '_cache';
	my $table_cache_time= '_' . $table . '_cache_time';

	my $type;
	if (ref($values) eq 'ARRAY') {
		$type = 0;
	} else {
		$type  = $values ? 1 : 0;
	}

	if ($type) {
		return $self->{$table_cache}{$id}{$values}
			if (keys %{$self->{$table_cache}{$id}} and !$cache_flag);
	} else {
		if (keys %{$self->{$table_cache}{$id}} && !$cache_flag) {
			my %return = %{$self->{$table_cache}{$id}};
			return \%return;
		}
	}

	# Lets go knock on the door of the database
	# and grab the data's since it is not cached
	# On a side note, I hate grabbing "*" from a database
	# -Brian
	$self->{$table_cache}{$id} = {};
	my $answer = $self->sqlSelectHashref('users.uid as uid,nickname,fakeemail,homepage,bio',
		'users,users_info', 'users.uid=' . $self->{_dbh}->quote($id) . ' AND users.uid = users_info.uid');
	$self->{$table_cache}{$id} = $answer;

	$self->{$table_cache_time} = time();

	if ($type) {
		return $self->{$table_cache}{$id}{$values};
	} else {
		if ($self->{$table_cache}{$id}) {
			my %return = %{$self->{$table_cache}{$id}};
			return \%return;
		} else {
			return;
		}
	}
}

########################################################
# This of course is modified from the norm
sub getAuthors {
	my($self, $cache_flag) = @_;

	my $table = 'authors';
	my $table_cache= '_' . $table . '_cache';
	my $table_cache_time= '_' . $table . '_cache_time';
	my $table_cache_full= '_' . $table . '_cache_full';

	if (keys %{$self->{$table_cache}} && $self->{$table_cache_full} && !$cache_flag) {
		my %return = %{$self->{$table_cache}};
		return \%return;
	}

	$self->{$table_cache} = {};
	my $sth = $self->sqlSelectMany('users.uid,nickname,fakeemail,homepage,bio',
		'users,users_info,users_param',
		'users_param.name="author" and users_param.value=1 and ' .
		'users.uid = users_param.uid and users.uid = users_info.uid');
	while (my $row = $sth->fetchrow_hashref) {
		$self->{$table_cache}{ $row->{'uid'} } = $row;
	}

	$self->{$table_cache_full} = 1;
	$sth->finish;
	$self->{$table_cache_time} = time();

	my %return = %{$self->{$table_cache}};
	return \%return;
}

########################################################
# copy of getAuthors, for admins ... needed for anything?
sub getAdmins {
	my($self, $cache_flag) = @_;

	my $table = 'admins';
	my $table_cache= '_' . $table . '_cache';
	my $table_cache_time= '_' . $table . '_cache_time';
	my $table_cache_full= '_' . $table . '_cache_full';

	if (keys %{$self->{$table_cache}} && $self->{$table_cache_full} && !$cache_flag) {
		my %return = %{$self->{$table_cache}};
		return \%return;
	}

	$self->{$table_cache} = {};
	my $sth = $self->sqlSelectMany('users.uid,nickname,fakeemail,homepage,bio',
		'users,users_info', 'seclev >= 100 and users.uid = users_info.uid');
	while (my $row = $sth->fetchrow_hashref) {
		$self->{$table_cache}{ $row->{'uid'} } = $row;
	}

	$self->{$table_cache_full} = 1;
	$sth->finish;
	$self->{$table_cache_time} = time();

	my %return = %{$self->{$table_cache}};
	return \%return;
}

########################################################
sub getPollQuestion {
	my $answer = _genericGet('pollquestions', 'qid', '', @_);
	return $answer;
}

########################################################
sub getDiscussion {
	my $answer = _genericGet('discussions', 'id', '', @_);
	return $answer;
}

########################################################
sub getDiscussionBySid {
	my $answer = _genericGet('discussions', 'sid', '', @_);
	return $answer;
}

########################################################
sub getBlock {
	my($self) = @_;
	_genericCacheRefresh($self, 'blocks', getCurrentStatic('block_expire'));
	my $answer = _genericGetCache('blocks', 'bid', '', @_);
	return $answer;
}

########################################################
sub _getTemplateNameCache {
	my($self) = @_;
	my %cache;
	my $templates = $self->sqlSelectAll('tpid,name,page,section', 'templates');
	for (@$templates) {
		$cache{$_->[1], $_->[2], $_->[3]} = $_->[0];
	}
	return \%cache;
}

########################################################
sub getTemplate {
	my($self) = @_;
	_genericCacheRefresh($self, 'templates', getCurrentStatic('block_expire'));
	my $answer = _genericGetCache('templates', 'tpid', '', @_);
	return $answer;
}

########################################################
# This is a bit different
sub getTemplateByName {
	my($self, $name, $values, $cache_flag, $page, $section) = @_;
	return if ref $name;	# no scalar refs, only text names
	my $constants = getCurrentStatic();
	_genericCacheRefresh($self, 'templates', $constants->{'block_expire'});

	my $table_cache = '_templates_cache';
	my $table_cache_time= '_templates_cache_time';
	my $table_cache_id= '_templates_cache_id';

	#First, we get the cache
	$self->{$table_cache_id} =
		$constants->{'cache_enabled'} && $self->{$table_cache_id}
		? $self->{$table_cache_id} : _getTemplateNameCache($self);

	#Now, lets determine what we are after
	unless ($page) {
		$page = getCurrentUser('currentPage');
		$page ||= 'misc';
	}
	unless ($section) {
		$section = getCurrentUser('currentSection');
		$section ||= 'default';
	}

	#Now, lets figure out the id
	#name|page|section => name|page|default => name|misc|section => name|misc|default
	# That frat boy march with a paddle
	my $id = $self->{$table_cache_id}{$name, $page,  $section };
	$id  ||= $self->{$table_cache_id}{$name, $page,  'default'};
	$id  ||= $self->{$table_cache_id}{$name, 'misc', $section };
	$id  ||= $self->{$table_cache_id}{$name, 'misc', 'default'};
	return unless $id;

	my $type;
	if (ref($values) eq 'ARRAY') {
		$type = 0;
	} else {
		$type  = $values ? 1 : 0;
	}

	if (!$cache_flag && exists $self->{$table_cache}{$id} && keys %{$self->{$table_cache}{$id}}) {
		if ($type) {
			return $self->{$table_cache}{$id}{$values};
		} else {
			my %return = %{$self->{$table_cache}{$id}};
			return \%return;
		}
	}

	$self->{$table_cache}{$id} = {};
	my $answer = $self->sqlSelectHashref('*', "templates", "tpid=$id");
	$answer->{'_modtime'} = time();
	$self->{$table_cache}{$id} = $answer;

	$self->{$table_cache_time} = time();

	if ($type) {
		return $self->{$table_cache}{$id}{$values};
	} else {
		if ($self->{$table_cache}{$id}) {
			my %return = %{$self->{$table_cache}{$id}};
			return \%return;
		}
	}

	return $answer;
}

########################################################
sub getTopic {
	my $answer = _genericGetCache('topics', 'tid', '', @_);
	return $answer;
}

########################################################
sub getTopics {
	my $answer = _genericGetsCache('topics', 'tid', '', @_);
	return $answer;
}

########################################################
sub getTemplates {
	my $answer = _genericGetsCache('templates', 'tpid', '', @_);
	return $answer;
}

########################################################
sub getContentFilter {
	my $answer = _genericGet('content_filters', 'filter_id', '', @_);
	return $answer;
}

########################################################
sub getSubmission {
	my $answer = _genericGet('submissions', 'subid', '', @_);
	return $answer;
}

########################################################
sub getSection {
	my($self, $section) = @_;
	if (!$section) {
		my $constants = getCurrentStatic();
		my $user      = getCurrentUser();
		return {
			title    => "$constants->{sitename}: $constants->{slogan}",
			artcount => getCurrentUser('maxstories') || 30,
			issue    => 3
		};
	}

	my $answer = _genericGetCache('sections', 'section', '', @_);
	return $answer;
}

########################################################
sub getSections {
	my $answer = _genericGetsCache('sections', 'section', '', @_);
	return $answer;
}

########################################################
sub getModeratorLog {
	my $answer = _genericGet('moderatorlog', 'id', '', @_);
	return $answer;
}

########################################################
sub getVar {
	my $answer = _genericGet('vars', 'name', '', @_);
	return $answer;
}

########################################################
sub setUser {
	my($self, $uid, $hashref) = @_;
	my(@param, %update_tables, $cache);
	my $tables = [qw(
		users users_comments users_index
		users_info users_prefs
	)];

	# special cases for password, exboxes
	if (exists $hashref->{passwd}) {
		# get rid of newpasswd if defined in DB
		$hashref->{newpasswd} = '';
		$hashref->{passwd} = encryptPassword($hashref->{passwd});
	}

	# hm, come back to exboxes later; it works for now
	# as is, since external scripts handle it -- pudge
	# a VARARRAY would make a lot more sense for this, no need to
	# pack either -Brian
	if (0 && exists $hashref->{exboxes}) {
		if (ref $hashref->{exboxes} eq 'ARRAY') {
			$hashref->{exboxes} = sprintf("'%s'", join "','", @{$hashref->{exboxes}});
		} elsif (ref $hashref->{exboxes}) {
			$hashref->{exboxes} = '';
		} # if nonref scalar, just let it pass
	}

	$cache = _genericGetCacheName($self, $tables);

	for (keys %$hashref) {
		(my $clean_val = $_) =~ s/^-//;
		my $key = $self->{$cache}{$clean_val};
		if ($key) {
			push @{$update_tables{$key}}, $_;
		} else {
			push @param, [$_, $hashref->{$_}];
		}
	}

	for my $table (keys %update_tables) {
		my %minihash;
		for my $key (@{$update_tables{$table}}){
			$minihash{$key} = $hashref->{$key}
				if defined $hashref->{$key};
		}
		$self->sqlUpdate($table, \%minihash, 'uid=' . $uid, 1);
	}
	# What is worse, a select+update or a replace?
	# I should look into that.
	for (@param)  {
		if ($_->[0] eq "acl") {
			$self->sqlReplace('users_acl', { uid => $uid, name => $_->[1]->{name}, value => $_->[1]->{value}});
		} else {
			$self->sqlReplace('users_param', { uid => $uid, name => $_->[0], value => $_->[1]})
	 			if defined $_->[1];
		}
	}
}

########################################################
# Now here is the thing. We want getUser to look like
# a generic, despite the fact that it is not :)
sub getUser {
	my($self, $id, $val) = @_;
	my $answer;
	my $tables = [qw(
		users users_comments users_index
		users_info users_prefs
	)];
	# The sort makes sure that someone will always get the cache if
	# they have the same tables
	my $cache = _genericGetCacheName($self, $tables);

	if (ref($val) eq 'ARRAY') {
		my($values, %tables, @param, $where, $table);
		for (@$val) {
			(my $clean_val = $_) =~ s/^-//;
			if ($self->{$cache}{$clean_val}) {
				$tables{$self->{$cache}{$_}} = 1;
				$values .= "$_,";
			} else {
				push @param, $_;
			}
		}
		chop($values);

		for (keys %tables) {
			$where .= "$_.uid=$id AND ";
		}
		$where =~ s/ AND $//;

		$table = join ',', keys %tables;
		$answer = $self->sqlSelectHashref($values, $table, $where) if $values;
		for (@param) {
			if ($_ eq 'is_anon') {
				$answer->{is_anon} = isAnon($id);
			} else {
				# First we try it as an acl param -acs
				my $val = $self->sqlSelect('value', 'users_acl', "uid=$id AND name='$_'");
				$val = $self->sqlSelect('value', 'users_param', "uid=$id AND name='$_'") if !$val;
				$answer->{$_} = $val;
			}
		}

	} elsif ($val) {
		(my $clean_val = $val) =~ s/^-//;
		my $table = $self->{$cache}{$clean_val};
		if ($table) {
			$answer = $self->sqlSelect($val, $table, "uid=$id");
		} else {
			# First we try it as an acl param -acs
			$answer = $self->sqlSelect('value', 'users_acl', "uid=$id AND name='$val'");
			$answer = $self->sqlSelect('value', 'users_param', "uid=$id AND name='$val'") if !$answer;
		}

	} else {
		my($where, $table, $append_acl, $append);
		for (@$tables) {
			$where .= "$_.uid=$id AND ";
		}
		$where =~ s/ AND $//;

		$table = join ',', @$tables;
		$answer = $self->sqlSelectHashref('*', $table, $where);
		$append_acl = $self->sqlSelectAll('name,value', 'users_acl', "uid=$id");
		for (@$append_acl) {
			$answer->{$_->[0]} = $_->[1];
		}
		$append = $self->sqlSelectAll('name,value', 'users_param', "uid=$id");
		for (@$append) {
			$answer->{$_->[0]} = $_->[1];
		}
		$answer->{is_anon} = isAnon($id);
	}

	return $answer;
}

########################################################
# This could be optimized by not making multiple calls
# to getKeys or by fixing getKeys() to return multiple
# values
sub _genericGetCacheName {
	my($self, $tables) = @_;
	my $cache;

	if (ref($tables) eq 'ARRAY') {
		$cache = '_' . join ('_', sort(@$tables), 'cache_tables_keys');
		unless (keys %{$self->{$cache}}) {
			for my $table (@$tables) {
				my $keys = $self->getKeys($table);
				for (@$keys) {
					$self->{$cache}{$_} = $table;
				}
			}
		}
	} else {
		$cache = '_' . $tables . 'cache_tables_keys';
		unless (keys %{$self->{$cache}}) {
			my $keys = $self->getKeys($tables);
			for (@$keys) {
				$self->{$cache}{$_} = $tables;
			}
		}
	}
	return $cache;
}

########################################################
# Now here is the thing. We want setUser to look like
# a generic, despite the fact that it is not :)
# We assum most people called set to hit the database
# and just not the cache (if one even exists)
sub _genericSet {
	my($table, $table_prime, $param_table, $self, $id, $value) = @_;

	if ($param_table) {
		my $cache = _genericGetCacheName($self, $table);

		my(@param, %updates);
		for (keys %$value) {
			(my $clean_val = $_) =~ s/^-//;
			my $key = $self->{$cache}{$clean_val};
			if ($key) {
				$updates{$_} = $value->{$_};
			} else {
				push @param, [$_, $value->{$_}];
			}
		}
		$self->sqlUpdate($table, \%updates, $table_prime . '=' . $self->{_dbh}->quote($id))
			if keys %updates;
		# What is worse, a select+update or a replace?
		# I should look into that. if EXISTS() the
		# need for a fully sql92 database.
		# transactions baby, transactions... -Brian
		for (@param)  {
			$self->sqlReplace($param_table, { $table_prime => $id, name => $_->[0], value => $_->[1]});
		}
	} else {
		$self->sqlUpdate($table, $value, $table_prime . '=' . $self->{_dbh}->quote($id));
	}

	my $table_cache= '_' . $table . '_cache';
	return unless keys %{$self->{$table_cache}};

	my $table_cache_time= '_' . $table . '_cache_time';
	$self->{$table_cache_time} = time();
	for (keys %$value) {
		$self->{$table_cache}{$id}{$_} = $value->{$_};
	}
	$self->{$table_cache}{$id}{'_modtime'} = time();
}

########################################################
# You can use this to reset cache's in a timely
# manner :)
sub _genericCacheRefresh {
	my($self, $table,  $expiration) = @_;
	return unless $expiration;
	my $table_cache = '_' . $table . '_cache';
	my $table_cache_time = '_' . $table . '_cache_time';
	my $table_cache_full = '_' . $table . '_cache_full';
	return unless $self->{$table_cache_time};
	my $time = time();
	my $diff = $time - $self->{$table_cache_time};

	if ($diff > $expiration) {
		# print STDERR "TIME:$diff:$expiration:$time:$self->{$table_cache_time}:\n";
		$self->{$table_cache} = {};
		$self->{$table_cache_time} = 0;
		$self->{$table_cache_full} = 0;
	}
}

########################################################
# This is protected and don't call it from your
# scripts directly.
sub _genericGetCache {
	return _genericGet(@_) unless getCurrentStatic('cache_enabled');

	my($table, $table_prime, $param_table,  $self, $id, $values, $cache_flag) = @_;
	my $table_cache = '_' . $table . '_cache';
	my $table_cache_time= '_' . $table . '_cache_time';

	my $type;
	if (ref($values) eq 'ARRAY') {
		$type = 0;
	} else {
		$type  = $values ? 1 : 0;
	}

	if ($type) {
		return $self->{$table_cache}{$id}{$values}
			if (keys %{$self->{$table_cache}{$id}} and !$cache_flag);
	} else {
		if (keys %{$self->{$table_cache}{$id}} && !$cache_flag) {
			my %return = %{$self->{$table_cache}{$id}};
			return \%return;
		}
	}

	$self->{$table_cache}{$id} = {};
	my $answer = $self->sqlSelectHashref('*', $table, "$table_prime=" . $self->{_dbh}->quote($id));
	$answer->{'_modtime'} = time();
	if ($param_table) {
		my $append = $self->sqlSelectAll('name,value', $param_table, "$table_prime=" . $self->{_dbh}->quote($id));
		for (@$append) {
			$answer->{$_->[0]} = $_->[1];
		}
	}
	$self->{$table_cache}{$id} = $answer;

	$self->{$table_cache_time} = time();

	if ($type) {
		return $self->{$table_cache}{$id}{$values};
	} else {
		if ($self->{$table_cache}{$id}) {
			my %return = %{$self->{$table_cache}{$id}};
			return \%return;
		} else {
			return;
		}
	}
}

########################################################
# This is protected and don't call it from your
# scripts directly.
sub _genericClearCache {
	my($table, $self) = @_;
	my $table_cache= '_' . $table . '_cache';

	$self->{$table_cache} = {};
}

########################################################
# This is protected and don't call it from your
# scripts directly.
sub _genericGet {
	my($table, $table_prime, $param_table, $self, $id, $val) = @_;
	my($answer, $type);
	my $id_db = $self->{_dbh}->quote($id);

	if ($param_table) {
	# With Param table
		if (ref($val) eq 'ARRAY') {
			my $cache = _genericGetCacheName($self, $table);

			my($values, @param);
			for (@$val) {
				(my $clean_val = $_) =~ s/^-//;
				if ($self->{$cache}{$clean_val}) {
					$values .= "$_,";
				} else {
					push @param, $_;
				}
			}
			chop($values);

			$answer = $self->sqlSelectHashref($values, $table, "$table_prime=$id_db");
			for (@param) {
				my $val = $self->sqlSelect('value', $param_table, "$table_prime=$id_db AND name='$_'");
				$answer->{$_} = $val;
			}

		} elsif ($val) {
			my $cache = _genericGetCacheName($self, $table);
			(my $clean_val = $val) =~ s/^-//;
			my $table = $self->{$cache}{$clean_val};
			if ($table) {
				($answer) = $self->sqlSelect($val, $table, "uid=$id");
			} else {
				($answer) = $self->sqlSelect('value', $param_table, "$table_prime=$id_db AND name='$val'");
			}

		} else {
			$answer = $self->sqlSelectHashref('*', $table, "$table_prime=$id_db");
			my $append = $self->sqlSelectAll('name,value', $param_table, "$table_prime=$id_db");
			for (@$append) {
				$answer->{$_->[0]} = $_->[1];
			}
		}
	} else {
	# Without Param table
		if (ref($val) eq 'ARRAY') {
			my $values = join ',', @$val;
			$answer = $self->sqlSelectHashref($values, $table, "$table_prime=$id_db");
		} elsif ($val) {
			($answer) = $self->sqlSelect($val, $table, "$table_prime=$id_db");
		} else {
			$answer = $self->sqlSelectHashref('*', $table, "$table_prime=$id_db");
		}
	}


	return $answer;
}

########################################################
# This is protected and don't call it from your
# scripts directly.
sub _genericGetsCache {
	return _genericGets(@_) unless getCurrentStatic('cache_enabled');

	my($table, $table_prime, $param_Table, $self, $cache_flag) = @_;
	my $table_cache= '_' . $table . '_cache';
	my $table_cache_time= '_' . $table . '_cache_time';
	my $table_cache_full= '_' . $table . '_cache_full';

	if (keys %{$self->{$table_cache}} && $self->{$table_cache_full} && !$cache_flag) {
		my %return = %{$self->{$table_cache}};
		return \%return;
	}

	# Lets go knock on the door of the database
	# and grab the data since it is not cached
	# On a side note, I hate grabbing "*" from a database
	# -Brian
	$self->{$table_cache} = {};
#	my $sth = $self->sqlSelectMany('*', $table);
#	while (my $row = $sth->fetchrow_hashref) {
#		$row->{'_modtime'} = time();
#		$self->{$table_cache}{ $row->{$table_prime} } = $row;
#	}
#	$sth->finish;
	$self->{$table_cache} = _genericGets(@_);
	$self->{$table_cache_full} = 1;
	$self->{$table_cache_time} = time();

	my %return = %{$self->{$table_cache}};
	return \%return;
}

########################################################
# This is protected and don't call it from your
# scripts directly.
sub _genericGets {
	my($table, $table_prime, $param_table, $self, $values) = @_;
	my(%return, $sth, $params);

	if (ref($values) eq 'ARRAY') {
		my $get_values;

		if ($param_table) {
			my $cache = _genericGetCacheName($self, $table);
			for (@$values) {
				(my $clean_val = $values) =~ s/^-//;
				if ($self->{$cache}{$clean_val}) {
					push @$get_values, $_;
				} else {
					my $val = $self->sqlSelectAll('$table_prime, name, value', $param_table, "name='$_'");
					for my $row (@$val) {
						push @$params, $row;
					}
				}
			}
		} else {
			$get_values = $values;
		}
		my $val = join ',', @$get_values;
		$val .= ",$table_prime" unless grep $table_prime, @$get_values;
		$sth = $self->sqlSelectMany($val, $table);
	} elsif ($values) {
		if ($param_table) {
			my $cache = _genericGetCacheName($self, $table);
			(my $clean_val = $values) =~ s/^-//;
			my $use_table = $self->{$cache}{$clean_val};

			if ($use_table) {
				$values .= ",$table_prime" unless $values eq $table_prime;
				$sth = $self->sqlSelectMany($values, $table);
			} else {
				my $val = $self->sqlSelectAll("$table_prime, name, value", $param_table, "name=$values");
				for my $row (@$val) {
					push @$params, $row;
				}
			}
		} else {
			$values .= ",$table_prime" unless $values eq $table_prime;
			$sth = $self->sqlSelectMany($values, $table);
		}
	} else {
		$sth = $self->sqlSelectMany('*', $table);
		if ($param_table) {
			$params = $self->sqlSelectAll("$table_prime, name, value", $param_table);
		}
	}

	if ($sth) {
		while (my $row = $sth->fetchrow_hashref) {
			$return{ $row->{$table_prime} } = $row;
		}
		$sth->finish;
	}

	if ($params) {
		for (@$params) {
			# this is not right ... perhaps the other is? -- pudge
#			${return->{$_->[0]}->{$_->[1]}} = $_->[2]
			$return{$_->[0]}{$_->[1]} = $_->[2]
		}
	}

	return \%return;
}

########################################################
sub getStories {
	my $answer = _genericGets('stories', 'sid', 'story_param', @_);
	return $answer;
}

########################################################
# single big select for ForumZilla ... if someone wants to
# improve on this, please go ahead
sub fzGetStories {
	my($self, $section) = @_;
	my $slashdb = getCurrentDB();
	my $section_dbi = $self->sqlQuote($section || '');

	my($comments, $stories);
	if (getCurrentStatic('mysql_heap_table')) {
		$comments = "comment_heap";
		$stories  = "story_heap";
	} else {
		$comments = "comments";
		$stories  = "stories";
	}

	my $data = $slashdb->sqlSelectAllHashrefArray(<<S, <<F, <<W, <<E);
$stories.sid, $stories.title, time, commentcount,
MAX($comments.date) AS lastcommentdate
S
discussions LEFT OUTER JOIN $comments ON discussions.id = $comments.sid, $stories
F
$stories.sid = discussions.sid
AND ((displaystatus = 0 and $section_dbi="")
OR ($stories.section=$section_dbi and displaystatus > -1))
AND time < now() AND writestatus > -1
W
GROUP BY $stories.sid
ORDER BY time DESC
LIMIT 10
E
	# note that LIMIT could be a var -- pudge
	return $data;
}


########################################################
sub getSessions {
	my $answer = _genericGets('sessions', 'session', '', @_);
	return $answer;
}

########################################################
sub createBlock {
	my($self, $hash) = @_;
	$self->sqlInsert('blocks', $hash);
}

########################################################
sub createTemplate {
	my($self, $hash) = @_;
	for (qw| page name section |) {
		next unless $hash->{$_};
		if ($hash->{$_} =~ /;/) {
			errorLog("A semicolon was found in the $_ while trying to create a template");
			return;
		}
	}
	$self->sqlInsert('templates', $hash);
	my $tpid  = $self->getLastInsertId('templates', 'tpid');
	return $tpid;
}

########################################################
sub createMenuItem {
	my($self, $hash) = @_;
	$self->sqlInsert('menus', $hash);
}

########################################################
sub getMenuItems {
	my($self, $script) = @_;
	my $sql = "SELECT * FROM menus WHERE page=" . $self->{_dbh}->quote($script) . "ORDER by menuorder";
	my $sth = $self->{_dbh}->prepare($sql);
	$sth->execute();
	my(@menu, $row);
	push(@menu, $row) while ($row = $sth->fetchrow_hashref);
	$sth->finish;

	return \@menu;
}

########################################################
sub getMenus {
	my($self) = @_;

	my $sql = "SELECT DISTINCT menu FROM menus ORDER BY menu";
	my $sth = $self->{_dbh}->prepare($sql);
	$sth->execute;
	my $menu_names = $sth->fetchall_arrayref;
	$sth->finish;

	my $menus;
	for (@$menu_names) {
		my $script = $_->[0];
		$sql = "SELECT * FROM menus WHERE menu=" . $self->{_dbh}->quote($script) . "ORDER by menuorder";
		$sth =	$self->{_dbh}->prepare($sql);
		$sth->execute();
		my(@menu, $row);
		push(@menu, $row) while ($row = $sth->fetchrow_hashref);
		$sth->finish;
		$menus->{$script} = \@menu;
	}

	return $menus;
}

########################################################
sub sqlReplace {
	my($self, $table, $data) = @_;
	my($names, $values);

	foreach (keys %$data) {
		if (/^-/) {
			$values .= "\n  $data->{$_},";
			s/^-//;
		} else {
			$values .= "\n  " . $self->{_dbh}->quote($data->{$_}) . ',';
		}
		$names .= "$_,";
	}

	chop($names);
	chop($values);

	my $sql = "REPLACE INTO $table ($names) VALUES($values)\n";
	$self->sqlConnect();
	return $self->sqlDo($sql) or errorLog($sql);
}

##################################################################
# This should be rewritten so that at no point do we
# pass along an array -Brian
sub getKeys {
	my($self, $table) = @_;
	my $keys = $self->sqlSelectColumns($table)
		if $self->sqlTableExists($table);

	return $keys;
}

########################################################
sub sqlTableExists {
	my($self, $table) = @_;
	return unless $table;

	$self->sqlConnect();
	my $tab = $self->{_dbh}->selectrow_array(qq!SHOW TABLES LIKE "$table"!);
	return $tab;
}

########################################################
sub sqlSelectColumns {
	my($self, $table) = @_;
	return unless $table;

	$self->sqlConnect();
	my $rows = $self->{_dbh}->selectcol_arrayref("SHOW COLUMNS FROM $table");
	return $rows;
}

########################################################
sub getRandomSpamArmor {
	my($self) = @_;

	my $ret = $self->sqlSelectAllHashref(
		'armor_id', '*', 'spamarmors', 'active=1'
	);
	my @armor_keys = keys %{$ret};

	# array index automatically int'd
	return $ret->{$armor_keys[rand($#armor_keys + 1)]};
}

########################################################
# Get a unique string for an admin session
#sub generatesession {
#	# crypt() may be implemented differently so as to
#	# make the field in the db too short ... use the same
#	# MD5 encrypt function?  is this session thing used
#	# at all anymore?
#	my $newsid = crypt(rand(99999), $_[0]);
#	$newsid =~ s/[^A-Za-z0-9]//i;
#
#	return $newsid;
#}

1;

__END__

=head1 NAME

Slash::DB::MySQL - MySQL Interface for Slash

=head1 SYNOPSIS

	use Slash::DB::MySQL;

=head1 DESCRIPTION

This is the MySQL specific stuff. To get the real
docs look at Slash::DB.

=head1 SEE ALSO

Slash(3), Slash::DB(3).

=cut

# See bottom of file for license and copyright information

=pod TML

---+ package Foswiki::Contrib::DBIStoreContrib::ResultSet

This class implements the ResultSet API - its basically a Sorted Aggregate Iterator for foswiki 1.1
   * NOTE: does not implement the unique function - by its nature, the data is unique, and it would be a non-trivial drain on memory in this context

Designed to work with DBI fetch

=cut

package Foswiki::Contrib::DBIStoreContrib::ResultSet;
use strict;
use warnings;

use Foswiki::Iterator ();
use Foswiki::Search::InfoCache;
use Foswiki::Contrib::DBIStoreContrib::TopicHandler ();



=pod TML

---++ new($topic_handler,$selectStatement)

Create a new iterator over the given list of iterators. The list is
not damaged in any way.

=cut

sub new {
    my ($class, $array_ref ) = @_;
	
	
	# rowRefGuide 
	# 1-key/topic_history_key, 2-topic_key, 3-revision, 4-timestamp_epoch, 5-web_key, 6-topic_name, 7-summary, 8-web_name, 9-user_key, 10-permissions
	my $rowHash = {topic_history_key =>1, key => 1, topic_key => 2, revision => 3, timestamp_epoch=> 4,
		web_key => 5, topic_name => 6, topic_content_summary => 7, web_name => 8, user_key => 9, deny => 10, allow => 11, author=> 9, summary => 7, topic_content_key => 12,
		topic_name_key => 13 };
	
	my $this = bless( 
	{RowNumber => scalar(@$array_ref), currentRow => undef,  currentRowNumber => -1, rowRefGuide => $rowHash, TopicMetaObject => undef, ReturnArray => $array_ref },
	$class);
	
	# add a little cache for web permissions
	# $this->{permission_cache}->{web_name} = 0 for can't view or 1 for view
	$this->{permission_cache} = undef;

    return $this;
}

# only initialize with a simple @list
sub newSimple {
	my ($class,$array_ref) = @_;
	
}


sub numberOfTopics {
    my $this = shift;
    return $this->{RowNumber};
    
}

=pod TML

---++ hasNext() -> $boolean

Iterates to the next row.  Returns false when the iterator is exhausted. 
This function also iterates to the next row if it does not have permission to view the current row.
=cut

sub hasNext {
	my $this = shift;
	my $int = $this->{currentRowNumber};
	$int += 1;
	$this->{currentRow} = $this->{ReturnArray}->[$int];
	return undef unless $this->{currentRow};
	$this->{currentRowNumber} = $int;

	# to prevent LoadTHRow from being called, load the cache from here
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();


	# TESTING whether something is screwy with the cache or not!!!!!!
	# 1-key/topic_history_key, 2-topic_key, 3-revision, 4-timestamp_epoch, 5-web_key, 6-topic_name, 7-summary, 8-web_name, 9-user_key, 10-permissions, 11-topic_content_key
	my $version = $this->currentRow('revision');
	if(!$version){
		$topic_handler->{topic_cache}->{$this->currentRow('web_name').'&'.$this->currentRow('topic_name')} = $this->currentRow('topic_key');
		$topic_handler->{topic_cache}->{$this->currentRow('topic_key').'-1'} = $this->currentRow('key');
	}

	$topic_handler->{topic_cache}->{$this->currentRow('topic_key').$this->currentRow('revision')} = $this->currentRow('key');
	foreach my $item ('key','topic_history_key','topic_key','user_key','revision','web_key','timestamp_epoch','topic_content_key','topic_name','topic_name_key'){
		$topic_handler->{topic_cache}->{$this->currentRow('key')}->{$item} = $this->currentRow($item);
	}

	#warn "HasNext: $int\n";
    return 1;
}

# this assumes that webs.current_web_name is in the ORDER BY clause
sub nextWeb {
	my $this = shift;
	my $currentWeb = $this->currentRow('web_name');
	return undef unless $currentWeb;
	while($this->currentRow('web_name') ne $currentWeb){
		$this->hasNext();
		return undef unless $this->currentRow('web_name');
	}
	return 1;
}

=pod TML

---++ currentRow('topic_name') -> $ref to topic_history row
# 1-key/topic_history_key, 2-topic_key, 3-revision, 4-timestamp_epoch, 5-web_key, 6-topic_name, 7-summary, 8-web_name, 9-user_key, 10-permissions,12-topic_content_key
Return the next entry in the list.

=cut

sub currentRow {
		my $this = shift;
		my $fieldname = shift;
		return undef unless $fieldname;
		my $int = $this->{rowRefGuide}->{$fieldname};
		if($int){
			$int -= 1;	
			# 1-key/topic_history_key, 2-topic_key, 3-revision, 4-timestamp_epoch, 5-web_key, 6-topic_name, 7-summary, 8-web_name, 9-user_key, 10-permissions
			return $this->{currentRow}->[$int];
		}
		elsif($fieldname eq 'wikiusername'){
			# TODO: need to call something, for now, just return the user key
			return $this->currentRow('user_key');
			
		}
				
}

=pod TML

---++ checkTopicPermission() -> 0 or 1 depending on permissions

Checks to see if the user has VIEW permissions on the current row/topic

=cut

sub checkPermission {
	my ($this) = @_;
	return 1;
	# cancel if the row is null
	return undef unless $this->currentRow('web_name') && $this->currentRow('topic_name');
	
	# get the $cUID and list of groups that the user is a member of
	my $cUID = $Foswiki::Plugins::SESSION->{user};
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	require Foswiki::Contrib::DBIStoreContrib::UserHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	my $user_handler = bless $topic_handler, *Foswiki::Contrib::DBIStoreContrib::UserHandler;
	my @listOfGroups = @{$user_handler->getUserMembers($cUID)};
	
	# check the webs first (the result is 0 or 1)
	my $web_name = $this->currentRow('web_name');
	my $web_result = $this->{permission_cache}->{$web_name};
	# first, check if it is in the permission_cache
	if(!$web_result){
		require Foswiki::Meta;
		my $web_checker = new Foswiki::Meta($Foswiki::Plugins::SESSION,$web_name);
		$web_result = $web_checker->haveAccess('VIEW', $Foswiki::Plugins::SESSION->{user});
		$this->{permission_cache}->{$web_name} = $web_result;	
	}
	my ($allow,$deny) = ($this->currentRow('allow'),$this->currentRow('deny'));
	my @denyArray = split(',',$this->currentRow('deny'));
	my @allowArray = split(',',$this->currentRow('allow'));
	
	# return the web result if both deny and allow lists are emtpy
	if(!$deny && !$allow ){
		return $web_result;
	}
	
	#--------------- this part was copied directly from Meta.pm  ---------------#
	# super admin is always allowed
	my $session = $Foswiki::Plugins::SESSION;
	my $crap = $session->{users}->isInAdminGroup($cUID);

	if ( $session->{users}->isAdmin($cUID) || $session->{users}->isInAdminGroup($cUID)) {
		return 1;
	}

	my ( $element, $tfbool );
	my (@union,@intersection,@difference);
	my %count;
	# Check ALLOWTOPIC. If this is defined the user _must_ be in it
	if( defined($allow)){
		if ( scalar(@allowArray) != 0 && $allow) {
			###### check to see if allow and groups overlap #######
			@union = @intersection = @difference = ();
			%count = ();
			foreach $element (@allowArray, @listOfGroups) { $count{$element}++ }
			foreach $element (keys %count) {
				push @union, $element;
				push @{ $count{$element} > 1 ? \@intersection : \@difference }, $element;
			}
			####### list intersection stuff over  ###########
			$tfbool = 0; # 0-keep going 1-allow
			# allow is "at least 1" (must be in at least 1 group to get an allow)
			$tfbool = 1 if scalar(@intersection) >= 1 ;
			# if the user is in the allow list, then absolutely allow
			foreach $element (@allowArray) { 
				$tfbool = 1 if $element eq $cUID;
			}
			if ( $tfbool ) {
				return 1;
			}
			else{
				# if the user is not in the ALLOW, then access is denied
				return 0;
			}
		}
		# if allow is empty, it has no meaning

	}

		
	# Check DENYTOPIC (meaning no ALLOWTOPIC was defined)
	if ( defined($deny) ) {
		if ( scalar(@denyArray) != 0 && $deny) {
			###### check to see if deny and groups overlap #######
			@union = @intersection = @difference = ();
			%count = ();
			foreach $element (@denyArray, @listOfGroups) { $count{$element}++ }
			foreach $element (keys %count) {
				push @union, $element;
				push @{ $count{$element} > 1 ? \@intersection : \@difference }, $element;
			}
			####### list intersection stuff over  ###########
               $tfbool = 0; # 0-keep going 1-deny
			# deny is all or nothing (must be in all groups to get a deny)
			$tfbool = 1 if scalar(@intersection) == scalar(@listOfGroups) && scalar(@intersection) != 0;
			# if the user is in the deny list, then absolutely deny
			foreach $element (@denyArray) { 
				$tfbool = 1 if $element eq $cUID;
			}
			
			if ( $tfbool ) {
				return 0;
			}
			# else, keeping going to the web level
		}
		# if allow does not exist and deny is empty,then let everyone in!
		if($deny && !$allow) {
			return 1;
		}
	}

	# return the web result in case the topic case turns up nothing
	return $web_result;

}

=pod TML

---++ getCurrentTopicObj() -> Meta Object built from current Topic Row

Checks to see if the user has VIEW permissions.

=cut

sub getCurrentTopicObj {
	my $this = shift;
	my $session = shift;
	my $topicObject = $this->{TopicMetaObject};
	
	return undef unless defined($this->{currentRow}); 
	if( defined($topicObject) && $topicObject->web eq $this->currentRow('web_name') && $topicObject->topic eq $this->currentRow('topic_name') ) {
		return $topicObject;
	}
	# the rest assumes that the Meta object does not match the current row
	$this->{TopicMetaObject} = undef;
	$this->{TopicMetaObject} = new Foswiki::Meta($session,$this->currentRow('web_name'),$this->currentRow('topic_name')); 
	$this->{TopicMetaObject}->text($this->currentRow('topic_content_summary'));
	# set the Topic Info
	my %info;
	$info{date} = $this->currentRow('timestamp_epoch');
	$info{author} = $this->currentRow('user_key');
	$info{version} = $this->currentRow('revision');
	$this->{TopicMetaObject}->setRevisionInfo(%info);
	
	return $this->{TopicMetaObject};
}

1;
__END__

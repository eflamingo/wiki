
package Foswiki::Users::DBIUserMapping;

use strict;
use Foswiki::Contrib::DBIStoreContrib ();
use Foswiki::ListIterator ();
use Digest::MD5 qw(md5 md5_hex md5_base64);
use Foswiki::Func ();
use Foswiki::Users::TopicUserMapping;
our @ISA = qw( Foswiki::Users::TopicUserMapping );
use Foswiki::Store::DBISQL ();
use Foswiki::Contrib::DBIStoreContrib::Handler ();
use Foswiki::Contrib::DBIStoreContrib::UserHandler ();
use Foswiki::Contrib::DBIStoreContrib::GroupHandler ();
=pod 

---++++ new($session) -> $DBIUserMapping

create a new Foswiki::Users::DBIUserMapping object and constructs an <nop>DBIStoreContrib Handler
object to delegate DBI services to.

=cut

sub new {
    my ( $class, $session ) = @_;

    my $this = $class->SUPER::new( $session);

	bless $this, $class;
	$this->addSiteHandler();
	my $ref = ref($this->{site_handler});
	#die "ref: $ref\n";
	return $this;
}

sub addSiteHandler {
	my $this = shift;
	# find out what the site key is for future reference
	$this->{site_handler} = Foswiki::Contrib::DBIStoreContrib::Handler::->new() unless ($this->{site_handler});
	return $this->{site_handler};
		
}
=pod

---++++ finish()

Complete processing after the client's HTTP request has been responded
to. I.e. it disconnects the LDAP database connection.

=cut

sub finish {
  my $this = shift;
    
  $this->{site_handler}->finish() if $this->{site_handler};
  #undef $this->{site_handler};
  $this->SUPER::finish();
  return 1;
}

=pod

---++++ writeDebug($msg) 

Static method to write a debug messages. 

=cut

sub writeDebug {

}


=pod

---++++ addUser ($login, $wikiname, $password, $emails) -> $cUID

overrides and thus disables the SUPER method

=cut

sub addUser {
	my $this = shift;
	my ($login, $wikiname, $passwordU, $emails) = @_;
	my $user_handler = Foswiki::Contrib::DBIStoreContrib::UserHandler::->init($this->{site_handler});
	my ($web_name,$topic_name) = Foswiki::Func::normalizeWebTopicName($Foswiki::cfg{UsersWebName},$wikiname);

	#my $dbiobj = Foswiki::Store::DBISQL->userNew($user_handler);
	# generate random, unbreakable password incase no password is provided here
	unless($passwordU){
		$passwordU = $user_handler->generateRandomPassword();
	}
	my $site_name = $Foswiki::cfg{SiteName};
	my $passwordE = md5_hex($login.':'.$site_name.':'.$passwordU);

	##### start the transaction #####
	$user_handler->database_connection()->{AutoCommit} = 0;
	$user_handler->database_connection()->{RaiseError} = 1;
	
	my ($cUID,$AgentID,$topic_handler,$user_topic_key);
	eval{
		# defer constraints
		$user_handler->set_to_deferred();
		# insert User Topic
		$AgentID = $Foswiki::cfg{AdminUserKey};
		$topic_handler = bless $user_handler, *Foswiki::Contrib::DBIStoreContrib::TopicHandler;
		$user_topic_key = $topic_handler->_insertUserTopic($web_name,$topic_name,$AgentID);
		# insert User
		$user_handler = bless $topic_handler, *Foswiki::Contrib::DBIStoreContrib::UserHandler;
		$cUID = $user_handler->insertUser($login,$web_name,$topic_name,$passwordE,$emails,$user_topic_key);
		##### complete transaction with commit #####
		$user_handler->database_connection()->commit;
	};
	if ($@) {
		warn "Rollback - failed to save user ($web_name,$topic_name) for reason:\n $@";
		$topic_handler->database_connection()->errstr;
		eval{
			$topic_handler->database_connection()->rollback;
		};
	}
	
	return $cUID;
}

=pod 

---++++ getLoginName ($cUID) -> $login

Converts an internal cUID to that user's login
(undef on failure)

=cut

sub getLoginName {
	my ($this, $cUID) = @_;
	my $user_key = $cUID;  # only to make the code easier to read
	my $user_handler = Foswiki::Contrib::DBIStoreContrib::UserHandler::->init($this->{site_handler});
	my $login_name = $user_handler->getLoginName_User($user_key);
	
	return $login_name;
}


=pod

---++++ getWikiName ($cUID) -> wikiname

Maps a canonical user name to a wikiname

=cut

sub getWikiName {
  	my ($this, $cUID) = @_;
	my $user_key = $cUID;  # only to make the code easier to read
	my $user_handler = Foswiki::Contrib::DBIStoreContrib::UserHandler::->init($this->{site_handler});
	my $return_hash = $user_handler->getWikiName_User($user_key);
	return undef unless $return_hash;
	my $blob_return = $user_handler->get_blob_value($return_hash->{bytea_topic_name});
	my $topic_name = $blob_return->{$return_hash->{bytea_topic_name}};
	my $wiki_name = $return_hash->{web_name}.'.'.$topic_name;
	# returns 'Main.Admin'
	return $wiki_name;
}

=pod 

---++++ getEmails($cUID) -> @emails

emails might be stored in the ldap account as well if
the record is of type possixAccount and inetOrgPerson.
if this is not the case we fallback to the default behavior

=cut

sub getEmails {
	my ($this, $user_key) = @_;
	my $user_handler = Foswiki::Contrib::DBIStoreContrib::UserHandler::->init($this->{site_handler});
	my $emailstring = $user_handler->getEmailsWithUserKey($user_key);
	# return the first email....
	return $emailstring;
}



=pod

---++++ userExists($cUID) -> $boolean

Determines if the user already exists or not. 

=cut

sub userExists {
	my ($this, $cUID) = @_;

	# only users in the sql database are considered
	my $loginName = $this->getLoginName($cUID);
	return 0 unless $loginName;
}

=pod

---++++ eachUser () -> listIterator of cUIDs

returns a list iterator for all known users

=cut

sub eachUser {
	my $this = shift;

	my @allCUIDs = ();
	my $user_handler = Foswiki::Contrib::DBIStoreContrib::UserHandler::->init($this->{site_handler});
	@allCUIDs = @{$user_handler->getAllUsers()}; #returns list of cUID
	my $Iter = new Foswiki::ListIterator(\@allCUIDs);
	return $Iter;
}

=pod

---++++ eachGroup () -> listIterator of groupnames

returns a list iterator for all known groups

=cut

sub eachGroup {
	my $this = shift;

	my @allGroupKeys = ();
	my $group_handler = Foswiki::Contrib::DBIStoreContrib::GroupHandler::->init($this->{site_handler});
	@allGroupKeys = @{$group_handler->getAllGroups()}; #returns list of cUID
	# need to get a list of Web.Topic names
	my @groupWT;
	foreach my $gkey (@allGroupKeys){
		# getWikiName_User(cUID) -> { web_name => Main, topic_name => 'Admin'} hash return
		my $WTref = $group_handler->getWikiName_Group($gkey);
		push(@groupWT,$WTref->{web_name}.'.'.$WTref->{topic_name});
	}
	my $Iter = new Foswiki::ListIterator(\@groupWT);
	return $Iter;
}


=pod

---++++ eachGroupMember ($groupName) ->  listIterator of cUIDs

returns a list iterator for all groups members

=cut

sub eachGroupMember {
	my ($this, $group_name, $expand) = @_;
	my ($web_name,$topic_name) = Foswiki::Func::normalizeWebTopicName($Foswiki::cfg{UsersWebName},$group_name);
	my $user_handler = Foswiki::Contrib::DBIStoreContrib::UserHandler::->init($this->{site_handler});
	# 1-group_key, 2-group_name (one or the other plz!)
	return new Foswiki::ListIterator($user_handler->getGroupMembers("","$web_name.$topic_name"));
}

=pod

---++++ eachMembership ($cUID) -> listIterator of groups this user is in

returns a list iterator for all groups a user is in.

=cut

sub eachMembership {
	my ($this, $cUID) = @_;
	my $user_handler = Foswiki::Contrib::DBIStoreContrib::UserHandler::->init($this->{site_handler});
	my $it = new Foswiki::ListIterator( $user_handler->getUserMembers($cUID));
	return $it;
}

=pod

---++++ isGroup($user) -> $boolean

Establish if a user object refers to a user group or not.
This returns true for the <nop>SuperAdminGroup or
the known LDAP groups. Finally, if =nativeGroupsBackoff= 
is set the native mechanism are used to check if $user is 
a group

=cut

sub isGroup {
  my ($this, $user) = @_;

  return 0 unless $user;
  #writeDebug("called isGroup($user)");

  # may be called using a user object or a wikiName of a user
  my $wikiName = (ref $user)?$user->wikiName:$user;

  # special treatment for build-in groups
  return 1 if $wikiName eq $Foswiki::cfg{SuperAdminGroup};

  my $isGroup;

  if ($this->{ldap}{mapGroups}) {
    # ask LDAP
    $isGroup = $this->{ldap}->isGroup($wikiName);
  }

  # backoff if it does not know
  if (!defined($isGroup) && $this->{ldap}{nativeGroupsBackoff}) {
    $isGroup = $this->SUPER::isGroup($user) if ref $user;
    $isGroup = ($wikiName =~ /Group$/); 
  }

  return $isGroup;
}

# check to see if a user $cUID is in $group
sub isInGroup {
	my $this = shift;
	
	my ( $cUID, $group, $options ) = @_;
	my $user_handler = Foswiki::Contrib::DBIStoreContrib::UserHandler::->init($this->{site_handler});
	my @group_keys = @{$user_handler->getUserMembers($cUID)};
	return undef unless scalar(@group_keys)>0;
	# need to get group key of group
	my @single_group_key = @{$user_handler->fetchcUIDOrGroupKeyByWikiName($group)};
	return undef unless @single_group_key;
	
	my $SingleGroup = $single_group_key[0];
	# find out if user is in the group
	my $truth = undef;
	foreach my $sg (@group_keys){
		return 1 if $sg eq $SingleGroup;
	}
	return 0;
}

# check to see if a user $cUID is in the admin group
sub isInAdminGroup {
	my $this = shift;
	my $cUID = shift;
	
	# get the group key
	my $admin_group = $Foswiki::cfg{SuperAdminGroupKey};
	my $user_handler = Foswiki::Contrib::DBIStoreContrib::UserHandler::->init($this->{site_handler});
	
	# get all of the groups that the user is in
	my @group_keys = @{$user_handler->getUserMembers($cUID)};
	return undef unless scalar(@group_keys)>0;
	
	# find out if user is in the group
	my $truth = undef;
	foreach my $sg (@group_keys){
		return 1 if $sg eq $admin_group;
	}
	return 0;
}
=pod

---++++ findUserByEmail( $email ) -> \@cUIDs
   * =$email= - email address to look up

Return a list of canonical user names for the users that have this email
registered with the password manager or the user mapping manager.

=cut

sub findUserByEmail {
  my ($this, $email) = @_;

  return $this->{ldap}->getLoginOfEmail($email);
}

=pod 

---++++ findUserByWikiName ($wikiName) -> list of cUIDs associated with that wikiname

See baseclass for documentation

=cut

sub findUserByWikiName {
	my ($this, $wikiName) = @_;
	my ($web_name,$topic_name) = Foswiki::Func::normalizeWebTopicName($Foswiki::cfg{UsersWebName},$wikiName);
	my $user_handler = Foswiki::Contrib::DBIStoreContrib::UserHandler::->init($this->{site_handler});
	my $user_key = $user_handler->fetchcUIDwithWikiName($web_name,$topic_name);
	return $user_key;
}

=pod

---++++ handlesUser($cUID, $login, $wikiName) -> $boolean

Called by the Foswiki::Users object to determine which loaded mapping
to use for a given user.

The user can be identified by any of $cUID, $login or $wikiName. Any of
these parameters may be undef, and they should be tested in order; cUID
first, then login, then wikiName. 

=cut

sub handlesUser {
	my ($this, $cUID, $login_name, $wikiName) = @_;

	# TODO: fix this mess...
=pod
	print "cUID: $cUID or login: $login_name or wikiName: $wikiName\n";
	# TODO: change "Main" to the userweb defined elsewhere

	my ($web_name,$topic_name) = Foswiki::Func::normalizeWebTopicName($Foswiki::cfg{UsersWebName},$wikiName);

	return 1 if ( defined($cUID)     && defined( $this->userExists($cUID) ) );
	return 1 if ( defined($login_name)    && defined( $this->login2cUID($login_name) ) );
	return 1 if ( defined($wikiName) && defined( $user_handler->fetchcUIDwithWikiName($web_name,$topic_name) ) );
=cut
	return 1;
}

=pod

---++++ login2cUID($loginName, $dontcheck) -> $cUID

Convert a login name to the corresponding canonical user name. The
canonical name can be any string of 7-bit alphanumeric and underscore
characters, and must correspond 1:1 to the login name.
(undef on failure)

(if dontcheck is true, return a cUID for a nonexistant user too.
This is used for registration)

=cut

sub login2cUID {
	my ($this, $login_name, $dontcheck) = @_;
	my $user_handler = Foswiki::Contrib::DBIStoreContrib::UserHandler::->init($this->{site_handler});
	my $cUID = $user_handler->fetchcUIDwithLogin($login_name);
	return $cUID;
}

=pod

---++++ groupAllowsChange($group, $cuid) -> boolean

normally, ldap-groups are read-only as they are maintained
using ldap-specific tools.

this method only returns 1 if the group is a topic-based group

=cut

sub groupAllowsChange {
	my ($this, $group, $cuid) = @_;

	# TODO: requires user permissions to be read from MetaPreferences

	return 1;
}
# (cUID) -> boolean      1 for admin, 0 for not an admin
sub isAdmin {
	my $this = shift;
	my $cUID = shift;
	my $user_handler = Foswiki::Contrib::DBIStoreContrib::UserHandler::->init($this->{site_handler});
	my $site_admin = $user_handler->fetchSiteAdmin();
	return 1 if $site_admin eq $cUID;
	return 0 unless $site_admin eq $cUID;

}

=pod TML

---+++ addUserToGroup( $group, $id, $create ) -> $boolean

   * $id can be a login name or a WikiName

=cut

sub addUserToGroup {
	my ($this, $user, $group, $create ) = @_;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($this->{site_handler});
	
	my $user_handler = bless $topic_handler, *Foswiki::Contrib::DBIStoreContrib::UserHandler;
	
	return undef;
}

=pod TML

---+++ changeGroupMemberShip( $groupName,\@clean_add_list,\@clean_remove_list) -> $boolean

   * $id can be a login name or a WikiName

=cut

sub changeGroupMemberShip {
	my ($this, $groupName,$addUsers,$removeUsers ) = @_;
	
	# need to get the meta topic for the group being modified
	my ($gweb,$gtopic) = Foswiki::Func::normalizeWebTopicName($Foswiki::Plugins::SESSION->{webName},$groupName);
	my $group_meta = new Foswiki::Meta($Foswiki::Plugins::SESSION, $gweb, $gtopic );
	$group_meta->load();
	my @temp_current_links = $group_meta->find('LINK');
	
	# separate the non-member links from the member links
	# so that we can just work with the member links and splice everything back together when we save
	# use a hash instead of an array to make sure we don't double count
	my %current_members;
	my %ex_mem_links;
	foreach my $link01 (@temp_current_links){
		$ex_mem_links{$link01->{name}} = $link01 if $link01->{link_type} ne 'MEMBER';
		$current_members{$link01->{name}} = $link01 if $link01->{link_type} eq 'MEMBER';
	}
	# with the group_meta loaded, we just need to add some links to the meta object
	# we need these points: (require => [ 'link_type' ], allow => [ 'dest_t', 'dest_th', 'dest_a', 'dest_ah', 'blob_key' ])
	
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($this->{site_handler});
	
	# need to make a list of links to shove into the group topic upon saving
	my @nameAssembly;
	# user who will be added to the group
	foreach my $adder (@$addUsers){
		my $adder_topic_key = $topic_handler->_convert_WT_Topics_in($adder);
		return undef unless $adder_topic_key;
		my $alinker;
		$alinker->{link_type} = 'MEMBER';
		$alinker->{dest_t} = $adder_topic_key;
		# the point of this part is b/c we are using putKeyed in the Meta Object
		# we need to include all of the keys because the Meta index includes the commas from the join()
		@nameAssembly = ($alinker->{link_type},$alinker->{dest_t},$alinker->{dest_th},$alinker->{dest_a},$alinker->{dest_ah},$alinker->{blob_key});
		$alinker->{name} = join(',',@nameAssembly);
		$current_members{$alinker->{name}} = $alinker;
		#$group_meta->putKeyed('LINK',$alinker);
	}
	# user who will be removed to the group
	foreach my $remover (@$removeUsers){
		my $remover_topic_key = $topic_handler->_convert_WT_Topics_in($remover);
		return undef unless $remover_topic_key;
		my $rlinker;
		$rlinker->{link_type} = 'MEMBER';
		$rlinker->{dest_t} = $remover_topic_key;
		# we need to include all of the keys because the Meta index includes the commas from the join()
		@nameAssembly = ($rlinker->{link_type},$rlinker->{dest_t},$rlinker->{dest_th},$rlinker->{dest_a},$rlinker->{dest_ah},$rlinker->{blob_key});
		$rlinker->{name} = join(',',@nameAssembly);
		delete $current_members{$rlinker->{name}};
	}
	
	# save the group_meta
	$group_meta->putAll('LINK', values %current_members, values %ex_mem_links);
	$group_meta->save;

	return 1;
}

=pod TML

---+++ createNewGroup( $group, $id, $create ) -> $boolean

   * $id can be a login name or a WikiName

=cut

sub createNewGroup {
	my ($this,$cUID,$group,$groupTopic,$userlist,$email) = @_;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($this->{site_handler});
	$topic_handler->database_connection()->{AutoCommit} = 0;
	$topic_handler->database_connection()->{RaiseError} = 1;
	########## Insert the Group Topic First ###########
	$topic_handler->set_to_deferred();
	# load the groupTopic
	my (%topicrow,%throw);
	$throw{topic_key} = $topic_handler->createUUID();
	$throw{user_key} = $cUID;
	$throw{web_key} = $topic_handler->{web_cache}->{$groupTopic->web};
	$throw{timestamp_epoch} = time();
	$throw{topic_name_key} = $topic_handler->insert_Blob_Store($groupTopic->topic);
	$throw{topic_content_key} = $topic_handler->insert_Blob_Store( qq^---+!! \%TOPIC\% Group\n\n   * Member list (comma-separated list): 
      * Set GROUP = $userlist\n   * Persons/group who can change the list: \n      * Set ALLOWTOPICCHANGE = AdminGroup^ );
	$throw{revision} = 1;
	$throw{key} = $topic_handler->_createTHkey(\%throw);
	$topic_handler->insertTHRow(\%throw);

	$topicrow{key} = $throw{topic_key};
	$topicrow{link_to_latest} = $throw{key};
	$topicrow{current_web_key} = $throw{web_key};
	$topicrow{current_topic_name} = $throw{topic_name_key};
	$topic_handler->insertTopicRow(\%topicrow);

	my $user_handler = bless $topic_handler, *Foswiki::Contrib::DBIStoreContrib::UserHandler;
	# load group_history row
	my (%grouprow,%ghrow);
	$ghrow{key} = '';
	$ghrow{group_key} = $user_handler->createUUID();
	$ghrow{email} = $email || '';
	$ghrow{timestamp_epoch} = time();
	$ghrow{user_key} = $cUID;
	$ghrow{key} = $user_handler->_createGHkey(\%ghrow);
	$user_handler->insertGHRow(\%ghrow);
	# load group row
	$grouprow{key} = $ghrow{group_key};
	$grouprow{link_to_latest} = $ghrow{key};
	$grouprow{site_key} = '';
	$grouprow{group_topic_key} = $throw{topic_key};
	$user_handler->insertGroupRow(\%grouprow);

	##### start the transaction #####
	$user_handler->database_connection()->{AutoCommit} = 0;
	$user_handler->database_connection()->{RaiseError} = 1;

	##### complete transaction with commit #####
	$user_handler->database_connection()->commit;
	$user_handler->database_connection()->{AutoCommit} = 1;
	## Reload the group topic and save it again
	$groupTopic->load();
	my $newText = $groupTopic->text.' ';
	$groupTopic->save();
	return $cUID;

}

1;
__END__

